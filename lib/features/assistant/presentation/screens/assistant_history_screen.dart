import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/hw_tokens.dart';
import '../../../../core/theme/widgets/hw_tablet.dart';
import '../../../history/data/history_repository.dart';
import '../../../history/domain/session_history_model.dart';
import '../../../home/presentation/providers/hub_stats_provider.dart'
    show PulseCheck, scoreOf;
import '../../../performance_protocols/domain/performance_models.dart';
import '../../../performance_protocols/presentation/screens/pad_map_screen.dart';
import '../../data/rag_chat_history_repository.dart';

/// The sessions behind History: one client's (`GET intake/client/:id`), or —
/// for Guest mode — every guest session in the organization.
final _historySessionsProvider = FutureProvider.autoDispose
    .family<List<SessionHistoryItem>, String?>((ref, clientId) async {
  if (clientId != null) {
    return ref.watch(clientHistoryProvider(clientId).future);
  }
  final all = await ref.watch(allSessionsProvider.future);
  return all
      .where((s) => (s.clientType ?? '').toLowerCase() == 'guest')
      .toList();
});

/// Assistant → clock: everything about this person in four tabs —
/// Protocols, Usage, Outcomes (from their sessions) and Chat (their saved
/// Assistant conversations, with any pad placement reopening in 3D).
class AssistantHistoryScreen extends StatelessWidget {
  /// Null = Guest mode.
  final String? clientId;
  final String name;

  const AssistantHistoryScreen({super.key, this.clientId, required this.name});

  static Future<void> open(BuildContext context,
      {String? clientId, required String name}) {
    return Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => AssistantHistoryScreen(clientId: clientId, name: name),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    final side =
        HwTablet.sidePadding(context, column: HwTablet.read, phone: 16);
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        backgroundColor: p.bg,
        body: SafeArea(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: side),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 10),
                Row(
                  children: [
                    _RoundButton(
                      icon: Icons.chevron_left_rounded,
                      label: 'Back',
                      onTap: () => Navigator.of(context).maybePop(),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('History',
                              style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -.3,
                                  color: p.ink)),
                          Text(clientId == null ? 'Guest sessions' : name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 13, color: p.ink3)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: p.card,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: p.cardline),
                  ),
                  child: TabBar(
                    dividerColor: Colors.transparent,
                    indicatorSize: TabBarIndicatorSize.tab,
                    indicator: BoxDecoration(
                      gradient: p.sunGrad,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    labelColor: const Color(0xFF2A1A12),
                    unselectedLabelColor: p.ink2,
                    labelStyle: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w800),
                    unselectedLabelStyle: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600),
                    labelPadding: EdgeInsets.zero,
                    tabs: const [
                      Tab(height: 36, text: 'Protocols'),
                      Tab(height: 36, text: 'Usage'),
                      Tab(height: 36, text: 'Outcomes'),
                      Tab(height: 36, text: 'Chat'),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: TabBarView(
                    children: [
                      _SessionsTab(
                          clientId: clientId,
                          build: _protocols,
                          skeleton: const _ProtocolsSkeleton()),
                      _SessionsTab(clientId: clientId, build: _usage),
                      _SessionsTab(clientId: clientId, build: _outcomes),
                      _ChatTab(clientId: clientId, name: name),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── shared bits ─────────────────────────────────────────────────────────────

String _date(DateTime? d) {
  if (d == null) return '';
  final l = d.toLocal();
  const m = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec'
  ];
  return '${m[l.month - 1]} ${l.day}, ${l.year}';
}

String _dateTime(DateTime? d) {
  if (d == null) return '';
  final l = d.toLocal();
  final hh = l.hour % 12 == 0 ? 12 : l.hour % 12;
  final mm = l.minute.toString().padLeft(2, '0');
  return '${_date(d)} · $hh:$mm ${l.hour < 12 ? 'AM' : 'PM'}';
}

String _minutes(int seconds) {
  final m = (seconds / 60).round();
  if (m < 60) return '$m min';
  final h = m ~/ 60, r = m % 60;
  return r == 0 ? '$h h' : '$h h $r min';
}

class _RoundButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _RoundButton(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: p.card,
            border: Border.all(color: p.cardline),
          ),
          child: Icon(icon, color: p.ink2, size: 26),
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: p.cardline),
      ),
      child: child,
    );
  }
}

