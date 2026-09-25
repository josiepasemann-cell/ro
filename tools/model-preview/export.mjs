// Runs every buildscript in assets/models/** through the Luau API shim and
// writes the resulting part geometry to models.json.
//
// usage: node export.mjs [--luau /path/to/luau] [--out models.json] [--only <pattern>[,<pattern>...]]
//   --only: folder/file substring (e.g. "creatures", "creatures/Axolotl") or glob ("creatures/*Egg*.lua",
//   "**/npcs/**"), matched against the path relative to assets/models. Hub scripts are added automatically
//   when an NPC script is selected (NPC scripts look for the hub).
import { readFileSync, writeFileSync, readdirSync, statSync, mkdtempSync, mkdirSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { join, relative, dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { tmpdir } from "node:os";

const here = dirname(fileURLToPath(import.meta.url));
const repo = join(here, "..", "..");
const args = process.argv.slice(2);
const opt = (k, d) => { const i = args.indexOf(k); return i >= 0 ? args[i + 1] : d; };
const luau = opt("--luau", process.env.LUAU || "luau");
const out = opt("--out", join(here, "out", "models.json"));
mkdirSync(dirname(resolve(out)), { recursive: true });

function walk(dir) {
  return readdirSync(dir).flatMap((f) => {
    const p = join(dir, f);
    return statSync(p).isDirectory() ? walk(p) : p.endsWith(".lua") || p.endsWith(".luau") ? [p] : [];
  });
}
const modelsDir = join(repo, "assets", "models");
// hub first (NPC scripts look for it), npcs last, everything else alphabetical
const rank = (p) => (p.includes("/hub/") ? 0 : p.includes("/npcs/") ? 2 : 1);
let scripts = walk(modelsDir).sort((a, b) => rank(a) - rank(b) || a.localeCompare(b));
const only = opt("--only", "").split(",").map((s) => s.trim()).filter(Boolean);
if (only.length) {
  const toRe = (g) => new RegExp("^" + g.replace(/[.+^${}()|[\]\\]/g, "\\$&").replace(/\*\*\/?/g, "\u0000").replace(/\*/g, "[^/]*").replace(/\?/g, "[^/]").replace(/\u0000/g, ".*") + "$", "i");
  const rel = (p) => relative(modelsDir, p);
  const match = (p) => only.some((pat) => {
    pat = pat.replace(/^\.?\/?(assets\/models\/)?/, "");
    return /[*?]/.test(pat) ? toRe(pat).test(rel(p)) : rel(p).toLowerCase().includes(pat.toLowerCase());
  });
  const picked = scripts.filter(match);
  const needHub = picked.some((p) => p.includes("/npcs/"));
  scripts = scripts.filter((p) => picked.includes(p) || (needHub && p.includes("/hub/")));
  if (!scripts.length) { console.error(`--only ${only.join(",")} matched no scripts under ${modelsDir}`); process.exit(1); }
  console.log(`--only: running ${scripts.length} script(s)${needHub ? " (hub added for NPCs)" : ""}`);
}

const shim = readFileSync(join(here, "shim.luau"), "utf8");
const B = (s) => { let n = 6; while (s.includes("]" + "=".repeat(n) + "]")) n++; const e = "=".repeat(n); return `[${e}[\n${s}]${e}]`; };
let driver = `local shim = loadstring(${B(shim)}, "=shim")()\n`;
for (const s of scripts) driver += `shim.runScript(${JSON.stringify(relative(repo, s))}, ${B(readFileSync(s, "utf8"))})\n`;
driver += "shim.exportAll()\n";

const tmp = mkdtempSync(join(tmpdir(), "model-preview-"));
const driverPath = join(tmp, "driver.luau");
writeFileSync(driverPath, driver);
const stdout = execFileSync(luau, [driverPath], { maxBuffer: 1 << 28, encoding: "utf8" });

const models = [], errors = [], ok = [], warns = [];
for (const line of stdout.split("\n")) {
  if (line.startsWith("@@MODEL@@")) models.push(JSON.parse(line.slice(9)));
  else if (line.startsWith("@@ERROR@@")) errors.push(line.slice(9));
  else if (line.startsWith("@@OK@@")) ok.push(line.slice(6));
  else if (line.startsWith("@@WARN@@")) warns.push(line.slice(8));
  else if (line.trim() && !line.startsWith("@@PRINT@@")) console.log("luau:", line);
}
writeFileSync(out, JSON.stringify({ generated: new Date().toISOString(), models }, null, 0));
console.log(`scripts ok: ${ok.length}/${scripts.length}, models exported: ${models.length}, parts: ${models.reduce((a, m) => a + m.parts.length, 0)}`);
for (const w of warns) console.log("WARN", w);
for (const e of errors) console.log("ERROR", e);
if (errors.length) process.exitCode = 1;
