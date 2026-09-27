import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'skill_state.dart';

class SkillRow {
  SkillRow({required this.id, required this.name, required this.categoryName, required this.state});

  final String id;
  final String name;
  final String? categoryName;
  final String state;
}

/// A real, RLS-scoped read against the same schema apps/web's /skills page
/// uses -- `skills` (public) joined with `skill_categories`, and this
/// user's own `user_skill_states` (owner-scoped by RLS, exactly like the
/// web app: no client-side filtering pretending to be security). No mock
/// data: an empty/misconfigured Supabase project shows a real empty list
/// or a real error, never a fabricated skill.
Future<List<SkillRow>> fetchSkills(SupabaseClient client, String userId) async {
  final skillsResponse = await client
      .from('skills')
      .select('id, name, skill_categories(name)')
      .order('name');
  final statesResponse = await client.from('user_skill_states').select('skill_id, state').eq('user_id', userId);

  final stateBySkillId = <String, String>{};
  for (final row in statesResponse as List) {
    stateBySkillId[row['skill_id'] as String] = row['state'] as String;
  }

  return (skillsResponse as List).map((row) {
    final category = row['skill_categories'] as Map<String, dynamic>?;
    return SkillRow(
      id: row['id'] as String,
      name: row['name'] as String,
      categoryName: category?['name'] as String?,
      state: stateBySkillId[row['id'] as String] ?? 'NOT_STARTED',
    );
  }).toList();
}

class SkillsScreen extends StatefulWidget {
  const SkillsScreen({super.key});

  @override
  State<SkillsScreen> createState() => _SkillsScreenState();
}

class _SkillsScreenState extends State<SkillsScreen> {
  late Future<List<SkillRow>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<SkillRow>> _load() {
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser!.id;
    return fetchSkills(client, userId);
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async {
        final next = _load();
        setState(() => _future = next);
        await next;
      },
      child: FutureBuilder<List<SkillRow>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('Could not load your skills: ${snapshot.error}'),
                ),
              ],
            );
          }
          final skills = snapshot.data ?? const [];
          if (skills.isEmpty) {
            return ListView(
              children: const [
                Padding(padding: EdgeInsets.all(24), child: Text('No skills are published yet.')),
              ],
            );
          }
          final scheme = Theme.of(context).colorScheme;
          return ListView.separated(
            itemCount: skills.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final skill = skills[index];
              return ListTile(
                title: Text(skill.name),
                subtitle: skill.categoryName != null ? Text(skill.categoryName!) : null,
                trailing: Chip(
                  label: Text(skillStateLabel(skill.state)),
                  labelStyle: TextStyle(color: skillStateColor(skill.state, scheme)),
                  side: BorderSide(color: skillStateColor(skill.state, scheme).withValues(alpha: 0.4)),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
