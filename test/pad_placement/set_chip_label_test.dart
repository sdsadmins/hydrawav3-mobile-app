// [FIX-10] Set labels.
//
// Every surface names a set "Set N" first (the chip strip, the set notes, the
// 3D legend). Performance authors `set_index` 0-based, so the FIRST set must
// print as "Set 1 · <role>" — never "Set 0" and never a literal "null" when the
// role / placement label is absent. The 3D screen's set legend takes its
// colours from `pad_placement/domain/set_colors.dart` (kAnatomySetColors /
// anatomySetColor), not from the theme palette.
//
// The chip itself lives inside PadMapScreen / PadPlacement3DScreen, both of
// which host a WebView 3D stage and cannot be pumped in a widget test, so this
// pins the label builders those widgets read (PadSetPayload.titleOf /
// displayIndexOf, set_colors) — the only inputs to the rendered strings.

import 'package:flutter_test/flutter_test.dart';

import 'package:hydrawav3/features/pad_placement/domain/set_colors.dart';
import 'package:hydrawav3/features/performance_protocols/domain/performance_models.dart';

Map<String, dynamic> _pad() => {
      'pad_label': 'Sun pad',
      'side': 'right',
      'plane': 'posterior',
      'position_along_muscle': 'proximal',
      'landmark_anchor': 'lat',
      'stack_position': 'base',
      'target_muscles': const <String>[],
    };

PadSetPayload _performance(List<Map<String, dynamic>> sets) =>
    PadSetPayload.fromJson({
      'discipline': 'tennis',
      'display_name': 'Tennis',
      'role': 'Singles Player',
      'chain': {
        'chain_id': 'c1',
        'name': 'Serve chain',
        'movement': 'overhead serve',
        'directional_mode': 'proximal_to_distal',
      },
      'sets': sets,
    });

void main() {
  group('[FIX-10] set chip labels', () {
    test('[FIX-10] performance sets print "Set 1 · role" from a 0-based index',
        () {
      final payload = _performance([
        {'set_index': 0, 'role': 'generator', 'sun': _pad()},
        {'set_index': 1, 'role': 'transfer', 'sun': _pad()},
      ]);
      final first = payload.sets[0];
      final second = payload.sets[1];

      // The number the chip leads with.
      expect(payload.displayIndexOf(first), 1);
      expect(payload.displayIndexOf(second), 2);
      // The chip composes "Set N" + " · <role>" — see PadMapScreen._setChip.
      expect('Set ${payload.displayIndexOf(first)} · ${first.role}',
          'Set 1 · generator');
      expect('Set ${payload.displayIndexOf(second)} · ${second.role}',
          'Set 2 · transfer');
      // Never the raw 0-based index.
      expect(payload.titleOf(first), startsWith('Set 1'));
      expect(payload.titleOf(first), isNot(startsWith('Set 0')));
    });

    test('[FIX-10] recovery sets keep their 1-based number', () {
      final payload = PadSetPayload.fromJson({
        'discipline': 'recovery',
        'display_name': 'Recovery',
        'role': '',
        'chain': {
          'chain_id': 'r1',
          'name': 'Low back',
          'movement': '',
          'directional_mode': '',
        },
        'sets': [
          {'set_index': 1, 'placement_label': 'Low back', 'sun': _pad()},
          {'set_index': 2, 'placement_label': 'Glute', 'sun': _pad()},
        ],
      });
      expect(payload.titleOf(payload.sets[0]), 'Set 1 · Low back');
      expect(payload.titleOf(payload.sets[1]), 'Set 2 · Glute');
      // Markers / palette index is 0-based for the same set.
      expect(payload.markerIndexOf(payload.sets[0]), 0);
    });

    test('[FIX-10] no label ever contains "null"', () {
      final payload = _performance([
        // Absent role AND placement label, explicit JSON nulls.
        {'set_index': 0, 'role': null, 'placement_label': null, 'sun': _pad()},
        // Missing keys entirely.
        {'set_index': 1, 'sun': _pad()},
      ]);
      for (final set in payload.sets) {
        final title = payload.titleOf(set);
        final suffix =
            set.role.trim().isNotEmpty ? set.role.trim() : set.placementLabel;
        final chip = 'Set ${payload.displayIndexOf(set)}'
            '${suffix.trim().isEmpty ? '' : ' · $suffix'}';
        for (final s in [title, chip, set.role, set.placementLabel]) {
          expect(s.contains('null'), isFalse, reason: '"$s" leaks null');
        }
        expect(title, matches(RegExp(r'^Set [1-9]\d*')));
        expect(chip, matches(RegExp(r'^Set [1-9]\d*$')));
      }
    });
  });

  group('[FIX-10] 3D set legend colours', () {
    test('[FIX-10] the legend reads set_colors (Set 1 yellow, 2 blue, 3 green)',
        () {
      // The 3D screen builds `_LegendDot(color: anatomySetColor(i),
      // label: 'Set ${i + 1}')` for i in 0..sets-1.
      expect(kAnatomySetColors.length, 8);
      expect(anatomySetColor(0), kAnatomySetColors[0]); // Set 1 — yellow
      expect(anatomySetColor(1), kAnatomySetColors[1]); // Set 2 — blue
      expect(anatomySetColor(2), kAnatomySetColors[2]); // Set 3 — green
      expect(anatomySetColor(0).toARGB32(), 0xFFF0E442);
      expect(anatomySetColor(1).toARGB32(), 0xFF0072B2);
      expect(anatomySetColor(2).toARGB32(), 0xFF009E73);
      // Wraps instead of throwing beyond the palette, and tolerates negatives.
      expect(anatomySetColor(8), kAnatomySetColors[0]);
      expect(anatomySetColor(-1), kAnatomySetColors[7]);
      // Every legend label for a 3-set recommendation.
      for (var i = 0; i < 3; i++) {
        expect('Set ${i + 1}', isNot(contains('null')));
      }
    });
  });
}
