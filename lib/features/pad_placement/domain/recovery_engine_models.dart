// The recovery ENGINE (chip-flow) models — `recovery-engine-v3/intake` and
// `recovery-engine-v3/resolve`.
//
// Deliberately separate from `recovery_chat_models.dart`: that file models the
// conversational surface, whose `render` carries `sets` and no pads. This one
// models the guided surface, which returns the real authored pad geometry —
// `pad_label`, `body_side`, `landmark_anchor`, `target_muscles` — i.e. exactly
// the fields the performance pad map already renders.
//
// WHICH IS WHY [RecoveryPlacement.payload] IS A `PadSetPayload`. Recovery and
// performance answer with the same thing — a Sun/Moon pad per set, anchored to a
// landmark and a list of target muscles — so they get the same card, the same 3D
// stage and the same marker mapper. The alternative, a second renderer fed by a
// second model, is how the two surfaces come to disagree about what a pad is.
// Everything that is genuinely recovery-only (the thermal note, the wellness
// claim, the refer-out) is kept on this class and never forced into the
// performance shape.

import '../../../core/constants/api_endpoints.dart';
import '../../performance_protocols/domain/performance_models.dart';

/// WHICH RECOVERY GENERATION THIS CLIENT IS TALKING TO — one decision, in one
/// place. Port of the web's `engine/recoveryGeneration.js`.
///
/// A generation is a SET of endpoints and they are handed out together or not at
/// all. The web's own bug is the reason: it fetched the screen and the catalogue
/// from v2 while taking the region list from v3, then resolved against v2 with
/// v3's region keys — so a pathway holding 156 points answered "none authored".
///
/// [readFrom] returns NULL for anything it does not recognise, and null is a real
/// answer rather than a v2: "I could not find out" and "it is v2" are different
/// facts and only one of them is safe to act on.
class RecoveryGeneration {
  final String id;
  final String label;
  final String screenPath;
  final String catalogPath;
  final String resolvePath;

  const RecoveryGeneration._({
    required this.id,
    required this.label,
    required this.screenPath,
    required this.catalogPath,
    required this.resolvePath,
  });

  static const v2 = RecoveryGeneration._(
    id: 'v2',
    label: 'v2.0',
    screenPath: ApiEndpoints.recoveryV2Screen,
    catalogPath: ApiEndpoints.recoveryV2Catalog,
    resolvePath: ApiEndpoints.recoveryV2Resolve,
  );

  static const v3 = RecoveryGeneration._(
    id: 'v3',
    label: 'v3.1',
    screenPath: ApiEndpoints.recoveryScreen,
    catalogPath: ApiEndpoints.recoveryIntake,
    resolvePath: ApiEndpoints.recoveryResolve,
  );

  bool get isV3 => id == 'v3';

  static RecoveryGeneration? readFrom(dynamic cutover) {
    final raw = (cutover is Map ? cutover['generation'] : null)
            ?.toString()
            .trim()
            .toLowerCase() ??
        '';
    if (raw == 'v3') return v3;
    if (raw == 'v2') return v2;
    return null;
  }
}

/// The cutover verdict, and the calls it authorises.
class RecoveryDispatch {
  final RecoveryGeneration generation;

  /// The server's own sentence for why this generation is serving. Shown so
  /// "which library am I looking at?" is answerable from the screen during a
  /// changeover rather than only from a log.
  final String reason;

  /// True when the serving generation has no live points at all — a real state,
  /// and not the same as a request that failed.
  final bool servingNothing;

  /// How many points the serving library reports holding. Read together with an
  /// empty [catalog] this is the difference between two very different faults —
  /// see [emptyCatalogReason].
  final int livePoints;

  final RecoveryIntakeCatalog catalog;
  final RecoverySafetyScreen screen;

  const RecoveryDispatch({
    required this.generation,
    this.reason = '',
    this.servingNothing = false,
    this.livePoints = 0,
    this.catalog = const RecoveryIntakeCatalog(),
    this.screen = const RecoverySafetyScreen(),
  });

  bool get hasNothingToOffer => servingNothing || catalog.isEmpty;

