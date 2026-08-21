/// Models for the performance-protocols service — the `pad_protocols` corpus.
///
/// There are exactly two ways in to a pad set and both return the SAME payload
/// shape ([PadSetPayload]):
///   A. catalogue — disciplines → roles → chains → chain (only the last returns pads)
///   B. query / chat — `performance-query/query` and `performance-chat/message`
///
/// Sun and Moon are a pair per set — that pair *is* the placement. Sets render in
/// `set_index` order.
library;

/// A discipline row. The match key travels on the wire (`track`), the label goes
/// on screen ("Track & Field") — bind dropdown values to [discipline] or
/// matching breaks.
class Discipline {
  final String discipline;
  final String displayName;

  const Discipline({required this.discipline, this.displayName = ''});

  String get label => displayName.trim().isEmpty ? discipline : displayName;

  factory Discipline.fromJson(Map<String, dynamic> json) => Discipline(
        discipline: (json['discipline'] ?? json['id'] ?? '').toString(),
        displayName:
            (json['display_name'] ?? json['displayName'] ?? '').toString(),
      );

  /// Accepts `[{discipline, display_name}]` or a bare `["tennis", …]` — the
  /// service may author either, and a dropped list reads on screen as "this org
  /// has no disciplines", which is a very different (and wrong) message.
  static List<Discipline> listFrom(dynamic raw) {
    final out = <Discipline>[];
    for (final row in _rowsRaw(raw)) {
      if (row is String) {
        if (row.trim().isNotEmpty) out.add(Discipline(discipline: row.trim()));
      } else if (row is Map) {
        final d = Discipline.fromJson(Map<String, dynamic>.from(row));
        if (d.discipline.trim().isNotEmpty) out.add(d);
      }
    }
    return out;
  }
}

/// A position authored for a discipline. The service may return bare strings or
/// `{ role, display_name, subtype }` objects — both are accepted.
class RoleOption {
  final String role;
  final String displayName;
  final String? subtype;

  const RoleOption({required this.role, this.displayName = '', this.subtype});

  String get label => displayName.trim().isEmpty ? role : displayName;

  factory RoleOption.fromJson(Map<String, dynamic> json) => RoleOption(
        role: (json['role'] ?? json['name'] ?? json['position'] ?? '')
            .toString(),
        displayName:
            (json['display_name'] ?? json['displayName'] ?? '').toString(),
        subtype: _blankToNull(json['subtype']),
      );

  static List<RoleOption> listFrom(dynamic raw) {
    final out = <RoleOption>[];
    for (final row in _rowsRaw(raw)) {
      if (row is String) {
        if (row.trim().isNotEmpty) out.add(RoleOption(role: row));
      } else if (row is Map) {
        final r = RoleOption.fromJson(Map<String, dynamic>.from(row));
        if (r.role.trim().isNotEmpty) out.add(r);
      }
    }
    return out;
  }
}

/// One entry in the chain MENU for a position. This list is not ranked and
/// carries no scores — never label it "closest matches".
class ChainSummary {
  final String chainId;
  final String name;
  final String movement;
  final String? subtype;

  /// The chain's OWN discipline and role, present on `performance-chat`
  /// `options` rows (the catalogue's `/chains` rows omit them — the caller
  /// already asked for one discipline+role there, so they'd be redundant).
  ///
  /// A chat option list can span several roles at once ("cricket" alone offers
  /// Fast Bowler, Batsman and Fielder chains together), so a chain must be
  /// fetched with the role IT belongs to. Using the conversation's current role
  /// instead asks `/chain` for a Batsman chain under Fast Bowler, which is a
  /// combination the catalogue does not have.
  final String? discipline;
  final String? role;

  /// The discipline's display name (`Cricket`), when the row carries one.
  final String? displayName;

  const ChainSummary({
    required this.chainId,
    this.name = '',
    this.movement = '',
    this.subtype,
    this.discipline,
    this.role,
    this.displayName,
  });

  /// The chat rows already ship a fully-qualified label
  /// (`Cricket · Fast Bowler — Overhead shoulder chain`); prefer it, because a
  /// bare chain name repeats across roles and the chips become ambiguous.
  String get label {
    if (name.trim().isNotEmpty) return name;
    return chainId;
  }

