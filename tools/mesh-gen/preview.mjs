// Side-by-side render: old part-built models vs the new generated meshes (three.js + headless Chromium).
// usage: node preview.mjs --three <three dir> --models <models.json> [--meshes ../../assets/meshes]
//        [--names GoldGuppy,TreasureTurtle,Shopkeeper] [--out ../../docs/previews/mesh-prototype.png] [--cell 640x520]
import { createServer } from "node:http";
import { readFileSync, writeFileSync, existsSync, mkdirSync } from "node:fs";
import { join, dirname, extname, normalize, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { createRequire } from "node:module";
const here = dirname(fileURLToPath(import.meta.url));
const args = process.argv.slice(2);
const opt = (k, d) => { const i = args.indexOf(k); return i >= 0 ? args[i + 1] : d; };
const threeDir = opt("--three", process.env.THREE_DIR || join(here, "..", "model-preview", "node_modules", "three"));
const modelsPath = resolve(opt("--models", join(here, "cache", "models.json")));
const meshesDir = resolve(opt("--meshes", join(here, "..", "..", "assets", "meshes")));
const out = resolve(opt("--out", join(here, "..", "..", "docs", "previews", "mesh-prototype.png")));
const names = opt("--names", "GoldGuppy,TreasureTurtle,Shopkeeper").split(",");
const [cw, ch] = opt("--cell", "600x480").split("x").map(Number);
const views = [{ name: "front 3/4", az: 38, el: 16 }, { name: "back 3/4", az: 205, el: 24 }];
let chromium;
try { ({ chromium } = await import("playwright")); } catch {
  const req = createRequire(join(process.execPath, "..", "..", "lib", "node_modules", "x.js"));
  ({ chromium } = req("playwright"));
}
const config = { names, cellW: cw, cellH: ch, cols: views.length * 2, views, title: "Abyssara mesh pipeline prototype - OLD part models (left of each pair) vs NEW SDF meshes with baked PBR textures (right)" };
const MIME = { ".js": "text/javascript", ".html": "text/html", ".json": "application/json", ".png": "image/png", ".glb": "model/gltf-binary" };
const server = createServer((req, res) => {
  const url = decodeURIComponent(req.url.split("?")[0]);
  let file;
  if (url === "/") file = join(here, "preview.html");
  else if (url === "/models.json") file = modelsPath;
  else if (url === "/config.json") { res.writeHead(200, { "content-type": "application/json" }); res.end(JSON.stringify(config)); return; }
  else if (url.startsWith("/three/")) file = join(threeDir, normalize(url.slice(7)));
  else if (url.startsWith("/meshes/")) file = join(meshesDir, normalize(url.slice(8)));
  if (!file || !existsSync(file)) { res.writeHead(404); res.end(); return; }
  res.writeHead(200, { "content-type": MIME[extname(file)] || "application/octet-stream" });
  res.end(readFileSync(file));
});
await new Promise((r) => server.listen(0, "127.0.0.1", r));
const launch = { args: ["--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist"] };
let browser;
try { browser = await chromium.launch(launch); } catch { browser = await chromium.launch({ ...launch, executablePath: process.env.CHROMIUM_PATH || "/opt/pw-browsers/chromium-1194/chrome-linux/chrome" }); }
const page = await browser.newPage({ viewport: { width: 800, height: 600 } });
page.on("console", (m) => { if (["error", "warning"].includes(m.type())) console.log("page:", m.text()); });
page.on("pageerror", (e) => console.log("pageerror:", e.message));
await page.goto(`http://127.0.0.1:${server.address().port}/`);
await page.waitForFunction(() => window.ready === true, null, { timeout: 180000 });
const url = await page.evaluate(() => window.result);
mkdirSync(dirname(out), { recursive: true });
writeFileSync(out, Buffer.from(url.split(",")[1], "base64"));
console.log("wrote", out);
await browser.close(); server.close();
