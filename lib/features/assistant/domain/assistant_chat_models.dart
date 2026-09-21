/// The unified `POST /chat` envelope — the ONE assistant route on the Node
/// backend (`src/modules/pad-chat`), which routes each turn between a knowledge
/// lane, a placement lane and a performance lane and grounds the answer against
/// the retrieved corpus.
///
/// Deliberately NOT the performance `ChatReply` or the `RecoveryChatReply`: this
/// surface returns already-phrased prose plus a flat list of follow-up [chips],
/// and carries no catalogue `options`, ranked pad `results` or pad-map payload.
/// Only the typed free-text path in the Assistant uses it; every chip-driven
/// flow (mode buttons, catalogue pickers, pad map) still talks to the older
/// `performance-chat/message` / `recovery-chat/message` endpoints.
class AssistantChatReply {
  /// Server decided this turn succeeded. A gate block comes back `ok: false`
  /// with `kind: "refusal"`.
  final bool ok;

  /// Which lane answered — `knowledge` · `placement` · `performance` ·
  /// `recovery`. Informational; the client renders every lane the same way.
  final String lane;

  /// `answer` · `refusal` · `question` · … — [isRefusal] is the only branch the
  /// UI takes on it.
  final String kind;

  /// The whole answer, phrased server-side (by the model when one is wired, by
  /// the deterministic presenter otherwise). Rendered verbatim.
  final String reply;

  /// Tappable follow-ups. Tapping one sends its [AssistantChip.label] back as
  /// the next turn, carrying [threadId], so the conversation continues.
  final List<AssistantChip> chips;

  /// Echoed back so a multi-turn conversation stays on one session server-side.
  final String sessionId;

  /// The conversation's accumulated slot memory AS THE SERVER NOW HOLDS IT. The
  /// client does not merge into this — it REPLACES its copy with whatever comes
  /// back and sends it verbatim on the next turn (web parity:
  /// `if (reply.slots) setSlots(reply.slots)`). This is how "cricket" →
  /// `perfAccept` → `perfChain` walks the performance flow to a placement.
  final Map<String, dynamic> slots;

  /// The handle for THIS conversation. Thread it back on every following turn or
  /// the backend starts a new one.
  final String? threadId;

  /// Retrieved passages that backed the answer, when the lane disclosed any.
  final List<AssistantSource> sources;

  final Map<String, dynamic> raw;

  const AssistantChatReply({
    this.ok = true,
    this.lane = '',
    this.kind = '',
    this.reply = '',
    this.chips = const [],
    this.sessionId = '',
    this.slots = const {},
    this.threadId,
    this.sources = const [],
    this.raw = const {},
  });

  /// The safety gate (or a lane refusal) stopped this turn — show [reply] and
  /// offer a way onward, never a placement.
  bool get isRefusal => ok == false || kind == 'refusal';

  factory AssistantChatReply.fromJson(Map<String, dynamic> json) {
    final data = (json['data'] is Map)
        ? Map<String, dynamic>.from(json['data'] as Map)
        : json;
    final threadId = (data['threadId'] ?? '').toString().trim();
    return AssistantChatReply(
      ok: data['ok'] != false,
      lane: (data['lane'] ?? '').toString(),
      kind: (data['kind'] ?? '').toString(),
      reply: (data['reply'] ?? data['message'] ?? '').toString(),
      chips: AssistantChip.listFrom(data['chips']),
      sessionId: (data['sessionId'] ?? '').toString(),
      slots: (data['slots'] is Map)
          ? Map<String, dynamic>.from(data['slots'] as Map)
          : const {},
      threadId: threadId.isEmpty ? null : threadId,
      sources: AssistantSource.listFrom(data['sources']),
      raw: data,
    );
  }
}

/// One follow-up chip from the assistant. `lane` / `slot` are what the web
/// surface uses to route the tap into its own flow; this client does not have
/// that flow, so it just replays [label] as the next message.
class AssistantChip {
  final String id;
  final String label;
  final String lane;

  /// Single-slot chip: `slot` is the key, [value] the value to write. Tapping
  /// sends `{...currentSlots, slot: value}` (web parity: `answerChip`).
  final String? slot;
  final dynamic value;

  /// A chip that confirms MORE THAN ONE slot at once — merged over the current
  /// slots ahead of [slot]/[value]. Empty for the common single-slot chip.
  final Map<String, dynamic> slots;

  /// The server's hint that this is the expected next answer (`likely: true`) —
  /// rendered as a "hot" chip.
  final bool likely;

  const AssistantChip({
    required this.label,
    this.id = '',
    this.lane = '',
    this.slot,
    this.value,
    this.slots = const {},
    this.likely = false,
  });

  factory AssistantChip.fromJson(Map<String, dynamic> json) {
    final slot = (json['slot'] ?? '').toString().trim();
    return AssistantChip(
      id: (json['id'] ?? '').toString(),
      label: (json['label'] ?? json['text'] ?? '').toString(),
      lane: (json['lane'] ?? '').toString(),
      slot: slot.isEmpty ? null : slot,
      value: json['value'],
      slots: (json['slots'] is Map)
          ? Map<String, dynamic>.from(json['slots'] as Map)
          : const {},
      likely: json['likely'] == true,
    );
  }

  /// The slot payload to send when this chip is tapped, given the conversation's
  /// [current] slots. Mirrors the web `answerChip`: a multi-slot chip merges its
  /// `slots`; a single-slot chip writes `slot: value`; a plain chip carries the
  /// current slots unchanged.
  Map<String, dynamic> nextSlots(Map<String, dynamic> current) {
    if (slots.isNotEmpty) return {...current, ...slots};
    // A chip with a `slot` but no `value` is a QUESTION chip ("Where is the
    // discomfort?") — the user answers it by typing next. Web sends
    // `{[slot]: undefined}`, which JSON drops, so it is effectively the current
    // slots unchanged; match that rather than writing an explicit null.
    if ((slot ?? '').isNotEmpty && value != null) {
      return {...current, slot!: value};
    }
    return current;
  }

  static List<AssistantChip> listFrom(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => AssistantChip.fromJson(Map<String, dynamic>.from(e)))
        .where((c) => c.label.trim().isNotEmpty)
        .toList();
  }
}

/// A retrieved passage the answer cited. Shown, when present, as a compact
/// "Source: …" line under the reply.
class AssistantSource {
  final String title;
  final String source;

  const AssistantSource({this.title = '', this.source = ''});

  String get display => title.trim().isNotEmpty ? title.trim() : source.trim();

  factory AssistantSource.fromJson(Map<String, dynamic> json) => AssistantSource(
        title: (json['title'] ?? json['heading'] ?? '').toString(),
        source: (json['source'] ?? json['sourceName'] ?? '').toString(),
      );

  static List<AssistantSource> listFrom(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => AssistantSource.fromJson(Map<String, dynamic>.from(e)))
        .where((s) => s.display.isNotEmpty)
        .toList();
  }
}