  factory ChainSummary.fromJson(Map<String, dynamic> json) => ChainSummary(
        chainId: (json['chain_id'] ?? json['chainId'] ?? json['id'] ?? '')
            .toString(),
        name: (json['label'] ??
                json['name'] ??
                json['chain'] ??
                json['chain_name'] ??
                '')
            .toString(),
        movement: (json['movement'] ?? '').toString(),
        subtype: _blankToNull(json['subtype']),
        discipline: _blankToNull(json['discipline']),
        role: _blankToNull(json['role']),
        displayName: _blankToNull(json['display_name']),
      );

  static List<ChainSummary> listFrom(dynamic raw) {
    final out = <ChainSummary>[];
    for (final row in _rowsRaw(raw)) {
      if (row is String) {
        // A bare id list — the label falls back to the id until the service
        // sends names.
        if (row.trim().isNotEmpty) out.add(ChainSummary(chainId: row.trim()));
      } else if (row is Map) {
        final c = ChainSummary.fromJson(Map<String, dynamic>.from(row));
        if (c.chainId.trim().isNotEmpty) out.add(c);
      }
    }
    return out;
  }
}

/// The chain the pad set belongs to.
class ChainInfo {
  final String chainId;
  final String name;
  final String movement;
  final String directionalMode;
  final List<String> stressNodes;
  final List<String> injuryRiskReduction;
  final List<String> performanceRomBenefits;
  final Map<String, dynamic> retrieval;

  const ChainInfo({
    this.chainId = '',
    this.name = '',
    this.movement = '',
    this.directionalMode = '',
    this.stressNodes = const [],
    this.injuryRiskReduction = const [],
    this.performanceRomBenefits = const [],
    this.retrieval = const {},
  });

  factory ChainInfo.fromJson(Map<String, dynamic> json) => ChainInfo(
        chainId: (json['chain_id'] ?? json['chainId'] ?? '').toString(),
        name: (json['name'] ?? '').toString(),
        movement: (json['movement'] ?? '').toString(),
        directionalMode:
            (json['directional_mode'] ?? json['directionalMode'] ?? '')
                .toString(),
        stressNodes: _strings(json['stress_nodes'] ?? json['stressNodes']),
        injuryRiskReduction: _strings(
            json['injury_risk_reduction'] ?? json['injuryRiskReduction']),
        performanceRomBenefits: _strings(json['performance_rom_benefits'] ??
            json['performanceRomBenefits']),
        retrieval: json['retrieval'] is Map
            ? Map<String, dynamic>.from(json['retrieval'] as Map)
            : const {},
      );

  /// The `movement · directional_mode` subline used under the screen title.
  String get subline =>
      [movement, directionalMode].where((s) => s.trim().isNotEmpty).join(' · ');
}

/// One pad — half of a set. `sun` and `moon` share this shape.
class Pad {
  final String padLabel;
  final String side;
  final String plane;
  final String positionAlongMuscle;
  final String landmarkAnchor;
  final String stackPosition;
  final List<String> targetMuscles;
  final String? proxyFor;

  /// The engine's own flag that the user asked for this pad on BOTH sides
  /// ("Both" at intake) — web parity: `recoveryPadMarkers.js`'s `padSides()`
  /// ORs this into the side list regardless of any manual bilateral toggle,
  /// "so a bilateral REQUEST draws bilaterally on its own."
  final bool renderBothSides;

  const Pad({
    this.padLabel = '',
    this.side = '',
    this.plane = '',
    this.positionAlongMuscle = '',
    this.landmarkAnchor = '',
    this.stackPosition = '',
    this.targetMuscles = const [],
    this.proxyFor,
    this.renderBothSides = false,
  });

