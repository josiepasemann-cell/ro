// Renders contact sheets from out/models.json with three.js in headless Chromium.
//
// usage: node render.mjs [--three /path/to/node_modules/three] [--out ../../docs/previews] [--only creatures,hub]
import { createServer } from "node:http";
import { readFileSync, writeFileSync, mkdirSync, existsSync } from "node:fs";
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
const ZONES = ["SunZoneTerrainChunk", "TwilightZoneTerrainChunk", "MidnightZoneTerrainChunk", "HadalDepthsTerrainChunk"];

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
  terrain: {
    title: "Zone terrain chunks", subtitle: "SunZone · TwilightZone · MidnightZone · HadalDepths, plus the habitat plot base",
    width: 1600, cols: 2, cellAspect: 0.66,
    cells: [...ZONES.map((n) => terrain.find((t) => t.name === n)).filter(Boolean), ...terrain.filter((t) => !ZONES.includes(t.name))].map((m) => cell(m, { view: { az: -30, el: 34, margin: 0.92 }, maxLights: 10 })),
  },
};

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
const MIME = { ".js": "text/javascript", ".html": "text/html", ".json": "application/json" };
const server = createServer((req, res) => {
  const url = decodeURIComponent(req.url.split("?")[0]);
  let file;
  if (url === "/" || url === "/render.html") file = join(here, "render.html");
  else if (url === "/models.json") file = modelsPath;
  else if (url.startsWith("/three/")) file = join(threeDir, normalize(url.slice(7)));
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
  if (only.length && !only.includes(name)) continue;
  const t0 = Date.now();
  const url = await page.evaluate((s) => window.renderSheet(s), spec);
  const file = join(outDir, `${name}.png`);
  writeFileSync(file, Buffer.from(url.split(",")[1], "base64"));
  console.log(`wrote ${file} (${((Date.now() - t0) / 1000).toFixed(1)}s)`);
}
await browser.close();
server.close();
