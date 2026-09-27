class Lab {
  Lab({
    required this.id,
    required this.title,
    this.description,
    required this.category,
    required this.difficulty,
    required this.points,
    required this.hasTerminal,
  });

  final String id;
  final String title;
  final String? description;
  final String category;
  final String difficulty;
  final int points;
  final bool hasTerminal;

  factory Lab.fromRow(Map<String, dynamic> row) {
    return Lab(
      id: row['id'] as String,
      title: row['title'] as String,
      description: row['description'] as String?,
      category: row['category'] as String,
      difficulty: row['difficulty'] as String,
      points: row['points'] as int,
      hasTerminal: row['has_terminal'] as bool,
    );
  }
}

class LabHint {
  LabHint({required this.id, required this.level, required this.pointCost});

  final String id;
  final int level;
  final int pointCost;

  factory LabHint.fromRow(Map<String, dynamic> row) {
    return LabHint(id: row['id'] as String, level: row['level'] as int, pointCost: row['point_cost'] as int);
  }
}

class LabInstance {
  LabInstance({required this.id, required this.guided, required this.status});

  final String id;
  final bool guided;
  final String status;

  factory LabInstance.fromRow(Map<String, dynamic> row) {
    return LabInstance(id: row['id'] as String, guided: row['guided'] as bool, status: row['status'] as String);
  }
}

/// The real submit_lab_flag() RPC returns a full lab_submissions row --
/// only `correct` is ever rendered, same as apps/web's lab-workspace.tsx.
bool submissionCorrect(Map<String, dynamic> row) => row['correct'] as bool;