  factory Pad.fromJson(Map<String, dynamic> json) => Pad(
        padLabel: (json['pad_label'] ?? json['padLabel'] ?? '').toString(),
        side: (json['side'] ?? '').toString(),
        plane: (json['plane'] ?? '').toString(),
        positionAlongMuscle:
            (json['position_along_muscle'] ?? json['positionAlongMuscle'] ?? '')
                .toString(),
        landmarkAnchor:
            (json['landmark_anchor'] ?? json['landmarkAnchor'] ?? '')
                .toString(),
        stackPosition:
            (json['stack_position'] ?? json['stackPosition'] ?? '').toString(),
        targetMuscles:
            _strings(json['target_muscles'] ?? json['targetMuscles']),
        proxyFor: _blankToNull(json['proxy_for'] ?? json['proxyFor']),
        renderBothSides:
            json['render_both_sides'] == true || json['renderBothSides'] == true,
      );

  /// "left" / "right" normalised for the 3D viewer, or null when unsided.
  String? get sideKey {
    final s = side.toLowerCase();
    if (s.contains('left')) return 'left';
    if (s.contains('right')) return 'right';
    return null;
  }

  /// The written cue: everything the practitioner needs if 3D can't place it.
  String get cue {
    final parts = <String>[
      if (padLabel.trim().isNotEmpty) padLabel.trim(),
      if (landmarkAnchor.trim().isNotEmpty) landmarkAnchor.trim(),
    ];
    final detail = [plane, positionAlongMuscle]
        .where((s) => s.trim().isNotEmpty)
        .join(' · ');
    final head = parts.join(' — ');
    return detail.isEmpty ? head : '$head ($detail)';
  }
}

/// A Sun+Moon pair. `role` is generator / transfer / terminus.
class PadSet {
  final int setIndex;
  final String role;
  final String placementLabel;
  final String clinicalReasoning;
  final Pad? sun;
  final Pad? moon;

  /// Recovery's `pad_geometry` — `sandwich` / `wrap` / `side_by_side` /
  /// `diagonal` / `bracket`. HOW the pair sits relative to each other, which the
  /// pad list alone doesn't say. Empty for performance, which doesn't author it.
  final String padGeometry;

  /// A set the engine authored but did NOT apply this session, with the reason
  /// it was held back (`chain.conditional.withheld_sets[]` /
  /// `chain.referral.withheld_sets[]`). It has NO pads — the role doesn't apply
  /// to this presentation at all (e.g. a rom-followup set on a discomfort
  /// pathway) — and is shown so the practitioner can see the set exists and what
  /// would bring it in.
  final bool withheld;
  final String withheldReason;

  /// A set the engine authored WITH real pad geometry, but scheduled for a
  /// LATER session rather than this one (`chain.sequence_later[]`) — distinct
  /// from [withheld]: this set's role applies to the case, it's just next in
  /// the chain's sequence rather than applied now. Carries [sun]/[moon] like an
  /// applied set, so it can be listed with its full placement, just not drawn
  /// on the model this session.
  final bool deferred;

  /// `chain.sequence_later[].session_priority` / `chain.apply_now[].session_priority`
  /// — the order this set's role is applied in across the chain (1 = first).
  final int sessionPriority;

  const PadSet({
    this.setIndex = 1,
    this.role = '',
    this.placementLabel = '',
    this.clinicalReasoning = '',
    this.sun,
    this.moon,
    this.padGeometry = '',
    this.withheld = false,
    this.withheldReason = '',
    this.deferred = false,
    this.sessionPriority = 0,
  });

  factory PadSet.fromJson(Map<String, dynamic> json) => PadSet(
        setIndex: _int(json['set_index'] ?? json['setIndex'], 1),
        role: (json['role'] ?? '').toString(),
        placementLabel:
            (json['placement_label'] ?? json['placementLabel'] ?? '')
                .toString(),
        clinicalReasoning:
            (json['clinical_reasoning'] ?? json['clinicalReasoning'] ?? '')
                .toString(),
        sun: json['sun'] is Map
            ? Pad.fromJson(Map<String, dynamic>.from(json['sun'] as Map))
            : null,
        moon: json['moon'] is Map
            ? Pad.fromJson(Map<String, dynamic>.from(json['moon'] as Map))
            : null,
        padGeometry:
            (json['pad_geometry'] ?? json['padGeometry'] ?? '').toString(),
        withheld: _bool(json['withheld'], false),
        withheldReason: (json['withheld_reason'] ?? json['withheldReason'] ?? '')
            .toString(),
        deferred: _bool(json['deferred'], false),
        sessionPriority:
            _int(json['session_priority'] ?? json['sessionPriority'], 0),
      );

