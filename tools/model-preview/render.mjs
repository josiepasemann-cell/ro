// Renders contact sheets from out/models.json with three.js in headless Chromium.
//
// usage: node render.mjs [--three /path/to/node_modules/three] [--out ../../docs/previews] [--only creatures,hub]
//        [--models out/models.json] [--textures ../../assets/textures] [--category <Name>]
//        [--model <Name>[,<Name>...]] [--script <path substring>]   one model, 4 large views -> <out>/<Name>.png
import { createServer } from "node:http";
import { readFileSync, writeFileSync, mkdirSync, existsSync, readdirSync } from "node:fs";
import { join, dirname, extname, normalize } from "node:path";
import { fileURLToPath } from "node:url";
import { createRequire } from "node:module";

const here = dirname(fileURLToPath(import.meta.url));
const args = process.argv.slice(2);
const opt = (k, d) => { const i = args.indexOf(k); return i >= 0 ? args[i + 1] : d; };
const threeDir = opt("--three", process.env.THREE_DIR || join(here, "node_modules", "three"));
const outDir = opt("--out", join(here, "..", "..", "docs", "previews"));
const only = opt("--only", "").split(",").filter(Boolean);
const modelsPath = opt("--models", join(here, "out", "models.json"));
const onlyModels = opt("--model", "").split(",").filter(Boolean);
const onlyScript = opt("--script", "");
if (!existsSync(join(threeDir, "build", "three.module.js"))) {
  console.error(`three.js not found at ${threeDir} (run: npm install in tools/model-preview, or pass --three)`);
  process.exit(1);
}

let chromium;
try { ({ chromium } = await import("playwright")); } catch {
  const req = createRequire(join(process.execPath, "..", "..", "lib", "node_modules", "x.js"));
  ({ chromium } = req("playwright"));
}

const data = JSON.parse(readFileSync(modelsPath, "utf8"));
const models = data.models;
const find = (cat) => models.filter((m) => m.category === cat);

// ------------------------------------------------------------------ labels
const RARITY = ["Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic"];
const TIER = ["Trash", "Elite", "Boss"];
function label(m) {
  const a = m.attributes;
  return a.CreatureName || a.DisplayName || a.EnemyName || a.EggName || m.name;
}
function sub(m) {
  const a = m.attributes;
  const bits = [];
  if (label(m) !== m.name) bits.push(m.name);
  if (a.Rarity) bits.push(a.Rarity);
  if (a.EnemyTier) bits.push(a.EnemyTier);
  if (a.Zone) bits.push(a.Zone);
  if (a.Event) bits.push("Event: " + a.Event);
  if (a.NpcId && a.NpcId !== m.name) bits.push(a.NpcId);
  bits.push(`${m.parts.length} parts`);
  return bits.join(" · ");
}
const cell = (m, extra = {}) => ({ models: [m.name], label: label(m), sub: sub(m), ...extra });

// ------------------------------------------------------------------ sheets
const creatures = find("Creatures").sort((a, b) => RARITY.indexOf(a.attributes.Rarity) - RARITY.indexOf(b.attributes.Rarity) || a.name.localeCompare(b.name));
const enemies = find("Enemies").sort((a, b) => TIER.indexOf(a.attributes.EnemyTier) - TIER.indexOf(b.attributes.EnemyTier) || a.name.localeCompare(b.name));
const buildings = find("Buildings");
const buildingTypes = [...new Set(buildings.map((b) => b.attributes.BuildingType))].sort();
const eggs = find("Gacha").filter((m) => m.name.startsWith("MysteryEgg")).sort((a, b) => RARITY.indexOf(a.attributes.EggTier) - RARITY.indexOf(b.attributes.EggTier));
const pickups = find("Pickups");
const decorations = find("Decorations");
const npcs = find("Npcs");
const hub = find("Hub");
const terrain = find("Terrain");
const have = (names) => names.filter((n) => models.some((m) => m.name === n)); // map-* sheets also render the pre-dressing state
const ZONES = ["SunZoneTerrainChunk", "TwilightZoneTerrainChunk", "MidnightZoneTerrainChunk", "HadalDepthsTerrainChunk"];


