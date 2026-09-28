import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'instructor_dashboard.dart';
import 'organization.dart';

/// Mirrors orgs/[orgId]/dashboard/page.tsx's queries exactly -- every one
/// RLS-scoped to the caller's own instructor/team_owner/org_admin session
/// (see 20260922000012_org_instructor_visibility_and_invitations.sql),
/// same visibility boundary as the web page, not a new one.
Future<(Organization, List<MemberStats>)> fetchInstructorDashboard(SupabaseClient client, String organizationId) async {
  final orgRow = await client.from('organizations').select('id, slug, name').eq('id', organizationId).single();
  final organization = Organization.fromRow(orgRow);

  final memberRows = await client
      .from('organization_members')
      .select('user_id, role')
      .eq('organization_id', organizationId)
      .order('joined_at');
  final members = (memberRows as List).cast<Map<String, dynamic>>();
  if (members.isEmpty) return (organization, const <MemberStats>[]);

  final memberIds = members.map((m) => m['user_id'] as String).toList();

  final profileRows = await client.from('profiles').select('id, display_name, username').inFilter('id', memberIds);
  final skillStateRows = await client.from('user_skill_states').select('user_id, state').inFilter('user_id', memberIds);
  final labProgressRows = await client.from('lab_progress').select('user_id, status').inFilter('user_id', memberIds);
  final quizAttemptRows = await client.from('quiz_attempts').select('user_id, passed').inFilter('user_id', memberIds);
  final ctfSubmissionRows = await client.from('ctf_submissions').select('user_id, correct').inFilter('user_id', memberIds);
  final investigationSubmissionRows = await client
      .from('investigation_submissions')
      .select('user_id, passed')
      .inFilter('user_id', memberIds);

  final stats = computeMemberStats(
    members: members,
    profiles: (profileRows as List).cast<Map<String, dynamic>>(),
    skillStates: (skillStateRows as List).cast<Map<String, dynamic>>(),
    labProgress: (labProgressRows as List).cast<Map<String, dynamic>>(),
    quizAttempts: (quizAttemptRows as List).cast<Map<String, dynamic>>(),
    ctfSubmissions: (ctfSubmissionRows as List).cast<Map<String, dynamic>>(),
    investigationSubmissions: (investigationSubmissionRows as List).cast<Map<String, dynamic>>(),
  );

  return (organization, stats);
}

/// Real graded results for every member -- skill states, lab completions,
/// quiz/CTF/investigation outcomes. Nothing here is self-reported, same
/// claim the web page makes. A per-member card list rather than the web's
/// wide table, since a phone has no room for an 8-column table.
class InstructorDashboardScreen extends StatefulWidget {
  const InstructorDashboardScreen({super.key, required this.organizationId});

  final String organizationId;

  @override
  State<InstructorDashboardScreen> createState() => _InstructorDashboardScreenState();
}

class _InstructorDashboardScreenState extends State<InstructorDashboardScreen> {
  late Future<(Organization, List<MemberStats>)> _future;

  @override
  void initState() {
    super.initState();
    _future = fetchInstructorDashboard(Supabase.instance.client, widget.organizationId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Instructor dashboard')),
      body: FutureBuilder<(Organization, List<MemberStats>)>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return Center(child: Text('Could not load this dashboard: ${snapshot.error}'));
          }
          final (organization, stats) = snapshot.data!;
          if (stats.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('No members yet in ${organization.name}.'),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Real graded results for every member of ${organization.name} -- skill states, lab completions, '
                'quiz/CTF/investigation outcomes. Nothing here is self-reported.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              ...stats.map(
                (member) => Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(member.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                            Text(formatOrgRole(member.role), style: Theme.of(context).textTheme.bodySmall),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 16,
                          runSpacing: 4,
                          children: [
                            _Stat('Skills proven', member.masteredOrDemonstrated),
                            _Stat('In progress', member.inProgress),
                            _Stat('Labs', member.labsCompleted),
                            _Stat('Quizzes', member.quizzesPassed),
                            _Stat('CTF', member.ctfSolved),
                            _Stat('Investigations', member.investigationsPassed),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value);

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$value', style: Theme.of(context).textTheme.titleMedium),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
