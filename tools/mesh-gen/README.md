# mesh-gen: part-built Luau models -> smooth organic meshes with baked PBR textures

Prototype pipeline (GoldGuppy, TreasureTurtle, Shopkeeper). It reads the *exported* part geometry of a buildscript
(`tools/model-preview/export.mjs`), never the buildscript itself, and does not touch `src/` or `assets/models/`.

## Run

Requirements: Python 3 with `numpy scipy scikit-image trimesh xatlas Pillow fast_simplification`
(`pip install fast_simplification`), Node + three.js + Playwright/Chromium for the preview (already used by `tools/model-preview`).

    LUAU=/path/to/luau THREE_DIR=/path/to/node_modules/three tools/mesh-gen/run.sh            # all 3 prototype models
    LUAU=... tools/mesh-gen/run.sh GoldGuppy                                                   # one model

Manual steps: `node tools/model-preview/export.mjs --luau $LUAU --only GoldGuppy --out tools/mesh-gen/cache/models.json`,
then `python3 tools/mesh-gen/pipeline.py --models tools/mesh-gen/cache/models.json --model GoldGuppy [--fast]`
(`--fast` = half resolution for quick iteration), then `node tools/mesh-gen/preview.mjs --three $THREE_DIR --models ...`
(writes `docs/previews/mesh-prototype.png`). `cache/` is git-ignored. A full run takes about 4 minutes for the three models.

Adding a model: add a `Cfg` subclass in `models.py` (sculpt extras/warps, texture patterns, budgets) and register it in `CONFIGS`.
Unknown models fall back to the default `Cfg` (plain smooth-union blobs with generic skin bumps).

## Pipeline

1. **Parts -> SDF.** Block = rounded box, Ball / SpecialMesh Sphere = ellipsoid, Cylinder = rounded cylinder (same shape rules as
   `model-preview/render.html`, including "Ball uses its smallest axis"). Parts are combined with a polynomial smooth-min
   (`k` per group/part in `models.py`). Sculpt layer: coordinate warps (fish tail taper, fin sweep), extra blobs (cheeks, belly),
   soft creases (gill line, shell lip, mouth slit), shell plate grooves (turtle, Voronoi on the dome), scallop ridges (shopkeeper),
   low-frequency fbm wobble so nothing is perfectly geometric.
2. **Mesh.** skimage marching cubes (~200-230 cells on the longest axis) -> Taubin smoothing -> quadric decimation
   (`fast_simplification`) to the per-mesh budget -> vertices re-projected onto the exact SDF surface, normals = SDF gradient.
3. **UVs** with xatlas (1 chart set per mesh, 6 px padding, edge-dilated textures).
4. **Bake** (texels evaluated against the SDF, so colour is continuous across UV seams):
   - `ColorMap`: nearest/deepest part colour, softmax-blended over `blend_tau`; decals (Blush, Mouth, Seams, ShellMark ...) painted
     on; cartoon shading (lighter belly, darker+more saturated crevices from SDF ambient occlusion, incl. neighbouring meshes);
     material patterns (fish scales, turtle plate rings, skin pebbles, fin rays, fabric weave).
   - `NormalMap`: tangent space, OpenGL / +Y convention (glTF standard). Roblox: if lighting looks inverted, flip the green channel.
   - `RoughnessMap`, `MetalnessMap` (Foil/Metal parts -> 0.9), optional `EmissiveMask` (only if the mesh contains Neon parts).
   - Textures are posterised slightly (colour step 3, normal step 6, roughness step 8) to keep PNG/GLB sizes small.
5. **Export** per model into `assets/meshes/<Model>/`: `<Model>_<Mesh>.obj` (+ 4-5 PNGs), `<Model>.glb` (all meshes as named nodes with
   embedded PBR textures) and `manifest.json`. Identical meshes (Eye1/Eye2, mirrored-identical legs) are generated once and referenced
   by several manifest entries (`sharedWith`).

## Grouping rule (which parts become separate meshes)

* The PrimaryPart (`Body`) mesh is the base group.
* **Roots** (own mesh, pivot = original part CFrame): names starting (case-insensitive) with
  `tailfin dorsalfin sidefin wing tentacle spinespike tailtip tip lowerjaw horn nose facet claw antenna leg` (list from
  `ModelAnimation/IdleSway.lua`), plus `Eye1`/`Eye2` always, plus `Head ArmL ArmR` for NPC models.
  Roots are never merged into each other (a `Leg...Tip` is its own root because IdleSway animates it by name).
* **Every other part** joins a root if (a) it shares its first CamelCase word with exactly one root (`TailLamella1` -> `TailFin`), or
  (b) its centre is within 0.15 studs of the root's surface (smallest signed distance wins: `EyeWhite1`, `EyePupilL` -> eye,
  `EyeStalkL` -> `Head`, `ArmStalkL` -> `ArmL`). Otherwise it goes into the body mesh (shell, satchel, blush ...).
* Fully transparent parts (`TailFin` 0.3 cube, transparency 1) only provide the pivot; their name is still in `replaces`.
* Eyes are UV spheres with the pole on the gaze axis: sclera, iris ring, pupil, highlight + secondary catch-light baked, glossy roughness.

## Manifest (`manifest.json`)