// ------------------------------------------------------------------ zone views (map-* sheets)
const hubModels = () => [...hub.map((m) => m.name), ...npcs.map((m) => m.name), "HubDressing"];
const ZONE_ENV = {
  sun: { bg: ["#8fe3ee", "#4cc0d2", "#1f86a0"], fog: 0x55c2d4, fogNear: 1.5, fogFar: 6, hemiSky: 0xd8f8ff, hemiGround: 0xf2d9a0, hemiI: 1.2, key: 0xffecc0, keyI: 2.0, rim: 0x80e0ff, rimI: 0.5, exposure: 1.0, bloom: 0.18 },
  twilight: { bg: ["#35358a", "#1b1c58", "#090a26"], fog: 0x1c1e5a, fogNear: 1.0, fogFar: 3.6, hemiSky: 0x8a82e0, hemiGround: 0x1c1c48, hemiI: 1.15, key: 0xb0a8ff, keyI: 1.4, rim: 0x40d8ff, rimI: 0.8, exposure: 1.0, bloom: 0.3 },
  midnight: { bg: ["#24100f", "#100708", "#030203"], fog: 0x140708, fogNear: 0.9, fogFar: 3.2, hemiSky: 0x7a5058, hemiGround: 0x120708, hemiI: 0.95, key: 0xffa890, keyI: 1.0, rim: 0xff5a20, rimI: 1.0, exposure: 1.05, bloom: 0.5 },
  hadal: { bg: ["#c8e6f6", "#7aa8cc", "#2c4a70"], fog: 0x80acd0, fogNear: 0.7, fogFar: 2.8, hemiSky: 0xdcf2ff, hemiGround: 0x506f94, hemiI: 0.95, key: 0xdcefff, keyI: 1.25, rim: 0x80b8ff, rimI: 0.6, exposure: 0.92, bloom: 0.3 },
  hub: { bg: ["#58b4c8", "#2c7e98", "#103a52"], fog: 0x2c7c98, fogNear: 1.3, fogFar: 5, hemiSky: 0xdcf4ff, hemiGround: 0xcaaa7c, hemiI: 1.45, key: 0xffe6bc, keyI: 2.1, rim: 0x70d0ff, rimI: 0.6, exposure: 1.0, bloom: 0.25 },
};
const ZONE_VIEWS = {
  "map-sun": { title: "Sun Zone - sandy reef shallows", short: "Sun Zone", tagline: "warm sand, coral, sunken pirate ship", chunk: "SunZoneTerrainChunk", dress: "SunZoneDressing", terrain: ["SunZoneTerrainChunk"], models: ["SunZoneTerrainChunk", "SunZoneDressing"], env: ZONE_ENV.sun,
    overview: { az: -30, el: 52, margin: 0.95 }, close: { az: -55, el: 26, margin: 0.8, focus: { center: [144, 6, 26], radius: 26 } }, closeLabel: "Pirate ship landmark", closeSub: "sunken wreck with gangway, treasure scatter", compare: { az: -30, el: 52, margin: 0.95 } },
  "map-twilight": { title: "Twilight Zone - kelp canyon at dusk", short: "Twilight Zone", tagline: "violet dusk, kelp canyon, cliff into the dark", chunk: "TwilightZoneTerrainChunk", dress: "TwilightZoneDressing", terrain: ["TwilightZoneTerrainChunk"], models: ["TwilightZoneTerrainChunk", "TwilightZoneDressing"], env: ZONE_ENV.twilight,
    overview: { az: 150, el: 52, margin: 0.95 }, close: { az: 125, el: 22, margin: 0.8, focus: { center: [-158, 8, -27], radius: 24 } }, closeLabel: "Kelp canyon", closeSub: "camera near the zone centre", compare: { az: -30, el: 52, margin: 0.95 } },
  "map-midnight": { title: "Midnight Zone - basalt and lava", short: "Midnight Zone", tagline: "black basalt, lava cracks, whale-bone gate", chunk: "MidnightZoneTerrainChunk", dress: "MidnightZoneDressing", terrain: ["MidnightZoneTerrainChunk"], models: ["MidnightZoneTerrainChunk", "MidnightZoneDressing"], env: ZONE_ENV.midnight,
    overview: { az: -30, el: 52, margin: 0.95 }, close: { az: 0, el: 22, margin: 0.8, focus: { center: [0, 8, 133], radius: 22 } }, closeLabel: "Whale-bone arena gate", closeSub: "camera near the zone centre", compare: { az: -30, el: 52, margin: 0.95 } },
  "map-hadal": { title: "Hadal Depths - crystal trench", short: "Hadal Depths", tagline: "pale ice, crystals, ancient temple", chunk: "HadalDepthsTerrainChunk", dress: "HadalDepthsDressing", terrain: ["HadalDepthsTerrainChunk"], models: ["HadalDepthsTerrainChunk", "HadalDepthsDressing"], env: ZONE_ENV.hadal,
    overview: { az: 150, el: 52, margin: 0.95 }, close: { az: 180, el: 18, margin: 0.8, focus: { center: [0, 10, -172], radius: 26 } }, closeLabel: "Ancient temple", closeSub: "camera near the zone centre", compare: { az: -30, el: 52, margin: 0.95 } },
  "map-hub": { title: "Tidal Market hub - cozy plaza", short: "Hub - Tidal Market", tagline: "sand plaza, docks, stalls with awnings", chunk: "TidalMarketHub", dress: "HubDressing", terrain: ["HubTerrain"], models: null, env: ZONE_ENV.hub,
    overview: { az: -30, el: 52, margin: 0.95 }, close: { az: 20, el: 24, margin: 0.8, focus: { center: [-500, 4, -440], radius: 50 } }, closeLabel: "Plaza edge close-up", closeSub: "camera at the plaza rim", compare: { az: -30, el: 52, margin: 0.95 } },
};
ZONE_VIEWS["map-hub"].models = hubModels();
function zoneStats(z) {
  const t = data.terrain && data.terrain.counts ? Object.entries(data.terrain.counts).filter(([k]) => z.terrain.some((s) => k.includes(s))).reduce((a, [, c]) => a + c.total, 0) : 0;
  const names = z.models;
  const parts = names.map((n) => models.find((m) => m.name === n)).filter(Boolean).reduce((a, m) => a + m.parts.length, 0);
  const neon = names.map((n) => models.find((m) => m.name === n)).filter(Boolean).reduce((a, m) => a + m.parts.filter((p) => p.material === "Neon").length, 0);
  return `${parts} parts (${parts ? ((neon / parts) * 100).toFixed(1) : 0}% Neon) + ${t} terrain fills`;
}