  /// WHY there is nothing to offer, and the two cases are not the same fault.
  ///
  /// "Nothing is published" and "the library holds N points and is refusing
  /// every one of them" send you to completely different places — the first to
  /// whoever authors the content, the second to the ingest, which is where a
  /// corpus gets excluded wholesale for an authoring finding on the records.
  /// Collapsing them into one sentence is what makes a backend problem look
  /// like an empty app.
  ///
  /// The cutover's own `reason` is only quoted where it actually explains the
  /// emptiness. When the library reports points, that sentence says why THIS
  /// generation serves — which reads as a contradiction next to "there is
  /// nothing here", so it is deliberately not repeated.
  String get emptyCatalogReason {
    if (livePoints > 0 && catalog.isEmpty) {
      return 'The recovery library reports $livePoints point(s) but none of '
          'them can be offered — every one is being excluded before it reaches '
          'the catalogue. That is an authoring or ingest gap on the backend, '
          'not something this app can work around.';
    }
    final why = reason.trim();
    return 'The recovery library has nothing published to work from right now.'
        '${why.isEmpty ? '' : '\n\n$why'}';
  }
}

/// `GET …/screen` — the authored red-flag questions and the client disclaimer.
///
/// The questions are NOT asked in the UI (web parity, Jul 29 review): they are
/// replaced by one always-visible disclaimer line. They are still fetched and
/// still answered on the wire, so the request shape is unchanged and the ENGINE
/// still runs the universal pre-gate on every resolve. What was removed is the
/// client-side asking, not the gate.
class RecoverySafetyScreen {
  final List<RecoveryScreenQuestion> questions;

  /// The authored client sentence. [disclaimerOrFallback] is what to render.
  final String disclaimer;

  const RecoverySafetyScreen({
    this.questions = const [],
    this.disclaimer = '',
  });

  /// Deliberately shorter and more generic than the authored line rather than a
  /// copy of it — a second version of the clinical wording is a second thing to
  /// drift. This is a floor, not an alternative.
  static const fallbackDisclaimer =
      'General wellness guidance, not medical advice and not a diagnosis. If '
      'anything feels wrong, stop and check with a qualified professional.';

  String get disclaimerOrFallback =>
      disclaimer.trim().isEmpty ? fallbackDisclaimer : disclaimer.trim();

  /// Every authored flag, answered NO, keyed by the ENDPOINT'S OWN question keys.
  ///
  /// Built from the payload rather than from a list here for the same reason the
  /// web builds it that way: a client-side list of keys is a second copy of the
  /// gate living somewhere that cannot enforce it, and it goes stale silently the
  /// first time a question is authored. An empty `{}` is also NOT the same
  /// statement — that is "not asked", where this is "asked and answered no".
  Map<String, dynamic> get allFlagsNo => {
        for (final q in questions)
          if (q.key.trim().isNotEmpty) q.key: false,
      };

  factory RecoverySafetyScreen.fromJson(Map<String, dynamic> json) {
    final data = json['data'] is Map
        ? Map<String, dynamic>.from(json['data'] as Map)
        : json;
    return RecoverySafetyScreen(
      questions: data['questions'] is List
          ? (data['questions'] as List)
              .whereType<Map>()
              .map((e) =>
                  RecoveryScreenQuestion.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : const [],
      disclaimer: (data['disclaimer'] ?? '').toString(),
    );
  }
}

class RecoveryScreenQuestion {
  final String key;
  final String question;

  /// `universal` | `trunk`. Only universal questions hard-block everywhere —
  /// pregnancy is trunk-scoped, so blocking every pathway on it would refuse an
  /// ankle placement the rulebook allows. WHICH flags block is authored here and
  /// never restated client-side.
  final String scope;

  /// `refer_out` | `absolute_contraindication`.
  final String gate;

  const RecoveryScreenQuestion({
    required this.key,
    this.question = '',
    this.scope = 'universal',
    this.gate = 'refer_out',
  });

  factory RecoveryScreenQuestion.fromJson(Map<String, dynamic> json) =>
      RecoveryScreenQuestion(
        key: (json['key'] ?? '').toString(),
        question: (json['question'] ?? '').toString(),
        scope: (json['scope'] ?? 'universal').toString(),
        gate: (json['gate'] ?? 'refer_out').toString(),
      );
}

/// One authored movement test for a region. [reveals] is the config's clinical
/// reading of the test and is often blank — the corpus can be authored against a
/// test the config does not describe, and that wording is never invented here.
class RecoveryMovementTest {
  final String test;
  final String reveals;