class _Eyebrow extends StatelessWidget {
  final String text;
  const _Eyebrow(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 6, 2, 8),
        child: Text(text.toUpperCase(),
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1,
                color: RefPalette.of(context).ink3)),
      );
}

Widget _empty(BuildContext context, String text) {
  final p = RefPalette.of(context);
  return ListView(
    children: [
      const SizedBox(height: 40),
      Icon(Icons.history_rounded, size: 34, color: p.ink3),
      const SizedBox(height: 10),
      Text(text,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: p.ink3)),
    ],
  );
}

/// Loads the sessions once, then builds a tab from them.
class _SessionsTab extends ConsumerWidget {
  final String? clientId;
  final Widget Function(BuildContext, List<SessionHistoryItem>) build_;

  /// Shown while loading, in place of the spinner.
  final Widget? skeleton;
  const _SessionsTab(
      {required this.clientId,
      required Widget Function(BuildContext, List<SessionHistoryItem>) build,
      this.skeleton})
      : build_ = build;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = RefPalette.of(context);
    final async = ref.watch(_historySessionsProvider(clientId));
    return RefreshIndicator(
      color: p.copper,
      onRefresh: () async => ref.invalidate(_historySessionsProvider(clientId)),
      child: async.when(
        loading: () =>
            skeleton ??
            Center(
                child:
                    CircularProgressIndicator(strokeWidth: 2, color: p.copper)),
        error: (e, _) =>
            _empty(context, 'Couldn’t load sessions. Pull to retry.'),
        data: (list) => list.isEmpty
            ? _empty(context, 'No sessions yet.')
            : build_(context, list),
      ),
    );
  }
}

// ── Protocols ───────────────────────────────────────────────────────────────

/// One run of a protocol, for the expandable list.
class _Run {
  final DateTime? at;
  final int secs;
  final String? device;

  /// From the run's check-ins: true = helped, false = didn't, null = none.
  final bool? helped;
  const _Run(this.at, this.secs, this.device, this.helped);
}

/// Everything about one protocol across this person's sessions.
class _ProtocolStats {
  final String name;
  final List<_Run> runs = [];
  _ProtocolStats(this.name);

  int get secs => runs.fold(0, (a, r) => a + r.secs);
  int get avg => runs.isEmpty ? 0 : secs ~/ runs.length;
  DateTime? get last => runs
      .map((r) => r.at)
      .whereType<DateTime>()
      .fold<DateTime?>(null, (a, b) => a == null || b.isAfter(a) ? b : a);
  String? get lastDevice {
    final sorted = [...runs]
      ..sort((a, b) => (b.at ?? DateTime(0)).compareTo(a.at ?? DateTime(0)));
    for (final r in sorted) {
      if ((r.device ?? '').trim().isNotEmpty) return r.device!.trim();
    }
    return null;
  }

  /// Share of checked runs that helped (null when none were checked).
  int? get helpedPct {
    final checked = runs.where((r) => r.helped != null).toList();
    if (checked.isEmpty) return null;
    return (checked.where((r) => r.helped!).length / checked.length * 100)
        .round();
  }
}