Per mesh: `name` (= glTF node name = intended MeshPart name), `file`, `pivot` (original anchor part CFrame relative to the PrimaryPart,
12 numbers `x,y,z,R00..R22` row-major = `CFrame:GetComponents()` order), `center` (CFrame of the mesh bounding-box centre relative to the
PrimaryPart: Roblox recentres imported meshes on their bbox, so **MeshPart.CFrame = PrimaryPart.CFrame * CFrame.new(unpack(center))**),
`size` (bbox studs = MeshPart.Size), `replaces` (original part names to destroy), `material` (dominant Roblox material; `Neon` if >60%
of the surface is Neon), `materialMix`, `neon` (fraction, part names, advice), `transparency`, `textures`, `tris`, `collisionFidelity`,
`sharedWith`. For animation code that sets a part's CFrame by pivot: `MeshPart.PivotOffset = CFrame.new(-bboxCenterLocal)` where
`bboxCenterLocal = pivot:Inverse() * center` translation, so `:PivotTo(pivotCFrame)` reproduces the old part pose.
Convention unchanged: original coordinates, -Z = front, 1 stud = 1 glTF metre.

Neon: meshes that are fully Neon (Shopkeeper arms/claws) -> set `Material = Neon` (SurfaceAppearance is ignored on Neon). Small neon
accents inside a textured mesh (tail tips, keyhole, shell mark, eye highlights) are in the `EmissiveMask` PNG: use SurfaceAppearance
`EmissiveMaskContent` + `EmissiveStrength`, or keep a tiny Neon part/mesh at that spot.

Collision: everything is `CanCollide=false` in the old models. Use `CollisionFidelity = Box` for animated pieces and `Hull` for bodies
(never `Default`/`PreciseConvexDecomposition` - expensive), `CanQuery=false`, `CastShadow` as needed.

## Studio import

1. **Fastest:** Avatar/3D Importer (Home > Import 3D) -> pick `assets/meshes/<Model>/<Model>.glb`. It creates a Model with one named MeshPart per
   node and a SurfaceAppearance (Color/Normal/MetalnessRoughness) each. Check `Model.Name`, node names = manifest names.
   (glTF metallicRoughness is packed G=roughness, B=metalness; the importer splits it.)
2. **Manual / bulk:** Asset Manager > Bulk Import the `.obj` files (import as MeshPart, "Import only as model" off), then on each MeshPart add a
   `SurfaceAppearance` with `ColorMap`, `NormalMap`, `RoughnessMap`, `MetalnessMap` (and `EmissiveMaskContent` if present) uploaded from the PNGs.
   Textures are 1024x1024 for body meshes, 512x512 for heads, the guppy tail and eyes, 256x256 for small parts (fins, legs, arms, claws) to stay within the size budget; raise `tex()` in `models.py` for hero assets.
3. Note the resulting `rbxassetid://` MeshIds/TextureIds per mesh.

## Planned runtime integration (`src/shared/MeshConfig.lua`, not created yet)

    return { GoldGuppy = { Body = { MeshId = "rbxassetid://...", ColorMap = "...", NormalMap = "...", RoughnessMap = "...", MetalnessMap = "...",
                                   Center = CFrame.new(...), Size = Vector3.new(...), Pivot = CFrame.new(...), Replaces = { "Body" } }, TailFin = {...} } }

Buildscripts/spawners look up `MeshConfig[modelName]`; if all IDs are non-empty they build `MeshPart`s (positioned with
`PrimaryPart.CFrame * Center`, Size from the config, SurfaceAppearance from the ids, `PivotOffset` as above, destroying/never creating the
`Replaces` parts); otherwise they fall back to the existing part construction. A generator can emit this file from `manifest.json`
plus a `mesh-ids.json` filled in after upload.

## Known limits of the prototype

* Ball parts are round (smallest axis) like the existing preview; if Roblox really draws stretched ellipsoids the SDF rule in
  `Part.__init__` is the one line to change.
* Fine detail (scales, pores, plate rings) lives in the normal map; only plate grooves, ridges, creases and blobs are real geometry.
* Junctions between separate animated meshes (arm/claw, leg/foot) overlap rather than blend; the seam is hidden by shared colours only.
* xatlas charts are automatic (no hand-placed seams); textures are PNG (Roblox re-encodes on upload).

## Swapping the meshes into the game (ApplyMeshes)

`python3 tools/mesh-gen/make_apply_script.py` writes `assets/meshes/ApplyMeshes.lua`
(template: `apply_template.lua`, layout from every `manifest.json`). In Studio, Edit mode:

1. Run all buildscripts in `assets/models/**` as usual (`docs/release-checklist.md` §3).
2. Create a Folder `MeshImports` in Workspace. For each `assets/meshes/<Model>/<Model>.glb`:
   File → Import 3D, import it and move the resulting model into `MeshImports`, named exactly `<Model>`.
3. Paste `assets/meshes/ApplyMeshes.lua` into the Command Bar and run it.
   Each model with a complete import is swapped (part names, PrimaryPart, attributes, tags,
   attachments, prompts and lights carried over; `MeshSwapped = true` is set). Models without
   an import keep their parts.
4. Delete `MeshImports`, then save or publish.

Offline check (no Studio): `python3 tools/mesh-gen/test_apply.py --luau <luau>` runs every meshed
buildscript through the model-preview shim, fakes `MeshImports` from the manifests, runs
`ApplyMeshes.lua` and checks that each model is swapped, every mesh exists and no replaced part is left.
After a swap, a model's PrimaryPart is the new bbox-centred mesh; `GetPivot()`/`PivotTo()` keep the
original pivot through `PivotOffset`, so code should move models with PivotTo (all game code does).
