import 'package:flutter_test/flutter_test.dart';

import 'package:hydrawav3/features/assistant/presentation/screens/assistant_history_screen.dart';

/// Chat history reopens a saved placement in 3D. A recovery card is saved as
/// the recovery engine's resolve response (sets carry `pads[]`), a
/// performance card in the pad-set shape (`sun` / `moon`).
void main() {
  Map<String, dynamic> pad(String label, String side, String muscle) => {
        'pad_label': label,
        'side': side,
        'aspect': 'posterior',
        'position': 'proximal',
        'landmark_anchor': '$muscle, $side',
        'target_muscles': [muscle],
      };

  test('a saved recovery placement keeps its Sun / Moon muscles', () {
    final saved = {
      'pathway': 'discomfort',
      'generation': 'v3',
      'point': {'region': 'neck'},
      'sets': [
        {
          'set_index': 1,
          'set_role': 'primary',
          'pads': [
            pad('sun', 'right', 'Levator scapulae'),
            pad('moon', 'right', 'Multifidus colli muscle'),
          ],
        },
      ],
    };
    final p = savedPlacementPayload(saved, 'Neck');
    expect(p.discipline, 'recovery');
    expect(p.displayName, 'Neck');
    expect(p.isRefusal, isFalse);
    final set = p.appliedSets.single;
    expect(set.sun?.targetMuscles, ['Levator scapulae']);
    expect(set.moon?.targetMuscles, ['Multifidus colli muscle']);
  });

  test('a saved performance placement reads as before', () {
    final saved = {
      'discipline': 'baseball',
      'display_name': 'Baseball',
      'role': 'Pitcher',
      'chain': {'chain_id': 'c1', 'name': 'Hip drive'},
      'sets': [
        {
          'set_index': 0,
          'sun': {'side': 'right', 'target_muscles': ['Gluteus medius muscle']},
          'moon': {'side': 'right', 'target_muscles': ['Piriformis muscle']},
        },
      ],
    };
    final p = savedPlacementPayload(saved, 'Baseball');
    expect(p.discipline, 'baseball');
    expect(p.appliedSets.single.sun?.targetMuscles, ['Gluteus medius muscle']);
  });
}
