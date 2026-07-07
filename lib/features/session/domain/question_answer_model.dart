/// A single post-session question and the practitioner/client's free-text
/// answer, logged per protocol (web parity: `questionAnswers: [{question,
/// answer}]` inside each `protocols[]` entry of the `/intake` body).
class QuestionAnswer {
  final String question;
  final String answer;

  /// The rank (1–5) of the selected preset answer option, REQUIRED by the
  /// backend `ProtocolQuestionAnswerDto`. 0 for a free-text answer with no
  /// matching preset (web parity: `rank: matched?.rank || 0`).
  final int rank;

  const QuestionAnswer({
    required this.question,
    required this.answer,
    this.rank = 0,
  });

  /// Shape accepted by the backend `CreateIntakeDto.protocols[].questionAnswers`
  /// (`{question, answer, rank}` — rank is required).
  Map<String, dynamic> toIntakeJson() => {
        'question': question,
        'answer': answer,
        'rank': rank,
      };

  Map<String, dynamic> toJson() => {
        'question': question,
        'answer': answer,
        'rank': rank,
      };

  factory QuestionAnswer.fromJson(Map<String, dynamic> json) => QuestionAnswer(
        question: (json['question'] ?? '').toString(),
        answer: (json['answer'] ?? '').toString(),
        rank: (json['rank'] as num?)?.toInt() ?? 0,
      );
}

/// The result returned by the post-session outcomes sheet: per-protocol
/// answers plus the session-level pain rating and notes.
class PostSessionOutcomes {
  /// Protocol name -> its answered questions (only non-empty answers kept).
  final Map<String, List<QuestionAnswer>> answersByProtocol;

  /// Per-area post-session discomfort (0–10), keyed by the index into the
  /// intake's discomfort areas (→ each `discomfortAreas[].discomfortAfter`).
  /// Empty when no area slider was touched.
  final Map<int, int> discomfortAfterByArea;

  /// Practitioner notes (→ `sessionNotes`).
  final String? notes;

  const PostSessionOutcomes({
    this.answersByProtocol = const {},
    this.discomfortAfterByArea = const {},
    this.notes,
  });

  /// True when the user submitted nothing meaningful (no answers, no pain
  /// recorded, no notes).
  bool get isEmpty =>
      answersByProtocol.values.every((l) => l.isEmpty) &&
      discomfortAfterByArea.isEmpty &&
      (notes == null || notes!.trim().isEmpty);

  Map<String, dynamic> toJson() => {
        'answersByProtocol': answersByProtocol.map(
          (k, v) => MapEntry(k, v.map((qa) => qa.toJson()).toList()),
        ),
        'discomfortAfterByArea': discomfortAfterByArea.map(
          (k, v) => MapEntry(k.toString(), v),
        ),
        if (notes != null) 'notes': notes,
      };

  factory PostSessionOutcomes.fromJson(Map<String, dynamic> json) {
    final raw = json['answersByProtocol'];
    final map = <String, List<QuestionAnswer>>{};
    if (raw is Map) {
      raw.forEach((key, value) {
        if (value is List) {
          map[key.toString()] = value
              .whereType<Map>()
              .map((e) =>
                  QuestionAnswer.fromJson(Map<String, dynamic>.from(e)))
              .toList();
        }
      });
    }
    final area = <int, int>{};
    final rawArea = json['discomfortAfterByArea'];
    if (rawArea is Map) {
      rawArea.forEach((k, v) {
        final i = int.tryParse(k.toString());
        final val = (v as num?)?.toInt();
        if (i != null && val != null) area[i] = val;
      });
    }
    return PostSessionOutcomes(
      answersByProtocol: map,
      discomfortAfterByArea: area,
      notes: json['notes']?.toString(),
    );
  }
}