  /// Raw-index title. Prefer [PadSetPayload.titleOf], which prints the set
  /// number the way the surface it came from counts — performance authors
  /// `set_index` 0-based, so this getter alone labels its first set "Set 0".
  String get title => placementLabel.trim().isEmpty
      ? 'Set $setIndex'
      : 'Set $setIndex · $placementLabel';
}

/// Recovery's pad-geometry catalogue — the Flutter port of `PAD_GEOMETRY_INFO`
/// in Hydrawave3 `apps/web/src/anatomy/recoveryPadMarkers.js`, wording included.
///
/// The engine sends the key only, so the label, the one-word "reads" and the
/// intent all have to live client-side; they're the same strings the web shows.
class PadGeometryInfo {
  final String label;

  /// The one-word summary the web puts under the chip label.
  final String reads;
  final String intent;

  const PadGeometryInfo(this.label, this.reads, this.intent);

  static const Map<String, PadGeometryInfo> catalogue = {
    'sandwich': PadGeometryInfo(
      'Sandwich',
      'through',
      'Anterior and posterior facing each other, reaching a deep structure from both sides.',
    ),
    'wrap': PadGeometryInfo(
      'Wrap',
      'across',
      'Opposite sides of a joint, bracketing it.',
    ),
    'side_by_side': PadGeometryInfo(
      'Side by side',
      'along',
      'Both pads on one surface, along a muscle belly or border.',
    ),
    'diagonal': PadGeometryInfo(
      'Diagonal',
      'offset',
      'Offset pairing so contact holds on a curved surface.',
    ),
    'bracket': PadGeometryInfo(
      'Bracket',
      'around, not on',
      'Around a lymphatic node cluster or sensitive area, without direct pressure on it.',
    ),
  };

  /// Null for an unknown or absent key — the caller shows the raw key rather
  /// than inventing copy for a geometry we don't have wording for.
  static PadGeometryInfo? of(String key) =>
      catalogue[key.trim().toLowerCase()];
}

/// The pad-set payload — identical whether it came from the catalogue, a query,
/// or a chat turn.
///
/// A blocked request answers a refusal envelope with `chain: null` and no pads;
/// [isRefusal] is the only correct way to tell the two apart. Picking from the
/// catalogue is NOT a way around the gate.
class PadSetPayload {
  final String discipline;
  final String displayName;
  final String role;
  final String? subtype;
  final ChainInfo? chain;
  final List<PadSet> sets;
  final String? refusalMessage;
  final Map<String, dynamic> raw;

  /// Recovery's `session.guidance` — "Apply all 1 set this session. 1
  /// referral-link set is authored on this point and is not shown (set 2)…".
  /// The engine's own words about how many sets to run and why the rest aren't
  /// here; shown verbatim.
  final String guidance;

  /// Recovery's `session.sequencing_note`.
  final String sequencingNote;

  const PadSetPayload({
    this.discipline = '',
    this.displayName = '',
    this.role = '',
    this.subtype,
    this.chain,
    this.sets = const [],
    this.refusalMessage,
    this.raw = const {},
    this.guidance = '',
    this.sequencingNote = '',
  });

  /// Sets that will actually be applied THIS SESSION — the ones with pads
  /// drawn now. [sets] also carries deferred and withheld sets so they can be
  /// listed and explained.
  List<PadSet> get appliedSets =>
      sets.where((s) => !s.withheld && !s.deferred).toList();

  /// Authored WITH pads, but sequenced into a later session — not applied now,
  /// not excluded either. Distinct from [withheldSets], whose role doesn't
  /// apply to this case at all.
  List<PadSet> get deferredSets => sets.where((s) => s.deferred).toList();

  List<PadSet> get withheldSets => sets.where((s) => s.withheld).toList();

