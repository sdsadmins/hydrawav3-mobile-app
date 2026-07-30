/// Range-of-motion prompts and the mapping from the wizard's 0–100% slider onto
/// the backend's `RomLevel` / `RomFinding` vocabulary.
///
/// The UI handoff spec carries a `WIZ_ROM` table (app.js:2848) keyed by ITS own
/// area ids (`shoulders`, `lowback`, …), which don't exist in this app — our
/// areas come from `BodyMap`'s region names ("Left Shoulder", "Lower Back", …).
/// So the instructions are re-keyed by a normalised body-part name, keeping the
/// spec's wording verbatim, including its fallback line.
library;

import 'intake_enums.dart';

/// The spec's instruction lines, keyed by a substring of the normalised area.
/// Order matters: the first match wins, so specific keys precede general ones.
const List<(String, String)> _instructions = [
  ('shoulder', 'Raise the arm slowly out and up as far as comfortable.'),
  ('neck', 'Turn the head slowly toward each shoulder.'),
  ('lower back', 'Hinge forward slowly, reaching toward the knees.'),
  ('low back', 'Hinge forward slowly, reaching toward the knees.'),
  ('mid back', 'Reach overhead and lean gently to each side.'),
  ('upper back', 'Reach overhead and lean gently to each side.'),
  ('hip', 'Pull one knee toward the chest while standing tall.'),
  ('hamstring', 'With soft knees, slide hands down the legs.'),
  ('knee', 'Sink into a slow half-squat, heels down.'),
  ('quad', 'Sink into a slow half-squat, heels down.'),
  ('upper leg', 'Sink into a slow half-squat, heels down.'),
  ('calf', 'Drop one heel off a step and hold.'),
  ('lower leg', 'Drop one heel off a step and hold.'),
  ('ankle', 'Drop one heel off a step and hold.'),
  ('foot', 'Rise onto the toes slowly, then lower.'),
  ('forearm', 'Extend the arm and gently flex the wrist down.'),
  ('wrist', 'Extend the arm and gently flex the wrist down.'),
  ('elbow', 'Straighten and bend the elbow through its full range.'),
  ('hand', 'Open and close the hand slowly, spreading the fingers.'),
  ('upper arm', 'Reach the arm across the body, then overhead.'),
  ('lat', 'Reach overhead and lean gently to each side.'),
  ('chest', 'Open the arms wide, drawing the shoulder blades together.'),
  ('abdomen', 'Stand tall and lean gently backwards.'),
  ('head', 'Nod slowly, then turn the head to each side.'),
];

/// The movement test name recorded on the `RomFinding`.
const List<(String, String)> _testNames = [
  ('shoulder', 'Shoulder Flexion'),
  ('neck', 'Neck Rotation'),
  ('lower back', 'Forward Bend'),
  ('low back', 'Forward Bend'),
  ('mid back', 'Trunk Rotation'),
  ('upper back', 'Trunk Rotation'),
  ('hip', 'Hip Flexion'),
  ('hamstring', 'Forward Bend'),
  ('knee', 'Squat'),
  ('quad', 'Squat'),
  ('upper leg', 'Squat'),
  ('calf', 'Ankle Dorsiflexion'),
  ('lower leg', 'Ankle Dorsiflexion'),
  ('ankle', 'Ankle Dorsiflexion'),
  ('foot', 'Ankle Dorsiflexion'),
  ('forearm', 'Wrist Flexion'),
  ('wrist', 'Wrist Flexion'),
  ('elbow', 'Elbow Extension'),
  ('hand', 'Wrist Flexion'),
  ('upper arm', 'Shoulder Flexion'),
  ('lat', 'Trunk Rotation'),
  ('chest', 'Shoulder Flexion'),
  ('abdomen', 'Trunk Rotation'),
  ('head', 'Neck Rotation'),
];

String _lookup(List<(String, String)> table, String bodyPart, String fallback) {
  final n = bodyPart.toLowerCase();
  for (final (key, value) in table) {
    if (n.contains(key)) return value;
  }
  return fallback;
}

/// The spec's own fallback line (app.js:2894).
const String kRomInstructionFallback =
    'Move slowly through the comfortable range.';

String romInstructionFor(String bodyPart) =>
    _lookup(_instructions, bodyPart, kRomInstructionFallback);

String romTestNameFor(String bodyPart) =>
    _lookup(_testNames, bodyPart, 'Comfortable Range');

/// The ROM asset that illustrates this movement, or null when none matches.
/// These already ship in `assets/images/`.
String? romImageFor(String bodyPart) {
  const byTest = {
    'Shoulder Flexion': 'assets/images/ROM_Shoulder_Flexion.png',
    'Neck Rotation': 'assets/images/ROM_Neck_Rotation.png',
    'Forward Bend': 'assets/images/ROM_Forward_Bend.png',
    'Trunk Rotation': 'assets/images/ROM_Trunk_Rotation.png',
    'Squat': 'assets/images/ROM_Squat.png',
    'Ankle Dorsiflexion': 'assets/images/ROM_Ankle_Dorsiflextion.png',
  };
  return byTest[romTestNameFor(bodyPart)];
}

/// The slider's 10–100% onto the backend's four-level `RomLevel`.
///
/// The spec's step 2 is a single percentage; the backend stores a level. These
/// bands are the bridge — a comfortable range at or above 85% reads as normal,
/// and below a third of range is severe.
RomLevel romLevelFromPercent(int pct) {
  if (pct >= 85) return RomLevel.normal;
  if (pct >= 60) return RomLevel.moderate;
  if (pct >= 35) return RomLevel.limited;
  return RomLevel.severelyLimited;
}

/// The `sensation` recorded on the synthesised `RomFinding`. Free text on the
/// backend, so this is descriptive rather than an enum.
String romSensationFromPercent(int pct) {
  if (pct >= 85) return 'Full range';
  if (pct >= 60) return 'Mild restriction';
  if (pct >= 35) return 'Restricted';
  return 'Severely restricted';
}

/// The spec's step 3 options (app.js:2853), verbatim.
const List<String> kDailyActivityOptions = [
  'Desk work',
  'Manual labor',
  'Driving',
  'Standing all day',
  'Training 2×/day',
  'Travel-heavy',
];

/// Display labels for `SleepPosture`, borrowing the spec's "… sleeper" phrasing.
///
/// ⚠️ The OPTIONS are the backend enum, not the spec's list. The spec offers
/// `Back / Side / Stomach / Mixed`; the server's `CreateIntakeDto` validates
/// with `forbidNonWhitelisted`, so sending `'Mixed'` is a 400. Only the wording
/// is borrowed.
String sleepPostureLabel(SleepPosture p) => switch (p) {
      SleepPosture.onBack => 'Back sleeper',
      SleepPosture.onStomach => 'Stomach sleeper',
      SleepPosture.leftSide => 'Left side sleeper',
      SleepPosture.rightSide => 'Right side sleeper',
      SleepPosture.changePositions => 'Mixed sleeper',
    };

/// Display labels for `HardPositionTolerance`.
///
/// ⚠️ Same constraint. The spec's step 5 offers movement-shaped options
/// (`Overhead reach`, `Deep squat`, …) that the backend enum has no room for —
/// it models which sustained POSITION is hardest to tolerate. Shipping the
/// spec's labels would 400, so the enum wins and the spec's step title is kept.
String hardPositionLabel(HardPositionTolerance p) => switch (p) {
      HardPositionTolerance.standing => 'Standing for long',
      HardPositionTolerance.sitting => 'Sitting for long',
      HardPositionTolerance.both => 'Both are hard',
      HardPositionTolerance.neither => 'Neither is hard',
    };
