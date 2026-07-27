# Kinetic Chain 3D viewer — build tooling

Builds the offline three.js viewer bundled into `assets/3d/`, used by
`KineticChain3DScreen` (the mobile "3D-Pattern A/B" view). This is a **vanilla
three.js fork** of the web `Hydrawav3-ai` viewer — changes there do not auto-flow
here; re-port and rebuild.

## Files
- `viewer.src.js` — the ported kinetic-chain viewer (materials, camera, chain
  line, labels). Ported from `Hydrawav3-ai/lib/zAnatomyModel.ts`,
  `lib/zAnatomyMapping.ts`, and `components/ai/ZAnatomyViewer.tsx`.
- `pad_placement.src.js` — the Sun/Moon pad viewer (`AnatomyScene` port). Serves
  both the recovery placement engine and the performance pad sets; resolves a pad
  to a calibrated landmark, else to the target muscle's mesh geometry, else
  reports it on `window.__unmapped` and draws nothing.
- `muscle_resolve.js` — SHARED muscle-name → mesh-name resolution (normalize,
  static `MAPPING`, fuzzy, side filter) imported by both viewers. Fix name
  matching here and both get it.
- `mapping.js` — AUTO-GENERATED from `Hydrawav3-ai/lib/zAnatomyMapping.ts`
  (the `MAPPING` dict). Re-extract when the web mapping changes (see below).

## Rebuild
```bash
npm install          # once
npm run build        # -> ../../assets/3d/{viewer,pad_placement}.bundle.js
```

## Re-extract the MAPPING dict (if web mapping changed)
```bash
node -e 'const fs=require("fs");const s=fs.readFileSync("../../../Hydrawav3-ai/lib/zAnatomyMapping.ts","utf8").split(/\r?\n/);let a=s.findIndex(l=>l.includes("const MAPPING"));let b=-1;for(let i=a+1;i<s.length;i++){if(/^\};\s*$/.test(s[i])){b=i;break;}}let blk=s.slice(a,b+1).join("\n").replace(/const MAPPING\s*:\s*Record<[^>]*>\s*=/,"export const MAPPING =");fs.writeFileSync("mapping.js","// AUTO-GENERATED from Hydrawav3-ai/lib/zAnatomyMapping.ts\n\n"+blk+"\n");'
```

## Draco decoder
`assets/3d/draco/{draco_wasm_wrapper.js, draco_decoder.wasm}` are copied from
`node_modules/three/examples/jsm/libs/draco/`. Re-copy if the three version bumps.