Widget _protocols(BuildContext context, List<SessionHistoryItem> sessions) {
  final byName = <String, _ProtocolStats>{};
  for (final s in sessions) {
    for (final pr in s.protocols) {
      final name = (pr.protocol ?? '').trim();
      if (name.isEmpty) continue;
      final qa = pr.questionAnswers;
      final helped = qa.isEmpty
          ? null
          : qa.where((q) => q.rank >= 4).length * 2 >= qa.length;
      byName
          .putIfAbsent(name, () => _ProtocolStats(name))
          .runs
          .add(_Run(s.createdAt, pr.duration ?? 0, pr.deviceName, helped));
    }
  }
  if (byName.isEmpty) return _empty(context, 'No protocols run yet.');
  final list = byName.values.toList()
    ..sort((a, b) {
      final c = b.runs.length.compareTo(a.runs.length);
      return c != 0 ? c : b.secs.compareTo(a.secs);
    });
  final totalRuns = list.fold<int>(0, (a, s) => a + s.runs.length);
  final totalSecs = list.fold<int>(0, (a, s) => a + s.secs);
  final p = RefPalette.of(context);

  return ListView(
    padding: const EdgeInsets.only(bottom: 24),
    children: [
      // summary
      Padding(
        padding: const EdgeInsets.fromLTRB(2, 0, 2, 10),
        child: Text.rich(
          TextSpan(children: [
            TextSpan(
                text: '${list.length} protocol${list.length == 1 ? '' : 's'}',
                style: TextStyle(fontWeight: FontWeight.w800, color: p.ink)),
            TextSpan(
                text: ' · $totalRuns run${totalRuns == 1 ? '' : 's'}'
                    ' · ${_minutes(totalSecs)} in total'),
          ]),
          style: TextStyle(fontSize: 13.5, color: p.ink2),
        ),
      ),
      for (var i = 0; i < list.length; i++) ...[
        _ProtocolCard(stats: list[i], rank: i + 1),
        const SizedBox(height: 10),
      ],
    ],
  );
}

class _ProtocolCard extends StatelessWidget {
  final _ProtocolStats stats;
  final int rank;
  const _ProtocolCard({required this.stats, required this.rank});

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    final s = stats;
    final top = rank == 1;
    final helped = s.helpedPct;

    Widget stat(String value, String label,
            {CrossAxisAlignment align = CrossAxisAlignment.start}) =>
        Expanded(
          child: Column(
            crossAxisAlignment: align,
            children: [
              Text(value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w800,
                      color: p.ink,
                      fontFeatures: const [FontFeature.tabularFigures()])),
              Text(label, style: TextStyle(fontSize: 11.5, color: p.ink3)),
            ],
          ),
        );

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
            color: top ? const Color.fromRGBO(198, 158, 131, .75) : p.cardline,
            width: top ? 1.5 : 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // name row
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: top ? p.sunGrad : null,
                  color: top ? null : p.tanSoft,
                ),
                child: Text('$rank',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: top ? const Color(0xFF2A1A12) : p.copperInk)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w800,
                            height: 1.25,
                            color: p.ink)),
                    if (top) ...[
                      const SizedBox(height: 3),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: p.tanSoft,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text('Most used',
                            style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                color: p.copperInk)),
                      ),
                    ],
                  ],
                ),
              ),
              // Helped, top-right
              if (helped != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: helped >= 50 ? p.goodSoft : p.tanSoft,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Text('$helped%',
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              height: 1.1,
                              color: helped >= 50 ? p.good : p.copperInk,
                              fontFeatures: const [
                                FontFeature.tabularFigures()
                              ])),
                      Text('helped',
                          style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: helped >= 50 ? p.good : p.copperInk)),
                    ],
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          const SizedBox(height: 2),
          // stats
          Row(
            children: [
              stat('${s.runs.length}', s.runs.length == 1 ? 'Run' : 'Runs'),
              // spread across the card: left, middle, right edge
              stat(_minutes(s.secs), 'Total time',
                  align: CrossAxisAlignment.center),
              stat(_minutes(s.avg), 'Avg per run',
                  align: CrossAxisAlignment.end),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            [
              if (s.last != null) 'Last run ${_date(s.last)}',
              if (s.lastDevice != null) s.lastDevice!,
            ].join(' · '),
            style: TextStyle(fontSize: 12, color: p.ink3),
          ),
        ],
      ),
    );
  }
}

/// Loading state for Protocols: the summary line and a few cards in the
/// shape of [_ProtocolCard], gently pulsing.
class _ProtocolsSkeleton extends StatefulWidget {
  const _ProtocolsSkeleton();

  @override
  State<_ProtocolsSkeleton> createState() => _ProtocolsSkeletonState();
}

