/// The `recovery-chat/message` envelope.
///
/// Deliberately NOT the performance `ChatReply`. The two chatbots share a shape
/// but not a meaning: performance answers with ranked protocol chains, recovery
/// answers with ONE documented recovery point, and its `needs` is a single field
/// name (`"region"`) rather than a list. Folding them into one model would make
/// every read site guess which surface it was looking at.
class RecoveryChatReply {
  /// The whole answer, already phrased server-side — header, wellness line, the
  /// Sun/Moon pad lines, the thermal note and the citation. Render it verbatim;
  /// the backend deliberately owns this wording (an LLM may only rephrase the
  /// non-claim prose, and only after passing its own guard).
  final String reply;

  /// `answer` · `safety` · `scope` · `decline` · `disambiguate` · `no_match`.
  final String kind;

  /// Multi-turn memory — `{goal, region, side, symptom_quality, acuity, …}`.
  /// Thread it back on the NEXT turn or the conversation forgets the area.
  final Map<String, dynamic> slots;

  /// The one slot still missing (`region` / `side`), or null when nothing is.
  final String? needs;

  /// Disambiguation chips for [needs] — one question, never an interrogation.
  final List<RecoveryChip> options;

  /// `{recovery_id, chunkIds, sets}` when a placement was resolved, else empty.
  /// Note this carries `sets`, NOT the `markers` the 3D viewer wants, so a chat
  /// answer can't feed `PadPlacement3DScreen` the way `placement-session` does.
  final Map<String, dynamic> render;

  /// `Source: rec-… · region · pathway · version · date`.
  final String? citation;
  final Map<String, dynamic> safety;
  final String pathway;
  final Map<String, dynamic> raw;

  const RecoveryChatReply({
    this.reply = '',
    this.kind = '',
    this.slots = const {},
    this.needs,
    this.options = const [],
    this.render = const {},
    this.citation,
    this.safety = const {},
    this.pathway = '',
    this.raw = const {},
  });

  /// A real placement came back. The gate empties `render` on a refusal rather
  /// than omitting it, so this is also the "not blocked" test.
  bool get hasPlacement => render['recovery_id'] != null;

  /// The safety gate stopped this turn — show [reply] and nothing else.
  bool get isRefusal =>
      safety['blocked'] == true || kind == 'safety' || kind == 'scope';

  factory RecoveryChatReply.fromJson(Map<String, dynamic> json) {
    final data = (json['data'] is Map)
        ? Map<String, dynamic>.from(json['data'] as Map)
        : json;
    final needs = data['needs'];
    return RecoveryChatReply(
      reply: (data['reply'] ?? data['message'] ?? '').toString(),
      kind: (data['kind'] ?? '').toString(),
      slots: _map(data['slots']),
      needs: needs is String && needs.trim().isNotEmpty ? needs.trim() : null,
      options: RecoveryChip.listFrom(data['options']),
      render: _map(data['render']),
      citation: data['citation']?.toString(),
      safety: _map(data['safety']),
      pathway: (data['pathway'] ?? '').toString(),
      raw: data,
    );
  }

  static Map<String, dynamic> _map(dynamic v) =>
      v is Map ? Map<String, dynamic>.from(v) : const {};
}

/// One disambiguation chip. `kind` says which slot the tap fills, so the answer
/// goes back as an exact slot value instead of being re-parsed out of the label
/// ("low back" → `low-back` is a round trip the client shouldn't have to guess).
class RecoveryChip {
  final String kind;
  final String label;
  final String? region;
  final String? side;
  final String? hub;
  final String? referral;

  const RecoveryChip({
    required this.kind,
    required this.label,
    this.region,
    this.side,
    this.hub,
    this.referral,
  });

  /// The slot patch this chip stands for, merged into `slots` on the next turn.
  Map<String, dynamic> get slotPatch => {
        if (region != null) 'region': region,
        if (side != null) 'side': side,
        if (hub != null) 'lymphatic_hub': hub,
        if (referral != null) 'referralTarget': referral,
      };

  factory RecoveryChip.fromJson(Map<String, dynamic> json) {
    String? str(String key) {
      final v = json[key];
      final s = v?.toString().trim() ?? '';
      return s.isEmpty ? null : s;
    }

    return RecoveryChip(
      kind: (json['kind'] ?? '').toString(),
      label: (json['label'] ?? json['region'] ?? json['side'] ?? '').toString(),
      region: str('region'),
      side: str('side'),
      hub: str('hub'),
      referral: str('referral'),
    );
  }

  static List<RecoveryChip> listFrom(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => RecoveryChip.fromJson(Map<String, dynamic>.from(e)))
        .where((c) => c.label.trim().isNotEmpty)
        .toList();
  }
}
