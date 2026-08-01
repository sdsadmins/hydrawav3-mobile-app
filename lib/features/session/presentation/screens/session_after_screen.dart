import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_names.dart';
import '../../../../core/theme/hw_tokens.dart';
import '../../../../core/theme/widgets/hw_primitives.dart';
import '../../../clients/domain/client_model.dart';
import '../../../clients/presentation/providers/client_providers.dart';
import '../../../protocols/domain/protocol_model.dart';
import '../../domain/pending_session_outcome_model.dart';
import '../../domain/question_answer_model.dart';
import '../providers/pending_outcomes_provider.dart';

/// Post-session screen — UI handoff `#scr-ready-after` / `renderAfter` parity
/// (`hydrawav3-ui-handoff/app.js`:3908–3959).
///
/// Shown whenever a session completes or is stopped — from the live card, or
/// pushed by [SessionOutcomeGate] when the run ended while the user was on
/// another screen.
///
/// Asks EVERY question the admin configured on the protocols that ran, with
/// every preset answer as its own chip, plus practitioner remarks — the same
/// content as `showPostSessionOutcomesSheet`, which until now was the only place
/// that showed them. This screen used to render a single hardcoded YES / NO
/// "outcome pulse" built from the FIRST question of the FIRST protocol, so a
/// protocol with two questions only ever asked one, and any answer option that
/// wasn't recognisably a yes or a no was unreachable.
///
/// The session is logged to history whichever way this screen is left — the
/// "Save & done" button is a shortcut, never a requirement. See
/// [PendingOutcomesNotifier.autoLog].
class SessionAfterScreen extends ConsumerStatefulWidget {
  final String sessionId;

  /// Optional overrides for a caller that already knows the run's shape. Both
  /// default to the queued snapshot, which is the only source available when the
  /// run ended off-screen.
  final bool? stoppedEarly;
  final int? remainingSeconds;

  const SessionAfterScreen({
    super.key,
    required this.sessionId,
    this.stoppedEarly,
    this.remainingSeconds,
  });

  @override
  ConsumerState<SessionAfterScreen> createState() => _SessionAfterScreenState();
}

class _SessionAfterScreenState extends ConsumerState<SessionAfterScreen> {
  /// Chosen preset answer, keyed `protocol::question`.
  final Map<String, String> _selected = {};

  /// Free-text answer for a question the admin left without preset options,
  /// keyed the same way.
  final Map<String, TextEditingController> _freeText = {};

  /// Practitioner remarks for the whole session.
  final TextEditingController _remarks = TextEditingController();

  bool _saving = false;

  /// True once the record has been handed to [PendingOutcomesNotifier] — stops
  /// [dispose] from logging it a second time.
  bool _logged = false;

  /// Captured in [initState]: `ref` is no longer usable once dispose runs.
  late final PendingOutcomesNotifier _outcomes;

  static String _key(String protocol, String question) => '$protocol::$question';

  @override
  void initState() {
    super.initState();
    _outcomes = ref.read(pendingOutcomesProvider.notifier);
    // Hold back the automatic save while the user is answering, so their
    // answers still ride along on the single `/intake` POST.
    _outcomes.markUnderReview(widget.sessionId);

    for (final section in _sections) {
      for (final q in section.questions) {
        if (q.answers.isEmpty) {
          _freeText[_key(section.protocolName, q.text)] =
              TextEditingController();
        }
      }
    }
  }

  @override
  void dispose() {
    // Left by ANY route — back gesture, nav tab, system back — still logs the
    // session, with whatever was answered.
    if (!_logged) {
      unawaited(_outcomes.autoLog(
        widget.sessionId,
        outcomes: _collectOutcomes(),
        force: true,
      ));
    }
    _outcomes.clearUnderReview(widget.sessionId);
    for (final c in _freeText.values) {
      c.dispose();
    }
    _remarks.dispose();
    super.dispose();
  }

  PendingSessionOutcome? get _pending => _outcomes.getById(widget.sessionId);

  /// Every protocol that ran, with its configured questions. Plus runs list one
  /// section per sub-protocol.
  List<({String protocolName, List<ProtocolQuestion> questions})>
      get _sections =>
          _pending?.sheetProtocolQuestions ??
          const <({String protocolName, List<ProtocolQuestion> questions})>[];