class _ProtocolsSkeletonState extends State<_ProtocolsSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) => _build(
          p,
          p.tanSoft.withValues(
              alpha: .5 + .5 * Curves.easeInOut.transform(_pulse.value))),
    );
  }

  /// The cards stay solid; only the placeholder bars pulse.
  Widget _build(RefPalette p, Color boneColor) {
    Widget bone(double w, double h, {double r = 6, bool circle = false}) =>
        Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            color: boneColor,
            shape: circle ? BoxShape.circle : BoxShape.rectangle,
            borderRadius: circle ? null : BorderRadius.circular(r),
          ),
        );

    Widget stat(CrossAxisAlignment align) => Expanded(
          child: Column(
            crossAxisAlignment: align,
            children: [
              bone(44, 15),
              const SizedBox(height: 6),
              bone(60, 10),
            ],
          ),
        );

    Widget card(double nameW) => Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
          decoration: BoxDecoration(
            color: p.card,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: p.cardline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  bone(30, 30, circle: true),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: nameW,
                        child: bone(double.infinity, 15),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  bone(54, 38, r: 12), // helped
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  stat(CrossAxisAlignment.start),
                  stat(CrossAxisAlignment.center),
                  stat(CrossAxisAlignment.end),
                ],
              ),
              const SizedBox(height: 12),
              Align(alignment: Alignment.centerLeft, child: bone(150, 11)),
            ],
          ),
        );

    return ListView(
      // still pull-to-refreshable while loading
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 2, 2, 12),
          child: Align(alignment: Alignment.centerLeft, child: bone(210, 13)),
        ),
        for (final w in const [.62, .48, .7, .55]) ...[
          card(w),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

// ── Usage ───────────────────────────────────────────────────────────────────

Widget _usage(BuildContext context, List<SessionHistoryItem> sessions) {
  final p = RefPalette.of(context);
  var secs = 0;
  DateTime? last;
  for (final s in sessions) {
    for (final pr in s.protocols) {
      secs += pr.duration ?? 0;
    }
    final at = s.createdAt;
    if (at != null && (last == null || at.isAfter(last))) last = at;
  }
  final n = sessions.length;
  final avg = n == 0 ? 0 : secs ~/ n;

  // Sessions per week, the last 8 weeks (oldest → newest).
  final now = DateTime.now();
  final weekStart = DateTime(now.year, now.month, now.day)
      .subtract(Duration(days: now.weekday - 1));
  final weeks = List<int>.filled(8, 0);
  for (final s in sessions) {
    final at = s.createdAt?.toLocal();
    if (at == null) continue;
    final diff = weekStart.difference(DateTime(at.year, at.month, at.day));
    final w = diff.isNegative ? 0 : (diff.inDays / 7).ceil();
    if (w < 8) weeks[7 - w]++;
  }
  Widget tile(String value, String label) => Expanded(
        child: _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w800, color: p.ink)),
              const SizedBox(height: 2),
              Text(label, style: TextStyle(fontSize: 12, color: p.ink3)),
            ],
          ),
        ),
      );

  return ListView(
    padding: const EdgeInsets.only(bottom: 24),
    children: [
      Row(children: [
        tile('$n', 'Sessions'),
        const SizedBox(width: 10),
        tile(_minutes(secs), 'Total time'),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        tile(_minutes(avg), 'Average session'),
        const SizedBox(width: 10),
        tile(last == null ? '—' : _date(last), 'Last session'),
      ]),
      const _Eyebrow('Sessions per week'),
      _WeeklyChart(
        weeks: weeks,
        starts: [
          for (var i = 0; i < 8; i++)
            weekStart.subtract(Duration(days: 7 * (7 - i))),
        ],
      ),
    ],
  );
}

/// Sessions per week over the last 8 weeks: this week against last week up
/// top, then a bar per week (this week in copper).
class _WeeklyChart extends StatelessWidget {
  /// Oldest → newest; the last is this week.
  final List<int> weeks;

  /// Each week's Monday, same order.
  final List<DateTime> starts;
  const _WeeklyChart({required this.weeks, required this.starts});

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    final nowIdx = weeks.length - 1;
    final thisWeek = weeks[nowIdx];
    final lastWeek = weeks[nowIdx - 1];
    final change = thisWeek - lastWeek;
    final peak = weeks.fold<int>(1, (a, b) => b > a ? b : a);
    final up = change > 0, down = change < 0;