  /// A withheld or deferred set has no pads drawn this session, so neither can
  /// make a refusal into a placement — the test is whether anything is
  /// actually applied.
  bool get isRefusal => chain == null || appliedSets.isEmpty;

  /// One payload shape serves BOTH surfaces; the assistant tells them apart by
  /// this same field before it even opens the screen.
  bool get isRecovery => discipline.trim().toLowerCase() == 'recovery';

  /// The set number to PRINT for [set].
  ///
  /// The two corpora disagree on the origin: recovery authors `set_index`
  /// 1-based (1..5, per Rulebook A.1), performance authors it 0-based — its
  /// normalizer literally stores `parseInt(line) - 1` and the schema defaults to
  /// 0. Rendering the raw value therefore labelled the first performance set
  /// "Set 0". Shifting it in the model would be worse: the same number indexes
  /// the palette, the marker `setIndex` and the viewer's focus, so it has to
  /// stay 0-based everywhere except the label.
  int displayIndexOf(PadSet set) =>
      isRecovery ? set.setIndex : set.setIndex + 1;

  /// The 0-based index [set]'s MARKERS use — the same number that keys the
  /// palette (`setColorFor`), the 3D stage's per-set focus/arcs, and the pad
  /// lookup (`PadPlacementViewData.padOf`). Same normalization as
  /// [displayIndexOf], minus the +1 for the label. Callers that need to name
  /// or focus a set by its own identity (not its position in a filtered
  /// list — some sets can be withheld/deferred) should use this instead of a
  /// loop index, or the set's number and its markers/colour disagree.
  int markerIndexOf(PadSet set) => isRecovery ? set.setIndex - 1 : set.setIndex;

  /// [PadSet.title] with the printable set number.
  String titleOf(PadSet set) => set.placementLabel.trim().isEmpty
      ? 'Set ${displayIndexOf(set)}'
      : 'Set ${displayIndexOf(set)} · ${set.placementLabel}';

  String get disciplineLabel =>
      displayName.trim().isEmpty ? discipline : displayName;

  /// "Tennis · Singles Player" — the placement-card subtitle.
  String get contextLine => [disciplineLabel, role]
      .where((s) => s.trim().isNotEmpty)
      .join(' · ');

  factory PadSetPayload.fromJson(Map<String, dynamic> json) {
    final data = (json['data'] is Map)
        ? Map<String, dynamic>.from(json['data'] as Map)
        : json;
    final rawSets = data['sets'];
    final sets = rawSets is List
        ? (rawSets
            .whereType<Map>()
            .map((e) => PadSet.fromJson(Map<String, dynamic>.from(e)))
            .toList()
          ..sort((a, b) => a.setIndex.compareTo(b.setIndex)))
        : <PadSet>[];
    return PadSetPayload(
      discipline: (data['discipline'] ?? '').toString(),
      displayName:
          (data['display_name'] ?? data['displayName'] ?? '').toString(),
      role: (data['role'] ?? '').toString(),
      subtype: _blankToNull(data['subtype']),
      chain: data['chain'] is Map
          ? ChainInfo.fromJson(Map<String, dynamic>.from(data['chain'] as Map))
          : null,
      sets: sets,
      refusalMessage: refusalMessageFrom(data),
      raw: data,
    );
  }

  /// The refusal text, whichever key the envelope used. Kept permissive on
  /// purpose — the exact field isn't pinned down yet.
  static String? refusalMessageFrom(Map<String, dynamic> json) {
    for (final key in const [
      'refusal',
      'message',
      'reply',
      'reason',
      'safety_message',
      'safetyMessage',
    ]) {
      final v = json[key];
      if (v is String && v.trim().isNotEmpty) return v.trim();
      if (v is Map) {
        final nested = refusalMessageFrom(Map<String, dynamic>.from(v));
        if (nested != null) return nested;
      }
    }
    return null;
  }
}

/// One ranked hit from `performance-query/query` — chains WITH their pads, so a
/// tap needs no second call. These do carry scores, so "best matches" is honest
/// language here (unlike the catalogue menu).
class RankedChain {
  final double? score;
  final PadSetPayload payload;

  const RankedChain({this.score, required this.payload});