  const RecoveryMovementTest({required this.test, this.reveals = ''});

  factory RecoveryMovementTest.fromJson(Map<String, dynamic> json) =>
      RecoveryMovementTest(
        test: (json['test'] ?? '').toString(),
        reveals: (json['reveals'] ?? '').toString(),
      );
}

/// One region the live corpus can answer for.
///
/// [region] is the CANONICAL id and the only thing `resolve` will match on;
/// [displayName] is for the chip. Sending the label is the failure mode this
/// class exists to prevent — the engine answers `point: null` and the flow dead
/// ends with no error to show.
class RecoveryRegion {
  final String region;
  final String displayName;
  final List<String> anatomicalNames;
  final List<RecoveryMovementTest> movementTests;

  /// Where else the pattern may travel to, as canonical ids — the engine's
  /// `referral_target`. Never the complaint region itself.
  final List<String> referralMenu;

  /// The sides this region was authored against: `right` / `left` / `both`.
  final List<String> sides;

  /// Front/back or medial/lateral, offered ONLY when [aspectOffered] — one
  /// authored value is not a question.
  final List<String> aspects;
  final bool aspectOffered;

  /// The goals this region can answer for. A region with only discomfort points
  /// genuinely cannot serve a range-of-motion request.
  final List<String> goalPathways;

  /// False when the region carries no selectable point — it is listed so a
  /// client can explain the gap, and must not be offered as a chip.
  final bool known;

  const RecoveryRegion({
    required this.region,
    this.displayName = '',
    this.anatomicalNames = const [],
    this.movementTests = const [],
    this.referralMenu = const [],
    this.sides = const [],
    this.aspects = const [],
    this.aspectOffered = false,
    this.goalPathways = const [],
    this.known = true,
  });

  String get label =>
      displayName.trim().isEmpty ? _humanize(region) : displayName.trim();

  /// True when this region was authored on both sides, so asking is meaningful.
  bool get asksSide => sides.length > 1;

  factory RecoveryRegion.fromJson(Map<String, dynamic> json) => RecoveryRegion(
        region: (json['region'] ?? '').toString(),
        displayName: (json['display_name'] ?? json['displayName'] ?? '')
            .toString(),
        anatomicalNames:
            _strings(json['anatomical_names'] ?? json['anatomicalNames']),
        movementTests: (json['movement_tests'] is List)
            ? (json['movement_tests'] as List)
                .whereType<Map>()
                .map((e) =>
                    RecoveryMovementTest.fromJson(Map<String, dynamic>.from(e)))
                .where((t) => t.test.trim().isNotEmpty)
                .toList()
            : const [],
        referralMenu: _strings(json['referral_menu'] ?? json['referralMenu']),
        sides: _strings(json['sides']),
        aspects: _strings(json['aspects']),
        aspectOffered: json['aspect_offered'] == true,
        goalPathways: _strings(json['goal_pathways'] ?? json['goalPathways']),
        known: json['known'] != false,
      );

  /// The v2 catalogue's region entry, which is a different shape and a poorer
  /// one: no display name, no aspects, and `movementTests` is a list of bare
  /// strings with no authored `reveals`.
  ///
  /// The missing fields stay missing. Manufacturing a `reveals` sentence or an
  /// aspect list here would put clinical wording in the client, which is exactly
  /// what reading the catalogue is meant to stop.
  factory RecoveryRegion.fromV2Json(Map<String, dynamic> json, String goal) {
    final hasTest = json['hasMovementTest'] == true;
    return RecoveryRegion(
      region: (json['region'] ?? '').toString(),
      movementTests: hasTest
          ? _strings(json['movementTests'])
              .map((t) => RecoveryMovementTest(test: t))
              .toList()
          : const [],
      referralMenu: _strings(json['referrals']),
      sides: _strings(json['sides']),
      goalPathways: [goal],
      known: _int(json['points'], 0) > 0,
    );
  }

