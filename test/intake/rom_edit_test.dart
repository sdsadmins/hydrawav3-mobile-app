// [FIX-25] Editing an area of focus in the Guided Assessment.
//
// GuidedAssessmentScreen step 1 lists each selected area as a `.padnote` row:
//   "<body part>" / "discomfort N/10 · ROM <level>[ · <note>]"
// with a pencil (Icons.edit_outlined) that opens `areaEditSheet`. Re-opening
// the pencil must pre-fill the SAVED discomfort ("N/10"), the saved
// comfortable-range percentage ("P%") and the saved note; "Done" writes the
// edits back and the summary row updates.
// (lib/features/intake/presentation/screens/guided_assessment_screen.dart)
//
// Two app bugs surface while driving this screen and are pinned here rather
// than hidden:
//  - guided_assessment_screen.dart:320 hosts BodyMap in a 380px SizedBox but
//    BodyMap (body_map.dart:74) lays out 40 + 12 + 360 = 412px → a 32px
//    RenderFlex overflow on every build of step 1. Each test consumes exactly
//    that one error so the FIX-25 behaviour can still be asserted.
//  - guided_assessment_screen.dart:290 disposes the note controller the moment
//    the sheet future returns, while the sheet is still animating out; when
//    the note field had focus it rebuilds once more and throws "used after
//    being disposed". The realistic type-then-Done flow is kept as a
//    `qa-known-bug` test; the passing twin defocuses before Done.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hydrawav3/features/intake/domain/intake_enums.dart';
import 'package:hydrawav3/features/intake/domain/intake_models.dart';
import 'package:hydrawav3/features/intake/domain/rom_instructions.dart';
import 'package:hydrawav3/features/intake/presentation/providers/guided_assessment_provider.dart';
import 'package:hydrawav3/features/intake/presentation/providers/wizard_draft_provider.dart';
import 'package:hydrawav3/features/intake/presentation/screens/guided_assessment_screen.dart';

import '../helpers/pump_app.dart';
import '../helpers/qa_snap.dart';

const _area = 'Lower back';
const _savedRow = 'discomfort 7/10 · ROM Limited · worse in the morning';
const _editedRow = 'discomfort 9/10 · ROM Normal · eases after walking';

/// A wizard already holding one assessed area.
class _SeededAssessment extends GuidedAssessmentNotifier {
  _SeededAssessment() {
    addArea(DiscomfortAreaInput(
      bodyPart: _area,
      side: DiscomfortSide.both,
      discomfortBefore: 7,
      romLevel: romLevelFromPercent(40), // Limited
      notes: 'worse in the morning',
    ));
  }
}

class _SeededDraft extends WizardDraftNotifier {
  _SeededDraft() {
    setRomPercent(_area, 40);
  }
}

void main() {
  /// Pumps step 1 and consumes the one known BodyMap overflow (see header).
  Future<void> pumpWizard(WidgetTester tester) async {
    await pumpApp(
      tester,
      const GuidedAssessmentScreen(),
      overrides: [
        guidedAssessmentProvider.overrideWith((ref) => _SeededAssessment()),
        wizardDraftProvider.overrideWith((ref) => _SeededDraft()),
      ],
    );
    await tester.pumpAndSettle();
    final overflow = tester.takeException();
    expect(overflow, isA<FlutterError>());
    expect('$overflow', contains('A RenderFlex overflowed by 32 pixels'));
  }

  Slider sliderNear(WidgetTester tester, String label) {
    final column = find.ancestor(
      of: find.text(label),
      matching: find.byType(Column),
    );
    return tester.widget<Slider>(
      find.descendant(of: column.first, matching: find.byType(Slider)).first,
    );
  }

  Future<void> openPencil(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
  }

  /// Drives the sheet to 9/10, 90%, a new note.
  Future<void> editToNine(WidgetTester tester) async {
    sliderNear(tester, 'Discomfort level').onChanged!(9);
    await tester.pump();
    sliderNear(tester, 'Comfortable range of motion').onChanged!(90);
    await tester.pump();
    expect(find.text('9/10'), findsOneWidget);
    expect(find.text('90%'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField, 'worse in the morning'),
      'eases after walking',
    );
    await tester.pump();
  }

  qaTestWidgets('[FIX-25] re-opening the pencil pre-fills the saved values',
      (tester) async {
    await pumpWizard(tester);

    // The row shows the saved summary in the real format.
    expect(romLevelFromPercent(40), RomLevel.limited);
    expect(find.text(_savedRow), findsOneWidget);

    await openPencil(tester);

    // Sheet pre-filled from the saved area, not the spec defaults (4 / 60%).
    expect(find.text('7/10'), findsOneWidget);
    expect(find.text('40%'), findsOneWidget);
    expect(find.text('4/10'), findsNothing);
    expect(find.text('60%'), findsNothing);
    expect(
      find.widgetWithText(TextField, 'worse in the morning'),
      findsOneWidget,
    );
    expect(sliderNear(tester, 'Discomfort level').value, 7);
    expect(sliderNear(tester, 'Comfortable range of motion').value, 40);

    // Close without changes: nothing moves.
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text(_savedRow), findsOneWidget);
  });

  qaTestWidgets(
      '[FIX-25] editing updates the "discomfort N/10 · ROM …" row (defocused)',
      (tester) async {
    await pumpWizard(tester);
    await openPencil(tester);
    await editToNine(tester);

    // Leave the note field before Done — see the header's second bug.
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(romLevelFromPercent(90), RomLevel.normal);
    expect(find.text(_editedRow), findsOneWidget);
    expect(find.text(_savedRow), findsNothing);

    // And the pencil re-opens with the NEW values.
    await openPencil(tester);
    expect(find.text('9/10'), findsOneWidget);
    expect(find.text('90%'), findsOneWidget);
    expect(
      find.widgetWithText(TextField, 'eases after walking'),
      findsOneWidget,
    );
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
  });

  // KNOWN BUG — the realistic flow: type the note, then tap Done straight
  // away. guided_assessment_screen.dart:290 disposes `noteCtrl` as soon as
  // the sheet future resolves, while the sheet is still animating out with
  // the focused field, which rebuilds and throws
  // "A TextEditingController was used after being disposed."
  qaTestWidgets(
      '[FIX-25] editing updates the row when Done follows typing the note',
      tags: ['qa-known-bug'], (tester) async {
    await pumpWizard(tester);
    await openPencil(tester);
    await editToNine(tester);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(find.text(_editedRow), findsOneWidget);
    expect(find.text(_savedRow), findsNothing);
  });
}