  /// Snapshot wins; the constructor args only override it for a caller that has
  /// fresher engine state.
  bool get _stoppedEarly =>
      widget.stoppedEarly ?? (_pending?.stoppedEarly ?? false);

  int get _remainingSeconds {
    final override = widget.remainingSeconds;
    if (override != null) return override;
    final pending = _pending;
    if (pending == null) return 0;
    return (pending.totalDurationSeconds - pending.elapsedSeconds)
        .clamp(0, 86400);
  }

  String _playerLabel(PendingSessionOutcome? pending) {
    if (pending?.clientId == null) return 'Guest';
    final clients = ref.read(clientListProvider).valueOrNull ?? const <Client>[];
    for (final c in clients) {
      if (c.id == pending!.clientId) return c.displayName;
    }
    return 'Client';
  }

  String _sessionSubtitle(PendingSessionOutcome? pending) {
    final who = _playerLabel(pending);
    final proto = pending?.protocolName ?? 'Session';
    return '$who · $proto';
  }

  String _fmtRemaining(int sec) {
    final s = sec.clamp(0, 86400);
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  /// Collect what has been answered so far — mirrors `_collect` in
  /// `post_session_outcomes_sheet.dart`, including the preset's rank (web
  /// parity: `matched?.rank || 0`; free text has no preset, so 0).
  PostSessionOutcomes _collectOutcomes() {
    final byProtocol = <String, List<QuestionAnswer>>{};
    // A partial session records no outcome (see the stopped-early copy below),
    // but remarks are still worth keeping.
    if (!_stoppedEarly) {
      for (final section in _sections) {
        final answers = <QuestionAnswer>[];
        for (final q in section.questions) {
          final k = _key(section.protocolName, q.text);
          final answer = q.answers.isNotEmpty
              ? (_selected[k] ?? '')
              : (_freeText[k]?.text.trim() ?? '');
          if (answer.isEmpty) continue;
          answers.add(QuestionAnswer(
            question: q.text,
            answer: answer,
            rank: q.rankForAnswer(answer) ?? 0,
          ));
        }
        if (answers.isNotEmpty) byProtocol[section.protocolName] = answers;
      }
    }
    final notes = _remarks.text.trim();
    return PostSessionOutcomes(
      answersByProtocol: byProtocol,
      discomfortAfterByArea: const {},
      notes: notes.isEmpty ? null : notes,
    );
  }

  /// How many questions are still unanswered — drives the button's copy so
  /// "Save & done" never quietly discards a half-filled form.
  int get _unanswered {
    if (_stoppedEarly) return 0;
    var n = 0;
    for (final section in _sections) {
      for (final q in section.questions) {
        final k = _key(section.protocolName, q.text);
        final answered = q.answers.isNotEmpty
            ? (_selected[k]?.isNotEmpty ?? false)
            : ((_freeText[k]?.text.trim().isNotEmpty) ?? false);
        if (!answered) n++;
      }
    }
    return n;
  }

  Future<void> _finish() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final pending = _pending;
      if (pending != null) {
        _logged = true;
        _outcomes.clearUnderReview(widget.sessionId);
        await _outcomes.finalize(widget.sessionId, _collectOutcomes());
      }
      if (!mounted) return;
      context.go(RoutePaths.home);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    final pending = _pending;
    final stoppedEarly = _stoppedEarly;
    final sections = _sections;
    final showQuestions = !stoppedEarly && sections.isNotEmpty;
    final subtitle = _sessionSubtitle(pending);

    final title = stoppedEarly
        ? 'Session stopped'
        : (showQuestions ? 'Session complete ✓' : 'Session complete');

    final totalQuestions = sections.fold<int>(
      0,
      (sum, s) => sum + s.questions.length,
    );

    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            HwSpace.s4,
            0,
            HwSpace.s4,
            HwSpace.s4 + MediaQuery.of(context).viewInsets.bottom,
          ),
          children: [
            HwBackBar(title: title, subtitle: subtitle),
            if (stoppedEarly)
              HwCard(
                child: Column(
                  children: [
                    Text('⏹', style: TextStyle(fontSize: 40, color: p.ink)),
                    const SizedBox(height: HwSpace.s2),
                    Text(
                      'Stopped with ${_fmtRemaining(_remainingSeconds)} remaining — '
                      'logged as stopped early. No outcome or score is recorded for partial sessions.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: HwType.sm,
                        height: 1.45,
                        color: p.ink2,
                      ),
                    ),
                  ],
                ),
              )
            else if (!showQuestions)
              HwCard(
                child: Column(
                  children: [
                    Text('✓', style: TextStyle(fontSize: 44, color: p.good)),
                    const SizedBox(height: HwSpace.s2),
                    Text(
                      'Nice work.',
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                        color: p.ink,
                      ),
                    ),
                    const SizedBox(height: HwSpace.s1),
                    Text(
                      pending?.clientId == null
                          ? 'Guest session logged — tag a player next time to build their history.'
                          : 'Session logged — capture readiness next time to see the before → after story.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: HwType.sm, color: p.ink2),
                    ),
                  ],
                ),
              ),
            if (showQuestions) ...[
              const SizedBox(height: HwSpace.s3),
              Row(
                children: [
                  const Expanded(child: HwEyebrow('Session questions')),
                  Text(
                    '$totalQuestions question${totalQuestions == 1 ? '' : 's'}',
                    style: TextStyle(fontSize: HwType.cap, color: p.ink3),
                  ),
                ],
              ),
              const SizedBox(height: HwSpace.s2),
              for (final section in sections) ...[
                _protocolSection(p, section),
                const SizedBox(height: HwSpace.s2),
              ],
            ],
            const SizedBox(height: HwSpace.s2),
            const HwEyebrow('Remarks'),
            const SizedBox(height: HwSpace.s2),
            HwCard(
              child: _field(
                p,
                _remarks,
                hint: 'Practitioner notes (optional)…',
                maxLines: 3,
              ),
            ),
            const SizedBox(height: HwSpace.s3),
            HwButton(
              label: stoppedEarly
                  ? 'Log & done'
                  : (_unanswered > 0 && _unanswered < totalQuestions
                      ? 'Save & done ($_unanswered left)'
                      : 'Save & done'),
              busy: _saving,
              onTap: _finish,
            ),
          ],
        ),
      ),
    );
  }

  /// One protocol's block: its name, then every question numbered, each with all
  /// of its configured answers as chips (or a text field when the admin defined
  /// no presets).
  Widget _protocolSection(
    RefPalette p,
    ({String protocolName, List<ProtocolQuestion> questions}) section,
  ) {
    return HwCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: p.copper,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  section.protocolName,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: p.ink,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: HwSpace.s2),
          for (var i = 0; i < section.questions.length; i++) ...[
            if (i > 0) const SizedBox(height: HwSpace.s3),
            Text(
              '${i + 1}. ${section.questions[i].text}',
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                height: 1.35,
                color: p.ink2,
              ),
            ),
            const SizedBox(height: HwSpace.s2),
            if (section.questions[i].answers.isNotEmpty)
              _answerChips(p, section.protocolName, section.questions[i])
            else
              _field(
                p,
                _freeText[
                    _key(section.protocolName, section.questions[i].text)]!,
                hint: 'Enter the client’s response…',
              ),
          ],
        ],
      ),
    );
  }

  /// Every configured answer, in the admin's own order — no yes/no guessing.
  Widget _answerChips(RefPalette p, String protocolName, ProtocolQuestion q) {
    final k = _key(protocolName, q.text);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final option in q.answers)
          () {
            final sel = _selected[k] == option.answer;
            return Material(
              color: sel ? p.copper.withValues(alpha: 0.16) : p.chipBg,
              borderRadius: BorderRadius.circular(999),
              child: InkWell(
                borderRadius: BorderRadius.circular(999),
                // Tapping the chosen chip again clears it, so a mis-tap doesn't
                // lock an answer in.
                onTap: () => setState(() {
                  if (sel) {
                    _selected.remove(k);
                  } else {
                    _selected[k] = option.answer;
                  }
                }),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: sel ? p.copper : p.cardline),
                  ),
                  child: Text(
                    option.answer,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: sel ? p.copperInk : p.ink2,
                    ),
                  ),
                ),
              ),
            );
          }(),
      ],
    );
  }

  Widget _field(
    RefPalette p,
    TextEditingController controller, {
    required String hint,
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      style: TextStyle(color: p.ink, fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: p.ink3),
        filled: true,
        fillColor: p.chipBg,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: p.cardline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: p.cardline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: p.copper),
        ),
      ),
    );
  }
}