    // bar heights live in [0, barMax]; the count sits above each bar
    const barMax = 92.0, countH = 18.0, plotH = barMax + countH;
    String label(DateTime d) => '${_months[d.month - 1]} ${d.day}';
    // Monday → Sunday, with the year (both, when the week crosses New Year)
    String range(DateTime d) {
      final end = d.add(const Duration(days: 6));
      return end.year == d.year
          ? '${label(d)} – ${label(end)}, ${end.year}'
          : '${label(d)}, ${d.year} – ${label(end)}, ${end.year}';
    }

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // this week vs last week
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text('$thisWeek',
                            style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w800,
                                height: 1.05,
                                color: p.ink)),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: up ? p.goodSoft : (down ? p.tanSoft : p.bg2),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            up
                                ? '\u25B2 +$change'
                                : (down ? '\u25BC ${-change}' : 'Same'),
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: up
                                    ? p.good
                                    : (down ? p.copperInk : p.ink3)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text('this week · $lastWeek last week',
                        style: TextStyle(fontSize: 12, color: p.ink3)),
                  ],
                ),
              ),
              Text('Last 8 weeks',
                  style: TextStyle(fontSize: 12, color: p.ink3)),
            ],
          ),
          const SizedBox(height: 16),
          // bars
          SizedBox(
            height: plotH,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // baseline
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(height: 1, color: p.line),
                ),
                Positioned.fill(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (var i = 0; i < weeks.length; i++) ...[
                        if (i > 0) const SizedBox(width: 8),
                        Expanded(
                          // tap a bar: its week's dates and count
                          child: Tooltip(
                            triggerMode: TooltipTriggerMode.tap,
                            showDuration: const Duration(seconds: 3),
                            preferBelow: false,
                            message: '${range(starts[i])}'
                                ' · ${weeks[i]} session'
                                '${weeks[i] == 1 ? '' : 's'}',
                            decoration: BoxDecoration(
                              color: p.ink,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            textStyle: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: p.card),
                            child: ColoredBox(
                              color: Colors.transparent,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  SizedBox(
                                    height: countH,
                                    child: weeks[i] == 0
                                        ? null
                                        : Text('${weeks[i]}',
                                            style: TextStyle(
                                                fontSize: 11.5,
                                                fontWeight: FontWeight.w800,
                                                color: i == nowIdx
                                                    ? p.copperInk
                                                    : p.ink2)),
                                  ),
                                  Container(
                                    // slim bars on wide screens
                                    constraints:
                                        const BoxConstraints(maxWidth: 44),
                                    height: weeks[i] == 0
                                        ? 4
                                        : (barMax * weeks[i] / peak)
                                            .clamp(8.0, barMax),
                                    decoration: BoxDecoration(
                                      gradient: i == nowIdx && weeks[i] > 0
                                          ? p.sunGrad
                                          : null,
                                      color: weeks[i] == 0
                                          ? p.bg2
                                          : (i == nowIdx
                                              ? null
                                              : p.copper
                                                  .withValues(alpha: .55)),
                                      borderRadius: const BorderRadius.vertical(
                                          top: Radius.circular(7),
                                          bottom: Radius.circular(2)),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          // week labels (each week's Monday)
          Row(
            children: [
              for (var i = 0; i < weeks.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    i == nowIdx ? 'Now' : label(starts[i]),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.visible,
                    style: TextStyle(
                        fontSize: 9.5,
                        fontWeight:
                            i == nowIdx ? FontWeight.w800 : FontWeight.w500,
                        color: i == nowIdx ? p.copperInk : p.ink3),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// ── Outcomes ────────────────────────────────────────────────────────────────

/// One post-session check-in answer.
class _Check {
  final DateTime at;
  final String protocol;
  final String question;
  final String answer;

  /// 1–5 for a preset answer, 0 for free text. Set per question by the
  /// admin, so the same wording ("Yes") can be good on one question and bad
  /// on another.
  final int rank;
  const _Check(this.at, this.protocol, this.question, this.answer, this.rank);

  // Same rule as the Hub's Improvement Score: an answer ranked 4+ helped.
  bool get helped => rank >= 4;
}

Widget _outcomes(BuildContext context, List<SessionHistoryItem> sessions) {
  final p = RefPalette.of(context);
  final checks = <_Check>[
    for (final s in sessions)
      if (s.createdAt != null)
        for (final pr in s.protocols)
          for (final qa in pr.questionAnswers)
            _Check(s.createdAt!, (pr.protocol ?? '').trim(), qa.question.trim(),
                qa.answer.trim(), qa.rank),
  ]..sort((a, b) => b.at.compareTo(a.at));
  final score = scoreOf([for (final c in checks) PulseCheck(c.at, c.helped)]);

  if (checks.isEmpty) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        const _OutcomeHero(pct: null, yes: 0, total: 0, last: null),
        const SizedBox(height: 24),
        _empty(context, 'Outcomes appear after the post-session check-in.'),
      ],
    );
  }

  // How sessions felt: per question, each preset answer with its count —
  // best answer first.
  final byQuestion = <String, Map<String, (int, int)>>{};
  for (final c in checks.where((c) => c.rank > 0)) {
    final q = c.question.isEmpty ? 'Check-in' : c.question;
    final a = c.answer.isEmpty ? 'Rated ${c.rank}' : c.answer;
    final answers = byQuestion.putIfAbsent(q, () => {});
    final prev = answers[a];
    answers[a] = ((prev?.$1 ?? 0) + 1, c.rank);
  }
  int count(Map<String, (int, int)> m) =>
      m.values.fold<int>(0, (x, v) => x + v.$1);
  final questions = byQuestion.entries.toList()
    ..sort((a, b) => count(b.value).compareTo(count(a.value)));

  // By protocol: helped % per protocol, most checked first.
  final byProtocol = <String, List<_Check>>{};
  for (final c in checks.where((c) => c.protocol.isNotEmpty)) {
    byProtocol.putIfAbsent(c.protocol, () => []).add(c);
  }
  final protocols = byProtocol.entries.toList()
    ..sort((a, b) => b.value.length.compareTo(a.value.length));

  Color tone(int rank) => rank >= 4 ? p.good : (rank == 3 ? p.mid : p.low);

  Widget bar(double share, Color color) => ClipRRect(
        borderRadius: BorderRadius.circular(99),
        child: Stack(
          children: [
            Container(height: 7, color: p.bg2),
            FractionallySizedBox(
              widthFactor: share.clamp(0.0, 1.0),
              child: Container(height: 7, color: color),
            ),
          ],
        ),
      );

  return ListView(
    padding: const EdgeInsets.only(bottom: 24),
    children: [
      _OutcomeHero(
          pct: score.pct,
          yes: score.yes,
          total: score.total,
          last: checks.first),
      if (questions.isNotEmpty) ...[
        const _Eyebrow('How sessions felt'),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final q in questions) ...[
                if (q != questions.first) ...[
                  const SizedBox(height: 14),
                  Divider(height: 1, color: p.line),
                  const SizedBox(height: 14),
                ],
                // the question
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(q.key,
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              height: 1.3,
                              color: p.ink2)),
                    ),
                    const SizedBox(width: 8),
                    Text(
                        '${count(q.value)} answer'
                        '${count(q.value) == 1 ? '' : 's'}',
                        style: TextStyle(fontSize: 11.5, color: p.ink3)),
                  ],
                ),
                const SizedBox(height: 10),
                // its answers, best first
                for (final (k, a) in (q.value.entries.toList()
                      ..sort((x, y) => y.value.$2.compareTo(x.value.$2)))
                    .indexed) ...[
                  if (k > 0) const SizedBox(height: 10),
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                            shape: BoxShape.circle, color: tone(a.value.$2)),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(a.key,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                                color: p.ink)),
                      ),
                      const SizedBox(width: 8),
                      Text('${a.value.$1}',
                          style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w800,
                              color: p.ink,
                              fontFeatures: const [
                                FontFeature.tabularFigures()
                              ])),
                      SizedBox(
                        width: 44,
                        child: Text(
                            '${(a.value.$1 / count(q.value) * 100).round()}%',
                            textAlign: TextAlign.right,
                            style: TextStyle(fontSize: 12, color: p.ink3)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  bar(a.value.$1 / count(q.value), tone(a.value.$2)),
                ],
              ],
            ],
          ),
        ),
      ],
      if (protocols.isNotEmpty) ...[
        const _Eyebrow('By protocol'),
        _Card(
          child: Column(
            children: [
              for (final e in protocols) ...[
                if (e != protocols.first) ...[
                  const SizedBox(height: 10),
                  Divider(height: 1, color: p.line),
                  const SizedBox(height: 10),
                ],
                () {
                  final yes = e.value.where((c) => c.helped).length;
                  final pct = (yes / e.value.length * 100).round();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(e.key,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w800,
                                        color: p.ink)),
                                Text(
                                    '$yes of ${e.value.length} check-in'
                                    '${e.value.length == 1 ? '' : 's'} helped',
                                    style: TextStyle(
                                        fontSize: 11.5, color: p.ink3)),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text('$pct%',
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: pct >= 50 ? p.good : p.copperInk,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures()
                                  ])),
                        ],
                      ),
                      const SizedBox(height: 8),
                      bar(pct / 100, pct >= 50 ? p.good : p.copper),
                    ],
                  );
                }(),
              ],
            ],
          ),
        ),
      ],
    ],
  );
}

