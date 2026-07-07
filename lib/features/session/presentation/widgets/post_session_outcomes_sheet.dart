import 'package:flutter/material.dart';

import '../../../../core/constants/theme_constants.dart';
import '../../../protocols/domain/protocol_model.dart';
import '../../domain/question_answer_model.dart';

/// A protocol and its post-session questions (each with preset answers).
typedef ProtocolQuestions = ({String protocolName, List<ProtocolQuestion> questions});

/// One area of focus for the discomfort mapping: body part + pre-session pain.
typedef DiscomfortAreaSeed = ({String bodyPart, int before});

/// Post-session "Session Outcomes" sheet (web parity). Captures, for a
/// completed CLIENT session: per-area discomfort (body part + post pain), the
/// protocol's session questions (preset-answer chips), and practitioner notes.
///
/// Built purely from the passed snapshot — no live engine — so it works even
/// after the live card is gone. Returns the collected [PostSessionOutcomes] on
/// Submit, or `null` on Skip / dismiss.
Future<PostSessionOutcomes?> showPostSessionOutcomesSheet(
  BuildContext context, {
  required List<ProtocolQuestions> protocolQuestions,
  required List<DiscomfortAreaSeed> discomfortAreas,
  bool dismissible = true,
}) {
  // Selected preset answer per "protocol::question".
  final selected = <String, String>{};
  // Free-text answer per "protocol::question" (only for questions with no presets).
  final textControllers = <String, TextEditingController>{};
  for (final pq in protocolQuestions) {
    for (final q in pq.questions) {
      if (q.answers.isEmpty) {
        textControllers['${pq.protocolName}::${q.text}'] =
            TextEditingController();
      }
    }
  }
  // Post-session pain per area index, seeded to the pre-session value.
  final painByArea = <int, double>{
    for (var i = 0; i < discomfortAreas.length; i++)
      i: discomfortAreas[i].before.toDouble(),
  };
  final painTouched = <int>{};
  final notesController = TextEditingController();

  String key(String p, String q) => '$p::$q';

  return showModalBottomSheet<PostSessionOutcomes>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    isDismissible: dismissible,
    enableDrag: dismissible,
    backgroundColor: ThemeConstants.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheet) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 4,
              bottom: 16 + MediaQuery.of(ctx).viewInsets.bottom,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.85,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Session Outcomes',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: ThemeConstants.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Capture recovery data before the session closes.',
                    style: TextStyle(
                      fontSize: 12,
                      color: ThemeConstants.textTertiary,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // --- Discomfort Mapping (per body area) ---
                          if (discomfortAreas.isNotEmpty) ...[
                            _sectionLabel('Discomfort Mapping (Post-Session)'),
                            for (var i = 0; i < discomfortAreas.length; i++) ...[
                              _areaRow(
                                bodyPart: discomfortAreas[i].bodyPart,
                                before: discomfortAreas[i].before,
                                value: painByArea[i]!,
                                touched: painTouched.contains(i),
                                onChanged: (v) => setSheet(() {
                                  painByArea[i] = v;
                                  painTouched.add(i);
                                }),
                              ),
                              const SizedBox(height: 12),
                            ],
                            const SizedBox(height: 4),
                          ],

                          // --- Session Questions (per protocol) ---
                          if (protocolQuestions.isNotEmpty) ...[
                            _sectionLabel('Session Questions'),
                            for (final pq in protocolQuestions) ...[
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: BoxDecoration(
                                        color: ThemeConstants.accent,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        pq.protocolName,
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w800,
                                          color: ThemeConstants.textPrimary,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              for (var qi = 0; qi < pq.questions.length; qi++) ...[
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 6),
                                  child: Text(
                                    '${qi + 1}. ${pq.questions[qi].text}',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: ThemeConstants.textSecondary,
                                    ),
                                  ),
                                ),
                                if (pq.questions[qi].answers.isNotEmpty)
                                  _answerChips(
                                    answers: pq.questions[qi].answers
                                        .map((o) => o.answer)
                                        .toList(),
                                    selected: selected[
                                        key(pq.protocolName, pq.questions[qi].text)],
                                    onSelect: (a) => setSheet(() => selected[key(
                                        pq.protocolName,
                                        pq.questions[qi].text)] = a),
                                  )
                                else
                                  _field(
                                    textControllers[key(pq.protocolName,
                                        pq.questions[qi].text)]!,
                                    hint: 'Enter the client\'s response…',
                                  ),
                                const SizedBox(height: 14),
                              ],
                            ],
                          ],

                          // --- Practitioner notes ---
                          _sectionLabel('Notes'),
                          _field(
                            notesController,
                            hint: 'Practitioner notes (optional)…',
                            maxLines: 3,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(ctx).pop(null),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            side: BorderSide(color: ThemeConstants.border),
                          ),
                          child: Text(
                            'Skip',
                            style: TextStyle(color: ThemeConstants.textSecondary),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton(
                          onPressed: () => Navigator.of(ctx).pop(
                            _collect(
                              protocolQuestions,
                              selected,
                              textControllers,
                              painByArea,
                              painTouched,
                              notesController.text,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: ThemeConstants.accent,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: const Text('Submit'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}

PostSessionOutcomes _collect(
  List<ProtocolQuestions> protocolQuestions,
  Map<String, String> selected,
  Map<String, TextEditingController> textControllers,
  Map<int, double> painByArea,
  Set<int> painTouched,
  String notes,
) {
  final byProtocol = <String, List<QuestionAnswer>>{};
  for (final pq in protocolQuestions) {
    final answers = <QuestionAnswer>[];
    for (final q in pq.questions) {
      final k = '${pq.protocolName}::${q.text}';
      final answer = q.answers.isNotEmpty
          ? (selected[k] ?? '')
          : (textControllers[k]?.text.trim() ?? '');
      if (answer.isEmpty) continue;
      // Carry the selected preset's rank (web parity: `matched?.rank || 0`);
      // free-text answers have no matching preset → 0.
      answers.add(QuestionAnswer(
        question: q.text,
        answer: answer,
        rank: q.rankForAnswer(answer) ?? 0,
      ));
    }
    if (answers.isNotEmpty) byProtocol[pq.protocolName] = answers;
  }
  final byArea = <int, int>{
    for (final i in painTouched) i: painByArea[i]!.round(),
  };
  final trimmedNotes = notes.trim();
  return PostSessionOutcomes(
    answersByProtocol: byProtocol,
    discomfortAfterByArea: byArea,
    notes: trimmedNotes.isEmpty ? null : trimmedNotes,
  );
}

Widget _areaRow({
  required String bodyPart,
  required int before,
  required double value,
  required bool touched,
  required ValueChanged<double> onChanged,
}) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: ThemeConstants.surfaceVariant.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: ThemeConstants.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                bodyPart.isEmpty ? 'Area' : bodyPart,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: ThemeConstants.textPrimary,
                ),
              ),
            ),
            _pill('Pre $before', ThemeConstants.textTertiary),
            const SizedBox(width: 6),
            Icon(Icons.arrow_forward_rounded,
                size: 14, color: ThemeConstants.textTertiary),
            const SizedBox(width: 6),
            _pill('Post ${touched ? value.round() : before}',
                ThemeConstants.accent),
          ],
        ),
        Slider(
          value: value,
          min: 0,
          max: 10,
          divisions: 10,
          activeColor: ThemeConstants.accent,
          label: value.round().toString(),
          onChanged: onChanged,
        ),
      ],
    ),
  );
}

