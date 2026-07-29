/// Per-screen rollback switches for the AnatomyScene viewer.
///
/// Both viewers ship in the APK, so flipping either of these back to `false` is
/// a one-line revert with no asset change and no rebuild of any bundle. They are
/// `const`, so the dead branch is tree-shaken and costs nothing at runtime.
///
/// The granularity is per-screen on purpose: Recovery is positioned entirely by
/// curated zone landmarks, Performance almost entirely by pre-derived mesh
/// anchors. They exercise different resolution tiers and can fail independently,
/// so one going wrong should not force the other back.
///
/// Once both have been through a release and the old viewer is retired, delete
/// these, `pad_anatomy_view.dart`, `pad_placement.src.js`, `pad_placement.html`,
/// `pad_placement.bundle.js` and the `build:pads` script — that recovers about
/// 630 KB of APK.
library;

/// Performance pad map (`pad_map_screen.dart`).
const bool kUseAnatomyScenePerformance = true;

/// Recovery 3D placement (`pad_placement_3d_screen.dart`).
const bool kUseAnatomySceneRecovery = true;
