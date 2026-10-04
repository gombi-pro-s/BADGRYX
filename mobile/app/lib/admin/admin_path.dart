final RegExp _slugPattern = RegExp(r'^[a-z0-9-]{3,64}$');

/// Mirrors `admin/paths/actions.ts`'s shared `slugSchema`: lowercase
/// letters, digits, hyphens, 3-64 chars. The same regex gates learning
/// path, module, and lesson slugs on the web admin UI, so this one helper
/// covers all three levels here too.
bool isValidContentSlug(String slug) => _slugPattern.hasMatch(slug);

class AdminLearningPath {
  AdminLearningPath({
    required this.id,
    required this.slug,
    required this.title,
    required this.description,
    required this.published,
  });

  final String id;
  final String slug;
  final String title;
  final String? description;
  final bool published;

  factory AdminLearningPath.fromRow(Map<String, dynamic> row) {
    return AdminLearningPath(
      id: row['id'] as String,
      slug: row['slug'] as String,
      title: row['title'] as String,
      description: row['description'] as String?,
      published: row['published'] as bool,
    );
  }
}

/// The row shape used in a path's own module list -- mirrors
/// `[pathId]/page.tsx`'s module query. There is no "edit module" form on
/// the web admin UI (only create, publish toggle, and its own lessons), so
/// this model carries nothing more than what that page ever displays.
class AdminModuleSummary {
  AdminModuleSummary({required this.id, required this.title, required this.published});

  final String id;
  final String title;
  final bool published;

  factory AdminModuleSummary.fromRow(Map<String, dynamic> row) {
    return AdminModuleSummary(id: row['id'] as String, title: row['title'] as String, published: row['published'] as bool);
  }
}

/// The row shape used in a module's own lesson list -- mirrors
/// `[moduleId]/page.tsx`'s lesson query.
class AdminLessonSummary {
  AdminLessonSummary({required this.id, required this.title, required this.published});

  final String id;
  final String title;
  final bool published;

  factory AdminLessonSummary.fromRow(Map<String, dynamic> row) {
    return AdminLessonSummary(id: row['id'] as String, title: row['title'] as String, published: row['published'] as bool);
  }
}

class AdminLessonDetail {
  AdminLessonDetail({
    required this.id,
    required this.slug,
    required this.title,
    required this.summary,
    required this.contentMarkdown,
    required this.estimatedMinutes,
    required this.published,
  });

  final String id;
  final String slug;
  final String title;
  final String? summary;
  final String contentMarkdown;
  final int estimatedMinutes;
  final bool published;

  factory AdminLessonDetail.fromRow(Map<String, dynamic> row) {
    return AdminLessonDetail(
      id: row['id'] as String,
      slug: row['slug'] as String,
      title: row['title'] as String,
      summary: row['summary'] as String?,
      contentMarkdown: row['content_markdown'] as String,
      estimatedMinutes: row['estimated_minutes'] as int,
      published: row['published'] as bool,
    );
  }
}