const sheets = {
  creatures: {
    title: "Creatures", subtitle: `${creatures.length} creatures, sorted by rarity · each cell framed individually (sizes not comparable)`,
    width: 1600, cols: 4, cells: creatures.map((m) => cell(m)),
  },
  "raid-enemies": {
    title: "Raid enemies", subtitle: "Trash → Elite → Boss · each cell framed individually",
    width: 1600, cols: 3, cells: enemies.map((m) => cell(m)),
  },
  buildings: {
    title: "Buildings — stage 1 / 2 / 3", subtitle: "one row per building type, upgrade stages left to right (same camera angle per row)",
    width: 1600, cols: 3, cellAspect: 0.72,
    cells: buildingTypes.flatMap((t) => [1, 2, 3].map((s) => {
      const m = buildings.find((b) => b.attributes.BuildingType === t && b.attributes.Stage === s);
      return m ? { models: [m.name], label: `${t} — Stage ${s}`, sub: `${m.name} · ${m.parts.length} parts`, view: { az: -35 } } : { models: [], label: `${t} — Stage ${s}`, sub: "missing" };
    })),
  },
  "eggs-pickups": {
    title: "Mystery eggs & pickups", subtitle: "gacha eggs Common → Mythic, then world pickups (GachaEggOpenVFX has no visible geometry, only emitters)",
    width: 1600, cols: 3, cells: [...eggs, ...pickups].map((m) => cell(m, { view: { az: -30, el: 18 } })),
  },
  decorations: {
    title: "Event decorations", subtitle: "one decoration per live event",
    width: 1600, cols: 3, cells: decorations.map((m) => cell(m)),
  },
  npcs: {
    title: "Hub NPCs", subtitle: "posed where the scripts place them in the hub, camera from each NPC's front",
    width: 1600, cols: 5, cellAspect: 1.35, cells: npcs.map((m) => cell(m, { view: frontView(m) })),
  },
  "hub-overview": {
    title: "Tidal Market hub", subtitle: "TidalMarketHub with the five NPC buildscripts placed into it",
    width: 1600, cols: 1, cellAspect: 0.6,
    cells: [
      { models: [...hub.map((m) => m.name), ...npcs.map((m) => m.name)], label: "TidalMarketHub + NPCs — full footprint", sub: `${hub.reduce((a, m) => a + m.parts.length, 0)} hub parts · ${npcs.length} NPCs`, view: { az: -30, el: 38, margin: 0.95 }, maxLights: 12 },
      { models: [...hub.map((m) => m.name), ...npcs.map((m) => m.name)], label: "Central plaza close-up", sub: "same scene, camera focused on the landmark and stands", view: { az: -30, el: 30, margin: 0.86, focus: { center: hub[0]?.primary ? hub[0].primary.slice(0, 3) : [0, 0, 0], radius: 55 } }, maxLights: 16 },
    ],
  },
  // Map previews: sculpted Workspace.Terrain + chunk/hub + its world/*Dressing model. Each zone is rendered with a
  // lighting/fog mood that approximates its src/client/ZoneAtmosphere.client.lua profile, so identity differences show.
  ...Object.fromEntries(Object.entries(ZONE_VIEWS).map(([key, z]) => [key, {
    title: `${z.title}`, subtitle: `${z.chunk} + ${z.dress} + Workspace.Terrain (particles and animation not shown)`,
    width: 1600, cols: 1, cellAspect: 0.62,
    cells: [
      { models: have(z.models), terrain: z.terrain, env: z.env, label: "Overview", sub: zoneStats(z), view: z.overview, maxLights: 10 },
      { models: have(z.models), terrain: z.terrain, env: z.env, label: z.closeLabel, sub: z.closeSub, view: z.close, maxLights: 14 },
    ],
  }])),
  "map-zones-compare": {
    title: "Abyssara zones side by side", subtitle: "Hub (cozy market) / Sun Zone / Twilight Zone / Midnight Zone / Hadal Depths - same camera elevation, each with its own palette, ground, landmarks and fog mood",
    width: 3000, cols: 5, cellAspect: 1.05,
    cells: ["map-hub", "map-sun", "map-twilight", "map-midnight", "map-hadal"].map((k) => { const z = ZONE_VIEWS[k]; return { models: have(z.models), terrain: z.terrain, env: z.env, label: z.short, sub: z.tagline, view: z.compare, maxLights: 8 }; }),
  },
  terrain: {
    title: "Zone terrain chunks (Workspace.Terrain + landmark parts)", subtitle: "SunZone - TwilightZone - MidnightZone - HadalDepths, each with its own lighting mood, plus the habitat plot base",
    width: 1600, cols: 2, cellAspect: 0.66,
    cells: [...ZONES.map((n) => terrain.find((t) => t.name === n)).filter(Boolean).map((m) => {
      const key = m.name.replace("ZoneTerrainChunk", "").replace("DepthsTerrainChunk", "").toLowerCase();
      return { models: [m.name], terrain: [m.name], env: ZONE_ENV[key === "sun" ? "sun" : key === "twilight" ? "twilight" : key === "midnight" ? "midnight" : "hadal"], label: m.name, sub: `${m.parts.length} parts`, view: { az: -30, el: 50, margin: 0.95 }, maxLights: 6 };
    }), ...terrain.filter((t) => !ZONES.includes(t.name)).map((m) => cell(m, { view: { az: -30, el: 34, margin: 0.92 }, maxLights: 10 }))],
  },
};