  /// One region seen under a second pathway. Only the goal list genuinely
  /// differs — the tests, menu and sides are properties of the region — so this
  /// unions the goals and keeps whichever entry actually carried detail.
  RecoveryRegion mergedWith(RecoveryRegion other) => RecoveryRegion(
        region: region,
        displayName: displayName.isEmpty ? other.displayName : displayName,
        anatomicalNames:
            anatomicalNames.isEmpty ? other.anatomicalNames : anatomicalNames,
        movementTests:
            movementTests.isEmpty ? other.movementTests : movementTests,
        referralMenu: referralMenu.isEmpty ? other.referralMenu : referralMenu,
        sides: {...sides, ...other.sides}.toList(),
        aspects: aspects.isEmpty ? other.aspects : aspects,
        aspectOffered: aspectOffered || other.aspectOffered,
        goalPathways: {...goalPathways, ...other.goalPathways}.toList(),
        known: known || other.known,
      );
}

/// The authored catalogue — `recovery-engine-v3/intake` OR `recovery-engine/catalog`.
///
/// The two generations return genuinely different shapes and NEITHER is a
/// fallback for the other, so each is read the way it is actually sent and both
/// land on the same [RecoveryRegion]. That normalisation is the whole reason the
/// flow above it does not have to know which library is serving.
class RecoveryIntakeCatalog {
  final String version;

  /// Every region the corpus can serve under SOME goal, in head-to-foot order.
  /// The right answer to "what does this library cover?" and the WRONG one to
  /// "what may I offer now?" — see [regionsFor].
  final List<RecoveryRegion> regions;

  /// Per-goal region lists, scoped by the server through the same live filter
  /// and the same gate exclusions the resolve applies.
  final Map<String, List<RecoveryRegion>> byGoal;

  /// Authored points per goal, for the goal cards' "N authored" line. v3 returns
  /// the pathway total directly (a v3 region belongs to no single pathway); v2
  /// has to be summed over its regions.
  final Map<String, int> pointsByGoal;

  const RecoveryIntakeCatalog({
    this.version = '',
    this.regions = const [],
    this.byGoal = const {},
    this.pointsByGoal = const {},
  });

  bool get isEmpty => regions.isEmpty;

  /// How many points a pathway is authored with.
  ///
  /// NOT what decides whether a goal is offered. All four are always asked — the
  /// web asks all four too — because "can this pathway answer?" is really a
  /// question about REGIONS, and it is answered at the next step against that
  /// pathway's own list. Gating the goal chips on a count would also hide a goal
  /// whenever the catalogue is merely slow, which is the wrong failure.
  int pointsFor(String goal) => pointsByGoal[goal] ?? 0;

  /// The regions to offer for [goal].
  ///
  /// SCOPED, and that is the fix for a bug the web shipped three times. The
  /// whole-corpus list under every pathway makes `performance_recovery` +
  /// `full-body` offerable, which no point can answer. Falls back through
  /// progressively weaker evidence rather than to nothing: an offer built from a
  /// stale catalogue is recoverable (the resolve says so), an empty chip row is a
  /// dead end with nothing to say.
  List<RecoveryRegion> regionsFor(String? goal) {
    final key = (goal ?? '').trim();
    if (key.isEmpty) return regions.where((r) => r.known).toList();

    final scoped = byGoal[key];
    if (scoped != null && scoped.isNotEmpty) {
      return scoped.where((r) => r.known).toList();
    }

    final declared =
        regions.where((r) => r.known && r.goalPathways.contains(key)).toList();
    if (declared.isNotEmpty) return declared;

    return regions.where((r) => r.known).toList();
  }

  RecoveryRegion? byId(String? id, {String? goal}) {
    final key = (id ?? '').trim().toLowerCase();
    if (key.isEmpty) return null;
    for (final r in [...regionsFor(goal), ...regions]) {
      if (r.region.toLowerCase() == key) return r;
    }
    return null;
  }

