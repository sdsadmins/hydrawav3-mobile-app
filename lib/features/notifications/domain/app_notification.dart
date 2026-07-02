/// A user notification (Node `Notification` schema). The AI-report processor
/// creates one — `title: "AI Report Generated with <client>"`,
/// `message: "Your AI report has been generated successfully"`,
/// `data: { reportId }` — when a queued report finishes generating.
class AppNotification {
  final String id;
  final String title;
  final String message;

  /// 'info' | 'warning' | 'error' | 'success'.
  final String type;
  final bool read;

  /// The generated report id (from `data.reportId`), when present.
  final String? reportId;
  final DateTime? createdAt;

  const AppNotification({
    required this.id,
    required this.title,
    required this.message,
    this.type = 'info',
    this.read = false,
    this.reportId,
    this.createdAt,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    final data = json['data'];
    return AppNotification(
      id: (json['_id'] ?? json['id'] ?? '').toString(),
      title: (json['title'] ?? 'Notification').toString(),
      message: (json['message'] ?? '').toString(),
      type: (json['type'] ?? 'info').toString(),
      read: json['read'] == true,
      reportId: data is Map ? data['reportId']?.toString() : null,
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? ''),
    );
  }

  AppNotification copyWith({bool? read}) => AppNotification(
        id: id,
        title: title,
        message: message,
        type: type,
        read: read ?? this.read,
        reportId: reportId,
        createdAt: createdAt,
      );
}