  factory RankedChain.fromJson(Map<String, dynamic> json) => RankedChain(
        score: _double(json['score'] ?? json['similarity'] ?? json['rank']),
        payload: PadSetPayload.fromJson(json),
      );

  static List<RankedChain> listFrom(dynamic raw) => _rows(raw)
      .map(RankedChain.fromJson)
      .where((r) => !r.payload.isRefusal)
      .toList();
}

/// A `performance-chat/message` reply. `render`/`results` are the query
/// service's output verbatim, so the same pad UI renders both paths.
class ChatReply {
  final String reply;
  final String intent;
  final Map<String, dynamic> slots;
  final List<String> needs;

  /// The full catalogue for the resolved role — a MENU, not near-answers.
  final List<ChainSummary> options;
  final List<RankedChain> results;
  final Map<String, dynamic> render;
  final List<String> sources;
  final Map<String, dynamic> raw;

  const ChatReply({
    this.reply = '',
    this.intent = '',
    this.slots = const {},
    this.needs = const [],
    this.options = const [],
    this.results = const [],
    this.render = const {},
    this.sources = const [],
    this.raw = const {},
  });

  bool get hasPads => results.isNotEmpty;

  factory ChatReply.fromJson(Map<String, dynamic> json) {
    final data = (json['data'] is Map)
        ? Map<String, dynamic>.from(json['data'] as Map)
        : json;
    return ChatReply(
      reply: (data['reply'] ?? data['message'] ?? '').toString(),
      intent: (data['intent'] ?? '').toString(),
      slots: data['slots'] is Map
          ? Map<String, dynamic>.from(data['slots'] as Map)
          : const {},
      needs: _strings(data['needs']),
      options: ChainSummary.listFrom(data['options']),
      results: RankedChain.listFrom(data['results']),
      render: data['render'] is Map
          ? Map<String, dynamic>.from(data['render'] as Map)
          : const {},
      sources: _strings(data['sources']),
      raw: data,
    );
  }
}

// ── shared parsing helpers ───────────────────────────────────────────────────

const _kListKeys = [
  'data',
  'items',
  'results',
  'disciplines',
  'roles',
  'chains',
  'options',
];

/// Finds the row list inside `[…]`, `{data: […]}`, or `{data: {chains: […]}}`.
/// Returns **null** when the payload holds no list at all — the caller must not
/// confuse that with an empty list. A dev tunnel serving an HTML interstitial,
/// or a renamed field, both land here, and "no disciplines are authored" is the
/// wrong thing to tell someone in that case.
List<dynamic>? rowsOrNull(dynamic raw, {int depth = 0}) {
  if (raw is List) return raw;
  if (raw is Map && depth < 3) {
    for (final key in _kListKeys) {
      final v = raw[key];
      if (v is List) return v;
      if (v is Map) {
        final nested = rowsOrNull(v, depth: depth + 1);
        if (nested != null) return nested;
      }
    }
  }
  return null;
}

List<dynamic> _rowsRaw(dynamic raw) => rowsOrNull(raw) ?? const [];

List<Map<String, dynamic>> _rows(dynamic raw) => _rowsRaw(raw)
    .whereType<Map>()
    .map((e) => Map<String, dynamic>.from(e))
    .toList();

List<String> _strings(dynamic raw) {
  if (raw is List) {
    return raw
        .map((e) => e is Map
            ? (e['name'] ?? e['muscle'] ?? e['label'] ?? '').toString()
            : e.toString())
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }
  if (raw is String && raw.trim().isNotEmpty) return [raw.trim()];
  return const [];
}

String? _blankToNull(dynamic v) {
  final s = v?.toString().trim();
  return (s == null || s.isEmpty || s == 'null') ? null : s;
}

bool _bool(dynamic v, bool fallback) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  final s = v?.toString().trim().toLowerCase();
  if (s == 'true') return true;
  if (s == 'false') return false;
  return fallback;
}

int _int(dynamic v, int fallback) =>
    v is int ? v : int.tryParse(v?.toString() ?? '') ?? fallback;

double? _double(dynamic v) =>
    v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '');