// ------------------------------------------------------------------ --terrain <script substring>: terrain-only debug sheet
const onlyTerrain = opt("--terrain", "");
if (onlyTerrain) {
  for (const k of Object.keys(sheets)) delete sheets[k];
  sheets[`terrain-${onlyTerrain.replace(/\W+/g, "_")}`] = {
    title: `Terrain: ${onlyTerrain}`, subtitle: "Workspace.Terrain Fill* calls only (no parts)", width: 1600, cols: 1, cellAspect: 0.6,
    cells: [{ models: [], terrain: [onlyTerrain], label: "Overview", sub: "", view: { az: Number(opt("--az", -30)), el: Number(opt("--el", 38)), margin: 0.95 } },
            { models: [], terrain: [onlyTerrain], label: "Opposite side", sub: "", view: { az: Number(opt("--az", -30)) + 180, el: Number(opt("--el", 38)) * 0.6, margin: 0.95 } }],
  };
}

// ------------------------------------------------------------------ --category <Name>: one sheet with every model of that category
const onlyCategory = opt("--category", "");
if (onlyCategory) {
  for (const k of Object.keys(sheets)) delete sheets[k];
  const ms = find(onlyCategory);
  if (!ms.length) { console.error(`no models in category "${onlyCategory}" (in ${modelsPath})`); process.exit(1); }
  sheets[onlyCategory.toLowerCase()] = { title: onlyCategory, subtitle: `${ms.length} models`, width: 1600, cols: 5, cells: ms.map((m) => cell(m, { view: { az: -35, el: 22 } })) };
}

