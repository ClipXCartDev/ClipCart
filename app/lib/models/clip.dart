class Clip {
  Clip({
    required this.id,
    required this.title,
    required this.slug,
    this.editorName,
    this.category,
    this.movieName,
    this.genre,
    required this.language,
    required this.access,
    required this.durationSec,
    required this.downloads,
    required this.layers,
  });

  final String id;
  final String title;
  final String slug;
  final String? editorName;
  final String? category;
  final String? movieName;
  final String? genre;
  final String language;
  final String access; // free | pro
  final int? durationSec;
  final int downloads;
  final List<String> layers;

  bool get isPro => access == 'pro';

  String get durationLabel {
    final s = durationSec ?? 0;
    return '${(s ~/ 60).toString().padLeft(1, '0')}:${(s % 60).toString().padLeft(2, '0')}';
  }

  factory Clip.fromJson(Map<String, dynamic> j) => Clip(
        id: j['id'] as String,
        title: j['title'] as String,
        slug: j['slug'] as String,
        editorName: j['editor_name'] as String?,
        category: j['category'] as String?,
        movieName: j['movie_name'] as String?,
        genre: j['genre'] as String?,
        language: (j['language'] ?? 'English') as String,
        access: (j['access'] ?? 'free') as String,
        durationSec: j['duration_sec'] as int?,
        downloads: (j['downloads'] ?? 0) as int,
        layers: ((j['layers'] ?? []) as List).map((e) => e.toString()).toList(),
      );
}