  /// v3.1 — `{version, region_order, regions[], pathways:[{goal_pathway, points,
  /// region_order, regions[]}]}`.
  factory RecoveryIntakeCatalog.fromV3Json(Map<String, dynamic> json) {
    final data = _envelope(json);
    final byGoal = <String, List<RecoveryRegion>>{};
    final points = <String, int>{};

    final pathways = data['pathways'];
    if (pathways is List) {
      for (final row in pathways.whereType<Map>()) {
        final goal = (row['goal_pathway'] ?? '').toString().trim();
        if (goal.isEmpty) continue;
        // `region_order` and `regions` come from the SAME entry, so the order
        // and the entries cannot be drawn from two different lists.
        byGoal[goal] = _ordered(row['regions'], row['region_order']);
        points[goal] = _int(row['points'], 0);
      }
    }

    return RecoveryIntakeCatalog(
      version: (data['version'] ?? '').toString(),
      regions: _ordered(data['regions'], data['region_order']),
      byGoal: byGoal,
      pointsByGoal: points,
    );
  }

  /// v2 — `{pathways:[{goal_pathway, regions:[{region, points, hasMovementTest,
  /// movementTests[], referrals[], sides[]}]}], corpus}`.
  ///
  /// No display names, no aspects, and `movementTests` are bare strings with no
  /// authored `reveals`. All of that is absent from the payload, so it is left
  /// absent here rather than invented — the region key is humanised for the chip
  /// and nothing else is filled in.
  factory RecoveryIntakeCatalog.fromV2Json(Map<String, dynamic> json) {
    final data = _envelope(json);
    final byGoal = <String, List<RecoveryRegion>>{};
    final points = <String, int>{};
    final all = <String, RecoveryRegion>{};

    final pathways = data['pathways'];
    if (pathways is List) {
      for (final row in pathways.whereType<Map>()) {
        final goal = (row['goal_pathway'] ?? '').toString().trim();
        if (goal.isEmpty) continue;
        final regions = <RecoveryRegion>[];
        var total = 0;
        for (final r in (row['regions'] is List ? row['regions'] as List : [])
            .whereType<Map>()) {
          final region = RecoveryRegion.fromV2Json(
              Map<String, dynamic>.from(r), goal);
          if (region.region.trim().isEmpty) continue;
          regions.add(region);
          total += _int(r['points'], 0);
          // A region serves several pathways; merge so the corpus-wide list
          // names each one once and carries every goal it can answer for.
          final seen = all[region.region];
          all[region.region] = seen == null
              ? region
              : seen.mergedWith(region);
        }
        byGoal[goal] = regions;
        points[goal] = total;
      }
    }

    return RecoveryIntakeCatalog(
      version: 'v2',
      regions: all.values.toList(),
      byGoal: byGoal,
      pointsByGoal: points,
    );
  }

  static Map<String, dynamic> _envelope(Map<String, dynamic> json) =>
      json['data'] is Map
          ? Map<String, dynamic>.from(json['data'] as Map)
          : json;

  /// Regions in the authored head-to-foot order the payload declares, not the
  /// order the corpus happened to produce and not alphabetical.
  static List<RecoveryRegion> _ordered(dynamic rawRegions, dynamic rawOrder) {
    final parsed = rawRegions is List
        ? rawRegions
            .whereType<Map>()
            .map((e) => RecoveryRegion.fromJson(Map<String, dynamic>.from(e)))
            .where((r) => r.region.trim().isNotEmpty)
            .toList()
        : <RecoveryRegion>[];
    if (rawOrder is! List || rawOrder.isEmpty) return parsed;

    final byKey = {for (final r in parsed) r.region: r};
    final out = <RecoveryRegion>[];
    for (final key in rawOrder.map((e) => e?.toString() ?? '')) {
      final hit = byKey.remove(key);
      if (hit != null) out.add(hit);
    }
    // Anything the order does not name still gets offered, after the ones it
    // does — dropping it would hide servable content.
    return [...out, ...parsed.where(byKey.containsValue)];
  }
}

/// The four goal pathways — the "What are we working on?" step, and the first
/// question the flow asks.
///
/// Titles and blurbs are the web's `PATHWAYS`, verbatim, so the same choice reads
/// the same in both clients. The VALUES are the contract — the request DTO
/// rejects anything else — and are never derived from a label.
///
/// GOAL BEFORE REGION, and the order is load-bearing rather than cosmetic: the
/// region list is scoped to the chosen pathway, so asking for an area first means
/// offering areas that pathway cannot answer for.
class RecoveryGoal {
  final String value;
  final String label;

