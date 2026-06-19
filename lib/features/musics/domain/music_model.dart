/// A session "Atmosphere" music track. Sourced from the backend `/musics`
/// collection — `music` is a public S3 https URL the player streams + loops.
class Music {
  final String id;
  final String name;
  final String url;

  const Music({
    required this.id,
    required this.name,
    required this.url,
  });

  factory Music.fromJson(Map<String, dynamic> json) => Music(
        id: json['_id']?.toString() ?? json['id']?.toString() ?? '',
        name: json['name'] as String? ?? 'Untitled',
        url: json['music'] as String? ?? json['url'] as String? ?? '',
      );

  /// A track is only usable if it carries a playable URL.
  bool get isPlayable => url.isNotEmpty;
}