// ------------------------------------------------------------------ single-model sheets
if (onlyModels.length || onlyScript) {
  for (const k of Object.keys(sheets)) delete sheets[k];
  let picks = onlyModels.map((n) => models.find((m) => m.name === n) || models.find((m) => m.name.toLowerCase() === n.toLowerCase()) || n);
  const missing = picks.filter((p) => typeof p === "string");
  if (missing.length) { console.error(`unknown model(s): ${missing.join(", ")} (in ${modelsPath})`); process.exit(1); }
  if (onlyScript) {
    const s = onlyScript.replace(/^.*?assets\/models\//, "");
    const hit = models.filter((m) => m.script && m.script.includes(s));
    if (!hit.length) { console.error(`no exported model came from a script matching "${onlyScript}"`); process.exit(1); }
    picks.push(...hit);
  }
  for (const m of picks) {
    const base = m.primary ? frontView(m).az - 30 : 0; // az 0 = camera on the -Z (LookVector) side
    const views = [
      ["front 3/4", { az: base + 35, el: 16 }], ["side (right)", { az: base + 90, el: 8 }],
      ["back 3/4", { az: base + 215, el: 20 }], ["top-down 3/4", { az: base - 35, el: 58 }],
    ];
    sheets[m.name] = {
      title: label(m), subtitle: `${m.category} · ${sub(m)} · ${m.script || ""}`,
      width: 1600, cols: 2, cellAspect: 0.75,
      cells: views.map(([v, view]) => ({ models: [m.name], label: v, sub: m.name, view: { ...view, margin: 0.9 }, maxLights: 8 })),
    };
  }
}

// camera azimuth that looks at the model's PrimaryPart front (LookVector = -Z), turned 30° to the side
function frontView(m) {
  if (!m.primary) return {};
  const [, , , , , r02, , , r12, , , r22] = m.primary; // column 2 = back vector
  const look = [-r02, -r12, -r22];
  // camera sits in front: direction from model to camera = look
  // az convention in render.html: dir = (sin a, ., -cos a)
  const az = Math.atan2(look[0], -look[2]) * 180 / Math.PI + 30;
  return { az, el: 14 };
}

// ------------------------------------------------------------------ server + browser
const MIME = { ".js": "text/javascript", ".html": "text/html", ".json": "application/json", ".png": "image/png" };
const texturesDir = opt("--textures", join(here, "..", "..", "assets", "textures"));
const server = createServer((req, res) => {
  const url = decodeURIComponent(req.url.split("?")[0]);
  let file;
  if (url === "/" || url === "/render.html") file = join(here, "render.html");
  else if (url === "/models.json") file = modelsPath;
  else if (url.startsWith("/three/")) file = join(threeDir, normalize(url.slice(7)));
  else if (url.startsWith("/textures/")) {
    // Texture/Decal images: assets/textures/<TextureKey>.png (missing files -> 404, the page skips them)
    const rel = normalize(url.slice(10));
    if (!rel.startsWith("..") && !rel.startsWith("/")) file = join(texturesDir, rel);
  }
  if (url === "/textures/index.json") {
    const list = [];
    const walkTex = (d, pre) => { for (const f of existsSync(d) ? readdirSync(d, { withFileTypes: true }) : []) {
      if (f.isDirectory()) walkTex(join(d, f.name), pre + f.name + "/"); else if (f.name.endsWith(".png")) list.push(pre + f.name);
    } };
    walkTex(texturesDir, "");
    res.writeHead(200, { "content-type": "application/json" });
    res.end(JSON.stringify(list));
    return;
  }
  if (!file || !existsSync(file)) { res.writeHead(404); res.end(); return; }
  res.writeHead(200, { "content-type": MIME[extname(file)] || "application/octet-stream" });
  res.end(readFileSync(file));
});
await new Promise((r) => server.listen(0, "127.0.0.1", r));
const port = server.address().port;

const launchOpts = { args: ["--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist"] };
let browser;
try { browser = await chromium.launch(launchOpts); } catch (e) {
  const exe = process.env.CHROMIUM_PATH || "/opt/pw-browsers/chromium-1194/chrome-linux/chrome";
  browser = await chromium.launch({ ...launchOpts, executablePath: exe });
}
const page = await browser.newPage({ viewport: { width: 800, height: 600 } });
page.on("console", (msg) => { if (msg.type() === "error" || msg.type() === "warning") console.log("page:", msg.text()); });
page.on("pageerror", (e) => console.log("pageerror:", e.message));
await page.goto(`http://127.0.0.1:${port}/render.html`);
await page.waitForFunction(() => window.ready === true, null, { timeout: 60000 });

mkdirSync(outDir, { recursive: true });
for (const [name, spec] of Object.entries(sheets)) {
  if (only.length && !onlyModels.length && !onlyScript && !only.includes(name)) continue;
  const t0 = Date.now();
  const url = await page.evaluate((s) => window.renderSheet(s), spec);
  const file = join(outDir, `${name}.png`);
  writeFileSync(file, Buffer.from(url.split(",")[1], "base64"));
  console.log(`wrote ${file} (${((Date.now() - t0) / 1000).toFixed(1)}s)`);
}
await browser.close();
server.close();
