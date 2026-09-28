# Model previews

These PNGs show what the buildscripts in `assets/models/**/*.lua` produce. Roblox Studio is not
involved. Each script runs unmodified under a small Roblox API shim written in Luau
(`tools/model-preview/shim.luau`). The Parts it creates are exported to JSON, and three.js renders
them in headless Chromium.

| File | Contents |
| --- | --- |
| `creatures.png` | All creatures, sorted by rarity |
| `raid-enemies.png` | Raid enemies, from trash up to the boss |
| `buildings.png` | Each building type at stages 1, 2 and 3 |
| `eggs-pickups.png` | Mystery eggs (Common to Mythic) and world pickups |
| `decorations.png` | Event decorations |
| `npcs.png` | Hub NPCs, posed where their scripts place them |
| `hub-overview.png` | TidalMarketHub plus its NPCs: the full footprint and a plaza close-up |
| `terrain.png` | The four zone terrain chunks and HabitatPlotBase |

Every cell is framed separately, so sizes can't be compared between cells.

## How faithful the renders are

- **Geometry, colours, materials and transparency** come straight from the scripts (materials are drawn as approximations, see below). Cylinders run
  along X, and wedges slope the way Roblox wedges do. Balls are drawn as spheres whose diameter is
  the smallest axis of `Size`, because Roblox does not stretch balls into ellipsoids. Many
  creatures, eggs and NPCs set non-uniform `Size` on a Ball, so they look rounder or smaller here
  than their authors may have intended. This is also how they would look in Roblox.
- **Meshes**: a `SpecialMesh`, `BlockMesh` or `CylinderMesh` child replaces the part's shape. The
  mesh fills `Size * Scale` and is shifted by `Offset` in part space. Use a `Sphere` SpecialMesh
  for eggs and ellipsoid bodies, because it stretches non-uniformly where a Ball does not. The
  renderer draws the mesh types this way:
  - `Sphere`: an ellipsoid.
  - `Cylinder` (SpecialMesh): runs along X like a Cylinder part, but its cross-section may be
    elliptical. This is an assumption, not checked in Studio.
  - `CylinderMesh` (legacy) and `Head`: a cylinder along Y. `Head` is approximated.
  - `Wedge`: a wedge.
  - `Brick`, `BlockMesh`, and `FileMesh` without the mesh file: a box.

  A new SpecialMesh defaults to `Head`, as in Roblox, so set `MeshType` explicitly. CSG operands
  ignore meshes. A MeshPart with no MeshId renders as a box.
- **Materials** are approximated, not copied from Roblox. Each `Material` gets a procedural
  surface pattern generated in the page (brick courses, wood grain, slate cracks, cobbles, brushed
  metal, foil crinkle, diamond plate and so on), with a matching bump and roughness. The pattern is
  multiplied with the part's `Color`. It is projected in part space and measured in studs, so a large
  part repeats the pattern instead of stretching it. `SmoothPlastic` stays plain. `Neon` glows.
  `Glass`, `Ice` and `Glacier` are glossy and see-through. `ForceField` is a translucent, glowing
  shimmer. `CrackedLava` is dark rock with glowing orange cracks. An unknown material renders like
  `Plastic`.
- **Textures and Decals**: a `Texture` or `Decal` child of a part is drawn on its `Face` when it has
  the attribute `TextureKey`. The image comes from `assets/textures/<TextureKey>.png`. Its
  `rbxassetid` `Texture` is not used. A `Texture` tiles every `StudsPerTileU/V` studs, shifted by
  `OffsetStudsU/V`. A `Decal` is stretched once over the face. Both are multiplied by `Color3`,
  respect `Transparency`, and draw over the part's own material. They show on Block faces and on a
  wedge's Back, Bottom and slope (`Top`). They are skipped on balls, cylinders, CSG results, and
  faces that have no image file yet. The first missing image is logged once.
- **CSG**: `UnionAsync`, `SubtractAsync` and `IntersectAsync` are not computed as meshes. The shim
  keeps the operands, and the renderer resolves the result for each pixel (it cuts away fragments
  inside a cutter, keeps only the overlap for intersections, and draws the cutter walls inside the
  base). Rings, holes, basins and the hexagonal plot therefore look right. When a script sets a
  colour or material on the result, that value overrides the operand colours (as with
  UsePartColor).
- **Random scatter** (terrain and hub decoration) uses the scripts' seeds, but the random generator
  is not Roblox's own. Positions of scattered props will differ from the ones you'd get in Studio.
- **Not shown**: particle emitters, beams, animation or tweens, and GUI (BillboardGui text, the
  GachaOddsPanel ScreenGui). `GachaEggOpenVFX` has only invisible anchors and emitters, so it isn't
  rendered. PointLights do light the scene, and Neon parts glow through a bloom pass. Lighting is a
  stylised deep-sea setup, not Roblox's lighting engine.

## Regenerating

```sh
cd tools/model-preview
npm install                      # three.js (0.160)
node export.mjs --luau /path/to/luau   # runs all buildscripts, writes out/models.json
node render.mjs                  # writes docs/previews/*.png (needs playwright + Chromium)
node render.mjs --only creatures,hub-overview   # render a subset
```

### Checking your own models (for agents editing buildscripts)

Use your own `--out` file so you don't overwrite anyone else's export:

```sh
cd tools/model-preview
LUAU=/path/to/luau
# 1. export a subset: folder/name substring or glob, relative to assets/models, comma-separated
node export.mjs --luau $LUAU --only creatures --out out/mine.json
node export.mjs --luau $LUAU --only 'creatures/Glow*.lua,gacha/MysteryEgg_*' --out out/mine.json
node export.mjs --luau $LUAU --only npcs --out out/npcs.json   # hub scripts are added automatically
# 2. find floating parts (meshes count as their Size*Scale box)
python3 check_connectivity.py --json out/mine.json [--category Creatures]
# 3. render one model large from 4 angles -> <out>/<Name>.png
node render.mjs --models out/mine.json --model GlowJelly --out out/png
node render.mjs --models out/mine.json --script creatures/GlowJelly.lua --out out/png
# or a whole sheet from your subset
node render.mjs --models out/mine.json --only creatures --out out/png
```

The part JSON has these optional fields when a part has a mesh child: `meshType` (a string such
as `"Sphere"`), `meshScale` `[x,y,z]` and `meshOffset` `[x,y,z]`.

Parts with `Texture`/`Decal` children also have `textures`: a list of objects with `class`, `face`,
`key` (the `TextureKey` attribute), `texture`, `color`, `transparency`, and, for a Texture,
`studsPerTile` and `offsetStuds`.

To try a scene that lives outside `assets/models`, use `node export.mjs --extra path/to/Test.lua
--out out/test.json`. Then `node render.mjs --models out/test.json --category <FolderName>` draws one
sheet with every model in that `Workspace.Assets` folder. `--textures <dir>` reads images from a
different directory than `assets/textures`.

`export.mjs` prints any script that errors under the shim. `render.mjs` takes a `--three <dir>`
argument if three.js is installed somewhere else. It uses the global `playwright` package, with
`CHROMIUM_PATH` as a fallback browser location.