  /// One line saying what this pathway is for, shown under the chip.
  final String blurb;

  const RecoveryGoal(this.value, this.label, [this.blurb = '']);

  static const discomfort = RecoveryGoal(
    'discomfort',
    'Discomfort',
    'Something hurts, feels tight or restricted. Includes a movement test '
        'where one exists.',
  );
  static const rangeOfMotion = RecoveryGoal(
    'range_of_motion',
    'Joint mobility',
    'You want more range in a joint. Direct select, no test.',
  );
  static const performanceRecovery = RecoveryGoal(
    'performance_recovery',
    'Post-workout',
    'Recovery for an area you have just trained.',
  );
  static const lymphatic = RecoveryGoal(
    'lymphatic_activation',
    'Lymphatic',
    'An area feels heavy, puffy or swollen.',
  );

  static const all = <RecoveryGoal>[
    discomfort,
    rangeOfMotion,
    performanceRecovery,
    lymphatic,
  ];

  static RecoveryGoal? byValue(String? value) {
    for (final g in all) {
      if (g.value == value) return g;
    }
    return null;
  }

  static String labelFor(String value) => byValue(value)?.label ?? _humanize(value);

  /// Only the discomfort pathway runs a movement test and offers a referral —
  /// web parity, and the same reason: the other three ask only what they need.
  bool get asksMovementTest => value == discomfort.value;
  bool get asksReferral => value == discomfort.value;

  /// Lymphatic is the one pathway that does not ask a side: it is drainage
  /// through a hub, not a one-sided complaint.
  bool get asksSide => value != lymphatic.value;

  /// The region question, in this pathway's own words.
  String get regionPrompt {
    switch (value) {
      case 'range_of_motion':
        return 'Which joint or zone do you want more range in?';
      case 'performance_recovery':
        return 'What did you train?';
      case 'lymphatic_activation':
        return 'Which area feels heavy?';
      default:
        return 'Where is the discomfort?';
    }
  }
}

/// `POST recovery-engine-v3/resolve` — one resolved recovery placement.
class RecoveryPlacement {
  /// The authored point this answer came from (`rec-acute-lowback-v1`).
  final String recoveryId;

  /// The canonical region the engine actually resolved, which is not always the
  /// one asked for — a referral can move the driver to another area.
  final String region;

  /// The goal the engine APPLIED. The "heavy / puffy / swollen" reroute sends a
  /// discomfort request down the lymphatic branch, so this can differ from what
  /// was requested and the UI should read this one.
  final String pathway;

  /// `v2` / `v3` — which generation served this. Carried so a placement can say
  /// where it came from; nothing in the UI branches on it.
  final String generation;

  /// The safety answer. When true there are NO pads, by design: the message is
  /// delivered and the placement is withheld.
  final bool referOut;
  final String? referOutReason;

  /// The engine's own description of what it is treating.
  final String driverDescription;
  final String finding;

  /// The movement test the point is authored against (not necessarily the one
  /// that was sent).
  final String movementTest;

  /// `hot_pack` / `cold_pack` / `slow_switch` / `fast_switch`, plus its authored
  /// reasoning. A RECOMMENDATION — the device is not driven from it.
  final String thermalMode;
  final String thermalRationale;

  /// The compliance-authored client sentence. Rendered verbatim: the backend
  /// owns this wording and it is never rephrased here.
  final String wellnessClaim;
  final String mechanismRationale;
  final String expectedSensation;
  final String reassessmentMarker;

  /// Relative cautions worth showing. Absolute contraindications arrive as a
  /// refer-out instead, which suppresses the pads.
  final List<String> cautions;

  /// The pads, in the shape the performance card and pad map already read.
  final PadSetPayload payload;

  final Map<String, dynamic> raw;

  const RecoveryPlacement({
    this.recoveryId = '',
    this.region = '',
    this.pathway = '',
    this.generation = '',
    this.referOut = false,
    this.referOutReason,
    this.driverDescription = '',
    this.finding = '',
    this.movementTest = '',
    this.thermalMode = '',
    this.thermalRationale = '',
    this.wellnessClaim = '',
    this.mechanismRationale = '',
    this.expectedSensation = '',
    this.reassessmentMarker = '',
    this.cautions = const [],
    this.payload = const PadSetPayload(),
    this.raw = const {},
  });

