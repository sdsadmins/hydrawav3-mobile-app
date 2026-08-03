# 3D viewer build tooling

Builds the offline three.js viewers bundled into `assets/3d/`. All three are
**vanilla three.js forks** of web components — changes on the web do not
auto-flow here; re-port and rebuild.

## The three viewers

| Bundle | Source | Used by |
|---|---|---|
| `anatomy_scene.bundle.js` | `anatomy_scene.src.js` | Performance pad map + Recovery 3D placement (`AnatomySceneView`) |
| `pad_placement.bundle.js` | `pad_placement.src.js` | **Rollback only** — the older, simpler pad viewer (`PadAnatomyView`) |
| `viewer.bundle.js` | `viewer.src.js` | Kinetic chain, from the AI report (`KineticChain3DScreen`) |

`anatomy_scene.src.js` and `pad_placement.src.js` do the same job. The first is a
much closer port of `Hydrawave3/apps/web/src/components/AnatomyScene.jsx` and is
what both pad screens render today; the second is kept **untouched** as the
per-screen rollback path behind
`lib/features/pad_placement/presentation/widgets/anatomy_scene_flag.dart`.
Flipping either flag back needs no rebuild, because both bundles ship.

Once the flags have been through a release, delete `pad_placement.src.js`,
`pad_placement.html`, `pad_placement.bundle.js`, `pad_anatomy_view.dart` and the
`build:pads` script — that recovers ~630 KB of APK.

## Files

- `anatomy_scene.src.js` — the AnatomyScene port. Per-mesh anatomy materials,
  X-ray, focus/dim, Okabe-Ito set colours, labelled Sun→Moon set arcs, mesh
  anchors, badge cluster packing, tap-to-select. Read its header comment for the
  full list of what it adds over `pad_placement.src.js` and where it deliberately
  deviates from the web.
- `anatomy_landmarks.js` — **canonical** curated landmarks + `refineLandmark`.
  Verbatim from `AnatomyScene.jsx:39-397`.
- `anatomy_calibration.js` — AUTO-GENERATED, the 39 shared calibrated landmarks.
- `set_colors.js` — Okabe-Ito per-set palette. Mirrored in Dart as
  `kAnatomySetColors` in `pad_map_screen.dart`; change the two together.
- `mesh_anchors.js` — loads/indexes `assets/3d/perf_mesh_anchors.json` and does
  the anchor→seed maths.
- `pad_placement.src.js` — the older pad viewer. **Do not edit** while it is the
  rollback path.
- `viewer.src.js` — the kinetic-chain viewer.
- `muscle_resolve.js` — SHARED muscle-name → mesh-name resolution, imported by
  all three viewers. Fix name matching here and all three get it.
- `mapping.js` — AUTO-GENERATED from `Hydrawav3-ai/lib/zAnatomyMapping.ts`.

### Duplicated landmark tables — deliberate

`PAD_LANDMARKS` exists twice: in `anatomy_landmarks.js` (canonical, with the
`cue` prose and midline support) and inlined in `pad_placement.src.js:68-211`
(trimmed). Extracting the shared copy out of the older viewer would force a
rebuild of `pad_placement.bundle.js`, and the entire value of that file is that
it stays frozen. `verify-landmarks.mjs` proves the coordinates still agree with
the web, which is the property that actually matters.

## Rebuild

```bash
npm install          # once
npm run build        # -> ../../assets/3d/{viewer,pad_placement,anatomy_scene}.bundle.js
npm run build:anatomy   # just the AnatomyScene bundle
npm run verify          # assert the landmark tables still match the web
```

**Stale bundles are the recurring hazard here.** The checked-in bundles have gone
out of sync with their sources before. Both Dart widgets feature-detect every
bridge call (`window.fn && window.fn(...)`) so a stale bundle degrades rather
than throwing into a WebView nobody is watching, and `anatomy_scene.src.js` sets
`window.__viewerVersion`, which `AnatomySceneView` checks and `debugPrint`s on
mismatch. If the 3D looks wrong, run `npm run build` and check the log first.

## Regenerating the calibration table

```bash
npm run gen:calibration     # node extract-anatomy-calibration.mjs
npm run verify              # then confirm nothing drifted
```

Reads `Hydrawave3/packages/placement-core/src/knowledge/anatomyCalibration.js`.
Requires the `Hydrawave3` checkout to be a sibling of this repo.

## Re-extract the MAPPING dict (if the web mapping changed)

```bash
node -e 'const fs=require("fs");const s=fs.readFileSync("../../../Hydrawav3-ai/lib/zAnatomyMapping.ts","utf8").split(/\r?\n/);let a=s.findIndex(l=>l.includes("const MAPPING"));let b=-1;for(let i=a+1;i<s.length;i++){if(/^\};\s*$/.test(s[i])){b=i;break;}}let blk=s.slice(a,b+1).join("\n").replace(/const MAPPING\s*:\s*Record<[^>]*>\s*=/,"export const MAPPING =");fs.writeFileSync("mapping.js","// AUTO-GENERATED from Hydrawav3-ai/lib/zAnatomyMapping.ts\n\n"+blk+"\n");'
```

## `perf_mesh_anchors.json`

`assets/3d/perf_mesh_anchors.json` is a byte copy of
`Hydrawave3/apps/web/src/data/perfMeshAnchors.json` (v4.2, 242 meshes, 97 KB),
generated on the web side by `apps/web/scripts/derive-perf-mesh-anchors.mjs`.
Re-copy it whenever the GLB or that generator changes.

It is fetched at runtime, not bundled: it is data that changes with the model,
not with this code, and bundling would force an esbuild run on every re-derive.
Without it the viewer still works — every pad just falls to the coarser
bounding-box tier — so watch `anchorsHit` / `anchorsTotal` in
`window.getViewerState()`, because that degradation is silent on screen.

## Draco decoder

`assets/3d/draco/{draco_wasm_wrapper.js, draco_decoder.wasm}` are copied from
`node_modules/three/examples/jsm/libs/draco/`. Re-copy if the three version bumps
(`npm run copy-draco`).

## Manual smoke checklist

There is no JS test harness; `window.getViewerState()` is the JS-side assertion
surface. After a rebuild, check on a device:

1. **Performance** — Hub → Performance → chain → pad map. Set arcs in yellow /
   blue / green bowing *around* the torso; badges read "Sun"/"Moon"; a pad on the
   back is **hidden** by the torso when facing front; Muscle Mode off gives the
   X-ray; focusing a set dims the others; Mirror and Bilateral still produce the
   right pad counts.
2. **Recovery** — Hub → Recovery → assessment → 3D placement. Pads must land
   where the old viewer put them: recovery has no muscle list and is positioned
   purely by its curated zone. Compare against
   `kUseAnatomySceneRecovery = false` if in doubt.
3. `anchorsHit` close to `anchorsTotal` on the performance flow. A large gap
   means the anchor keys are not matching our mesh vocabulary and every pad has
   quietly dropped to the bounding-box tier.
4. No-WebGL: run an emulator with `-gpu guest`; the stage should show the
   fallback message and the written pad list below must stay usable.
