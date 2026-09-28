class MemberStats {
  MemberStats({
    required this.userId,
    required this.name,
    required this.role,
    required this.masteredOrDemonstrated,
    required this.inProgress,
    required this.labsCompleted,
    required this.quizzesPassed,
    required this.ctfSolved,
    required this.investigationsPassed,
  });

  final String userId;
  final String name;
  final String role;
  final int masteredOrDemonstrated;
  final int inProgress;
  final int labsCompleted;
  final int quizzesPassed;
  final int ctfSolved;
  final int investigationsPassed;
}

/// Mirrors orgs/[orgId]/dashboard/page.tsx's PROVEN_STATES/IN_PROGRESS_STATES.
const List<String> provenSkillStates = ['DEMONSTRATED', 'MASTERED'];
const List<String> inProgressSkillStates = ['LEARNING', 'PRACTICING', 'ASSESSED'];

/// Mirrors orgs/[orgId]/dashboard/page.tsx's inline `stats` map exactly:
/// one row per member, each stat a plain filter+count over the matching
/// rows already fetched (RLS already scoped every one of those queries to
/// exactly this org's members, for an instructor/team_owner/org_admin
/// caller -- these counts add no visibility of their own).
List<MemberStats> computeMemberStats({
  required List<Map<String, dynamic>> members,
  required List<Map<String, dynamic>> profiles,
  required List<Map<String, dynamic>> skillStates,
  required List<Map<String, dynamic>> labProgress,
  required List<Map<String, dynamic>> quizAttempts,
  required List<Map<String, dynamic>> ctfSubmissions,
  required List<Map<String, dynamic>> investigationSubmissions,
}) {
  final profileByUserId = <String, Map<String, dynamic>>{for (final p in profiles) p['id'] as String: p};

  return members.map((m) {
    final userId = m['user_id'] as String;
    final profile = profileByUserId[userId];
    final name = (profile?['display_name'] as String?) ?? (profile?['username'] as String?) ?? userId;
    final myStates = skillStates.where((s) => s['user_id'] == userId);

    return MemberStats(
      userId: userId,
      name: name,
      role: m['role'] as String,
      masteredOrDemonstrated: myStates.where((s) => provenSkillStates.contains(s['state'])).length,
      inProgress: myStates.where((s) => inProgressSkillStates.contains(s['state'])).length,
      labsCompleted: labProgress.where((l) => l['user_id'] == userId && l['status'] == 'completed').length,
      quizzesPassed: quizAttempts.where((q) => q['user_id'] == userId && q['passed'] == true).length,
      ctfSolved: ctfSubmissions.where((c) => c['user_id'] == userId && c['correct'] == true).length,
      investigationsPassed: investigationSubmissions.where((i) => i['user_id'] == userId && i['passed'] == true).length,
    );
  }).toList();
}