  /// A placement was resolved AND may be drawn. A refer-out returns a point and
  /// no sets, so "there is a point" is not the test.
  bool get hasPads => !referOut && payload.sets.isNotEmpty;

  /// What to say when there are no pads: the refer-out reason if the gate gave
  /// one, otherwise the honest "nothing authored for this combination".
  String get emptyReason {
    final reason = referOutReason?.trim() ?? '';
    if (reason.isNotEmpty) return reason;
    if (referOut) {
      return 'This one is better looked at in person before any placement.';
    }
    return 'There’s no authored placement for that combination yet.';
  }

  /// `cold_pack` → `Cold pack`.
  String get thermalLabel => _humanize(thermalMode);

  factory RecoveryPlacement.fromJson(
    Map<String, dynamic> json, {
    String? regionLabel,
  }) {
    final data = json['data'] is Map
        ? Map<String, dynamic>.from(json['data'] as Map)
        : json;

    final point = _map(data['point']);
    final safety = _map(data['safety']);
    // `pointSafety` is v2's name for it, `safetyBlock` is v3's. Whichever
    // generation served this, the point's own refer-out lives in one of the two.
    final pointSafety = _map(data['pointSafety']).isNotEmpty
        ? _map(data['pointSafety'])
        : _map(data['safetyBlock']);
    final assessment = _map(data['assessment']);
    final thermal = _map(data['thermal']);
    final intent = _map(data['clinical_intent']);
    final driver = _map(data['driver']);

    final region = (point['region'] ?? data['region'] ?? '').toString();
    final pathway = (data['pathway'] ?? point['goal_pathway'] ?? '').toString();
    final label = (regionLabel ?? '').trim().isEmpty
        ? _humanize(region)
        : regionLabel!.trim();

    // The gate's refer-out and the point's own are the same outcome for the
    // reader — pads withheld — so they are collapsed into one flag here rather
    // than leaving every call site to remember both.
    final referOut =
        safety['refer_out'] == true || pointSafety['refer_out'] == true;
    final referOutReason = _firstNonEmpty([
      safety['reason'],
      safety['refer_out_reason'],
      pointSafety['refer_out_reason'],
      data['reply'],
      data['message'],
    ]);

    final finding = (assessment['finding'] ?? '').toString();
    final driverDescription = (driver['description'] ?? '').toString();

    return RecoveryPlacement(
      recoveryId: (point['recovery_id'] ?? '').toString(),
      region: region,
      pathway: pathway,
      generation: (data['generation'] ?? '').toString(),
      referOut: referOut,
      referOutReason: referOutReason,
      driverDescription: driverDescription,
      finding: finding,
      movementTest: (assessment['movement_test'] ?? '').toString(),
      thermalMode: (thermal['mode'] ?? '').toString(),
      thermalRationale: (thermal['rationale'] ?? '').toString(),
      wellnessClaim: (intent['wellness_claim_wording'] ?? '').toString(),
      mechanismRationale: (intent['mechanism_rationale'] ?? '').toString(),
      expectedSensation: (intent['expected_sensation'] ?? '').toString(),
      reassessmentMarker: (intent['reassessment_marker'] ??
              _map(data['session'])['reassessment_marker'] ??
              '')
          .toString(),
      cautions: _strings(pointSafety['cautions_relative']),
      payload: _payloadFrom(
        data,
        regionLabel: label,
        pathway: pathway,
        finding: finding.trim().isEmpty ? driverDescription : finding,
        movementTest: (assessment['movement_test'] ?? '').toString(),
        thermalMode: (thermal['mode'] ?? '').toString(),
        mechanism: (intent['mechanism_rationale'] ?? '').toString(),
      ),
      raw: data,
    );
  }