Widget _answerChips({
  required List<String> answers,
  required String? selected,
  required ValueChanged<String> onSelect,
}) {
  return Wrap(
    spacing: 8,
    runSpacing: 8,
    children: answers.map((a) {
      final sel = a == selected;
      return InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () => onSelect(a),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration(
            color: sel
                ? ThemeConstants.accent.withValues(alpha: 0.16)
                : ThemeConstants.surfaceVariant.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: sel ? ThemeConstants.accent : ThemeConstants.border,
            ),
          ),
          child: Text(
            a,
            style: TextStyle(
              color: sel ? ThemeConstants.accent : ThemeConstants.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }).toList(),
  );
}

Widget _sectionLabel(String text) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
          color: ThemeConstants.accent,
        ),
      ),
    );

Widget _field(
  TextEditingController controller, {
  required String hint,
  int maxLines = 1,
}) {
  return TextField(
    controller: controller,
    maxLines: maxLines,
    style: TextStyle(color: ThemeConstants.textPrimary, fontSize: 14),
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: ThemeConstants.textTertiary),
      filled: true,
      fillColor: ThemeConstants.surfaceVariant.withValues(alpha: 0.7),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: ThemeConstants.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: ThemeConstants.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: ThemeConstants.accent),
      ),
    ),
  );
}

Widget _pill(String text, Color color) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
