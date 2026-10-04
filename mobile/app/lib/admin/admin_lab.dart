final RegExp _slugPattern = RegExp(r'^[a-z0-9-]{3,64}$');

/// Mirrors `admin/labs/actions.ts`'s `labSchema` slug rule -- the same
/// regex every other admin CMS slug field in this app enforces.
bool isValidLabSlug(String slug) => _slugPattern.hasMatch(slug);

class AdminLab {
  AdminLab({
    required this.id,
    required this.slug,
    required this.title,
    required this.description,
    required this.category,
    required this.difficulty,
    required this.estimatedMinutes,
    required this.points,
    required this.published,
  });

  final String id;
  final String slug;
  final String title;
  final String? description;
  final String category;
  final String difficulty;
  final int estimatedMinutes;
  final int points;
  final bool published;

  factory AdminLab.fromRow(Map<String, dynamic> row) {
    return AdminLab(
      id: row['id'] as String,
      slug: row['slug'] as String,
      title: row['title'] as String,
      description: row['description'] as String?,
      category: row['category'] as String,
      difficulty: row['difficulty'] as String,
      estimatedMinutes: row['estimated_minutes'] as int,
      points: row['points'] as int,
      published: row['published'] as bool,
    );
  }
}

class AdminLabHint {
  AdminLabHint({required this.id, required this.level, required this.content, required this.pointCost});

  final String id;
  final int level;
  final String content;
  final int pointCost;

  factory AdminLabHint.fromRow(Map<String, dynamic> row) {
    return AdminLabHint(
      id: row['id'] as String,
      level: row['level'] as int,
      content: row['content'] as String,
      pointCost: row['point_cost'] as int,
    );
  }
}

class AdminLabFlag {
  AdminLabFlag({required this.id, required this.label, required this.variantSeed});

  final String id;
  final String label;
  final int variantSeed;

  factory AdminLabFlag.fromRow(Map<String, dynamic> row) {
    return AdminLabFlag(id: row['id'] as String, label: row['label'] as String, variantSeed: row['variant_seed'] as int);
  }
}