  /// Recovery's `sets[].pads[]` → performance's `sets[].sun/moon`.
  ///
  /// The two corpora describe a pad with the SAME facts under two spellings, so
  /// this is a rename and not a translation: `position` is performance's
  /// `position_along_muscle`, and `aspect` is its `plane` on a v3 pad, which
  /// dropped `plane` (a v2 pad still carries both, and its own wins). Everything
  /// the marker mapper reads — `landmark_anchor`, `target_muscles`, `side`,
  /// `proxy_for` — is already spelled identically, which is why the 3D stage
  /// needs no recovery-specific path at all.
  static PadSetPayload _payloadFrom(
    Map<String, dynamic> data, {
    required String regionLabel,
    required String pathway,
    required String finding,
    required String movementTest,
    required String thermalMode,
    required String mechanism,
  }) {
    final rawSets = data['sets'];
    final sets = <PadSet>[];

    if (rawSets is List) {
      for (final row in rawSets.whereType<Map>()) {
        final set = Map<String, dynamic>.from(row);
        final pads = set['pads'];
        Pad? sun;
        Pad? moon;
        if (pads is List) {
          for (final p in pads.whereType<Map>()) {
            final pad = _normalisePad(Map<String, dynamic>.from(p));
            final role = (pad['pad_label'] ?? '').toString().toLowerCase();
            if (role == 'sun') {
              sun ??= Pad.fromJson(pad);
            } else if (role == 'moon') {
              moon ??= Pad.fromJson(pad);
            }
          }
        }
        if (sun == null && moon == null) continue;

        final note = (set['note'] ?? '').toString().trim();
        sets.add(PadSet(
          setIndex: _int(set['set_index'], sets.length + 1),
          // `primary_site` → `primary site`, so the pad map's role line reads as
          // words. It uppercases whatever it is handed.
          role: _humanize((set['set_role'] ?? '').toString()).toLowerCase(),
          placementLabel: note.isEmpty ? regionLabel : note,
          // The authored reasoning, which is what the card's "Why this
          // placement" expander is for. Set-level note first when there is one:
          // it is about THIS set, where the mechanism is about the whole point.
          clinicalReasoning: note.isEmpty ? mechanism : '$note\n\n$mechanism',
          sun: sun,
          moon: moon,
        ));
      }
    }
    sets.sort((a, b) => a.setIndex.compareTo(b.setIndex));

    return PadSetPayload(
      discipline: 'recovery',
      displayName: regionLabel,
      role: RecoveryGoal.labelFor(pathway),
      // A non-null chain is what makes `isRefusal` false, so it is built only
      // when there are pads — an empty chain with empty sets would read as a
      // placement to every caller that checks the flag.
      chain: sets.isEmpty
          ? null
          : ChainInfo(
              chainId: (_map(data['point'])['recovery_id'] ?? '').toString(),
              name: finding.trim().isEmpty
                  ? '$regionLabel placement'
                  : finding.trim(),
              movement: movementTest.trim(),
              directionalMode: _humanize(thermalMode),
            ),
      sets: sets,
      raw: data,
    );
  }

  static Map<String, dynamic> _normalisePad(Map<String, dynamic> pad) => {
        ...pad,
        'position_along_muscle': _firstNonEmpty([
              pad['position_along_muscle'],
              pad['position'],
            ]) ??
            '',
        'plane': _firstNonEmpty([pad['plane'], pad['aspect']]) ?? '',
        'side': _firstNonEmpty([pad['side'], pad['body_side']]) ?? '',
      };
}

// ── local helpers ────────────────────────────────────────────────────────────

Map<String, dynamic> _map(dynamic v) =>
    v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

List<String> _strings(dynamic v) => v is List
    ? v
        .map((e) => e?.toString().trim() ?? '')
        .where((s) => s.isNotEmpty)
        .toList()
    : const [];

int _int(dynamic v, int fallback) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v?.toString() ?? '') ?? fallback;
}

String? _firstNonEmpty(List<dynamic> values) {
  for (final v in values) {
    final s = v?.toString().trim() ?? '';
    if (s.isNotEmpty && s != 'null') return s;
  }
  return null;
}

/// `low-back` / `cold_pack` → `Low back` / `Cold pack`.
String _humanize(String key) {
  final s = key.replaceAll(RegExp(r'[-_]+'), ' ').trim();
  if (s.isEmpty) return '';
  return '${s[0].toUpperCase()}${s.substring(1)}';
}