/// Helped % in a ring, with the counts and the latest check-in beside it.
class _OutcomeHero extends StatelessWidget {
  final int? pct;
  final int yes;
  final int total;
  final _Check? last;
  const _OutcomeHero(
      {required this.pct,
      required this.yes,
      required this.total,
      required this.last});

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    final good = (pct ?? 0) >= 50;
    return _Card(
      child: Row(
        children: [
          SizedBox(
            width: 84,
            height: 84,
            child: CustomPaint(
              painter: _RingPainter(
                  share: (pct ?? 0) / 100,
                  track: p.bg2,
                  color: good ? p.good : p.copper),
              child: Center(
                child: Text(pct == null ? '—' : '$pct%',
                    style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                        color: p.ink,
                        fontFeatures: const [FontFeature.tabularFigures()])),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('SESSIONS HELPED',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                        color: p.ink3)),
                const SizedBox(height: 4),
                Text(
                  total == 0
                      ? 'No post-session check-ins yet'
                      : '$yes of $total check-in${total == 1 ? '' : 's'}'
                          ' said it helped',
                  style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      height: 1.3,
                      color: p.ink),
                ),
                if (last != null) ...[
                  const SizedBox(height: 4),
                  Text('Last check-in ${_date(last!.at)}',
                      style: TextStyle(fontSize: 12, color: p.ink3)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double share;
  final Color track;
  final Color color;
  _RingPainter({required this.share, required this.track, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 8.0;
    final rect = (Offset.zero & size).deflate(stroke / 2);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = track;
    canvas.drawArc(rect, 0, 6.2832, false, base);
    if (share > 0) {
      canvas.drawArc(
          rect,
          -1.5708,
          6.2832 * share.clamp(0.0, 1.0),
          false,
          base
            ..color = color
            ..strokeCap = StrokeCap.round);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.share != share || old.color != color || old.track != track;
}

// ── Chat ────────────────────────────────────────────────────────────────────

class _ChatTab extends ConsumerWidget {
  final String? clientId;
  final String name;
  const _ChatTab({required this.clientId, required this.name});

  Future<void> _delete(
      BuildContext context, WidgetRef ref, RagConversationSummary c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete conversation?'),
        content:
            const Text('This removes it for everyone in your organization.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref
          .read(ragChatHistoryRepositoryProvider)
          .deleteConversation(c.conversationId);
      ref.invalidate(ragConversationsProvider(clientId));
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Couldn’t delete. Try again.')));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = RefPalette.of(context);
    final async = ref.watch(ragConversationsProvider(clientId));
    return RefreshIndicator(
      color: p.copper,
      onRefresh: () async => ref.invalidate(ragConversationsProvider(clientId)),
      child: async.when(
        loading: () => Center(
            child: CircularProgressIndicator(strokeWidth: 2, color: p.copper)),
        error: (e, _) =>
            _empty(context, 'Couldn’t load conversations. Pull to retry.'),
        data: (list) => list.isEmpty
            ? _empty(context, 'No saved conversations yet.')
            : ListView.separated(
                padding: const EdgeInsets.only(bottom: 24),
                itemCount: list.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, i) {
                  final c = list[i];
                  final placement = c.lastMessage.startsWith('Pad placement:');
                  return Material(
                    color: p.card,
                    borderRadius: BorderRadius.circular(18),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => ChatTranscriptScreen(
                            conversationId: c.conversationId,
                            when: c.lastAt,
                            name: name,
                          ),
                        ),
                      ),
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: p.cardline),
                        ),
                        child: Row(
                          children: [
                            Icon(
                                placement
                                    ? Icons.accessibility_new_rounded
                                    : Icons.chat_bubble_outline_rounded,
                                size: 20,
                                color: p.copperInk),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(c.lastMessage,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: p.ink)),
                                  const SizedBox(height: 3),
                                  Text(
                                    '${_dateTime(c.lastAt)} · '
                                    '${c.messageCount} messages',
                                    style:
                                        TextStyle(fontSize: 12, color: p.ink3),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: 'Delete conversation',
                              icon: Icon(Icons.delete_outline_rounded,
                                  color: p.ink3),
                              onPressed: () => _delete(context, ref, c),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

/// One saved conversation, read-only. A message that carried a pad placement
/// shows it as a card that reopens the 3D pad map.
class ChatTranscriptScreen extends ConsumerWidget {
  final String conversationId;
  final DateTime? when;
  final String name;
  const ChatTranscriptScreen({
    super.key,
    required this.conversationId,
    required this.when,
    required this.name,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = RefPalette.of(context);
    final side =
        HwTablet.sidePadding(context, column: HwTablet.read, phone: 16);
    final async = ref.watch(ragConversationProvider(conversationId));
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: side),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 10),
              Row(
                children: [
                  _RoundButton(
                    icon: Icons.chevron_left_rounded,
                    label: 'Back',
                    onTap: () => Navigator.of(context).maybePop(),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Conversation',
                            style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: p.ink)),
                        Text(_dateTime(when),
                            style: TextStyle(fontSize: 13, color: p.ink3)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: async.when(
                  loading: () => Center(
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: p.copper)),
                  error: (e, _) =>
                      _empty(context, 'Couldn’t load this conversation.'),
                  data: (msgs) => ListView.builder(
                    padding: const EdgeInsets.only(bottom: 24),
                    itemCount: msgs.length,
                    itemBuilder: (context, i) {
                      final m = msgs[i];
                      if (m.placement != null) {
                        return _PlacementCard(message: m, clientName: name);
                      }
                      return Align(
                        alignment: m.isUser
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          constraints: const BoxConstraints(maxWidth: 440),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: m.isUser ? p.copper : p.card,
                            borderRadius: BorderRadius.circular(16),
                            border:
                                m.isUser ? null : Border.all(color: p.cardline),
                          ),
                          child: Text(m.message,
                              style: TextStyle(
                                  fontSize: 14,
                                  height: 1.35,
                                  color: m.isUser ? Colors.white : p.ink)),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A saved pad placement: its name and sets, and "View in 3D" — the same
/// pad map the Assistant opened when it was made.
class _PlacementCard extends StatelessWidget {
  final RagMessage message;
  final String clientName;
  const _PlacementCard({required this.message, required this.clientName});

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    final payload = PadSetPayload.fromJson(message.placement!);
    final recovery = payload.discipline == 'recovery';
    final title = payload.displayName.isNotEmpty
        ? payload.displayName
        : message.message.replaceFirst('Pad placement: ', '');
    final sets = payload.sets.length;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          gradient: p.heroGrad,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.accessibility_new_rounded,
                  color: Colors.white),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(recovery ? 'RECOVERY PLACEMENT' : 'PAD PLACEMENT',
                      style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1,
                          color: Color(0xFFDDCABF))),
                  Text(title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: Colors.white)),
                  if (sets > 0)
                    Text('$sets set${sets == 1 ? '' : 's'} · Sun & Moon',
                        style: const TextStyle(
                            fontSize: 12, color: Color(0xFFDDCABF))),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Material(
              borderRadius: BorderRadius.circular(999),
              clipBehavior: Clip.antiAlias,
              child: Ink(
                decoration: BoxDecoration(gradient: p.sunGrad),
                child: InkWell(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => PadMapScreen(
                        payload: payload,
                        clientName: clientName,
                        title: recovery
                            ? 'Recovery Placement'
                            : 'Performance Placement',
                        preloadProtocol: !recovery,
                      ),
                    ),
                  ),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                    child: Text('View in 3D',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF2A1A12))),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
