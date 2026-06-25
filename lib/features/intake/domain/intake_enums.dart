// Enums mirroring the backend `CreateIntakeDto`
// (`Hydrawav3-Server/src/modules/intake/dto/create-intake.dto.ts`). The
// `.value` strings MUST match the server enums exactly — the server rejects
// unknown values (`whitelist + forbidNonWhitelisted`). These are the single
// source of truth for both the wizard pickers and the `/intake` payload.

enum DiscomfortSide {
  left('Left'),
  right('Right'),
  both('Both');

  final String value;
  const DiscomfortSide(this.value);

  String get label => value;

  /// Side for the AI `PatientIntakeInput`: Left->left, Right->right, Both->center.
  String get aiValue => switch (this) {
        DiscomfortSide.left => 'left',
        DiscomfortSide.right => 'right',
        DiscomfortSide.both => 'center',
      };
}

enum TemporalDuration {
  lessThan6Weeks('Less than 6 weeks'),
  sixWeeksTo3Months('6 weeks to 3 months'),
  threeTo6Months('3 to 6 months'),
  sixMonthsTo1Year('6 months to 1 year'),
  moreThan1Year('More than 1 year');

  final String value;
  const TemporalDuration(this.value);

  String get label => value;

  /// Months (string) for the AI input, per the web lookup table.
  String get aiMonths => switch (this) {
        TemporalDuration.lessThan6Weeks => '1',
        TemporalDuration.sixWeeksTo3Months => '2',
        TemporalDuration.threeTo6Months => '4',
        TemporalDuration.sixMonthsTo1Year => '9',
        TemporalDuration.moreThan1Year => '18',
      };
}

enum DiscomfortBehavior {
  alwaysPresent('Always Present'),
  comesAndGoes('Comes and Goes'),
  onlyWithCertainActivities('Only with certain Activities'),
  variesDayToDay('Varies day to day');

  final String value;
  const DiscomfortBehavior(this.value);

  String get label => value;
}

/// Range-of-motion level for a discomfort area. Display labels are local; the
/// AI input maps them to normal | limited | stiff (web parity).
enum RomLevel {
  normal('Normal'),
  moderate('Moderate'),
  limited('Limited'),
  severelyLimited('Severely Limited');

  final String value;
  const RomLevel(this.value);

  String get label => value;

  String get aiValue => switch (this) {
        RomLevel.normal => 'normal',
        RomLevel.moderate => 'limited',
        RomLevel.limited => 'limited',
        RomLevel.severelyLimited => 'stiff',
      };
}

enum SleepPosture {
  onBack('On back'),
  onStomach('On stomach'),
  leftSide('Left side'),
  rightSide('Right side'),
  changePositions('Change positions');

  final String value;
  const SleepPosture(this.value);

  String get label => value;
}

enum HardPositionTolerance {
  standing('Standing'),
  sitting('Sitting'),
  both('Both'),
  neither('Neither');

  final String value;
  const HardPositionTolerance(this.value);

  String get label => value;
}

enum HipTightness {
  no('No', 'No'),
  yesRight('Yes-right', 'Yes — Right'),
  yesLeft('Yes-left', 'Yes — Left'),
  yesBoth('Yes-both', 'Yes — Both');

  final String value;
  final String label;
  const HipTightness(this.value, this.label);
}

/// Parse a backend enum value string back into a Dart enum (for deserialising
/// persisted intake JSON). Returns null if no match.
T? enumFromValue<T>(List<T> values, String? raw, String Function(T) toValue) {
  if (raw == null) return null;
  for (final v in values) {
    if (toValue(v) == raw) return v;
  }
  return null;
}
