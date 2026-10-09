import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'profile.dart';

/// Mirrors `/settings`'s own Profile form exactly: the same four
/// fields (`display_name`, `username`, `bio`, `timezone`), the same
/// `validateProfileUpdate()` client-side checks (a direct port of
/// `profileSchema`), and the same plain `profiles` Postgrest update --
/// `profiles_update_own` RLS is the real boundary here, same as on web,
/// not this screen's own `.eq('id', ...)`. See ADR 0066.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _displayNameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _bioController = TextEditingController();
  final _timezoneController = TextEditingController();

  late Future<void> _future;
  bool _saving = false;
  String? _error;
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _usernameController.dispose();
    _bioController.dispose();
    _timezoneController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser!.id;
    final row = await client.from('profiles').select('display_name, username, bio, timezone').eq('id', userId).single();
    _displayNameController.text = (row['display_name'] as String?) ?? '';
    _usernameController.text = (row['username'] as String?) ?? '';
    _bioController.text = (row['bio'] as String?) ?? '';
    _timezoneController.text = (row['timezone'] as String?) ?? 'UTC';
  }

  Future<void> _save() async {
    final validationError = validateProfileUpdate(
      displayName: _displayNameController.text,
      username: _usernameController.text,
      bio: _bioController.text,
      timezone: _timezoneController.text,
    );
    if (validationError != null) {
      setState(() {
        _error = validationError;
        _saved = false;
      });
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
      _saved = false;
    });
    try {
      final client = Supabase.instance.client;
      final userId = client.auth.currentUser!.id;
      await client
          .from('profiles')
          .update(
            buildProfileUpdateRow(
              displayName: _displayNameController.text,
              username: _usernameController.text,
              bio: _bioController.text,
              timezone: _timezoneController.text,
            ),
          )
          .eq('id', userId);
      setState(() {
        _saving = false;
        _saved = true;
      });
    } on PostgrestException catch (e) {
      setState(() {
        _saving = false;
        _error = e.code == '23505' ? 'That username is already taken.' : 'Could not save your profile. Please try again.';
      });
    } catch (e) {
      setState(() {
        _saving = false;
        _error = 'Could not save your profile. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: FutureBuilder<void>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Could not load your profile: ${snapshot.error}'));
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextField(
                controller: _displayNameController,
                maxLength: 80,
                decoration: const InputDecoration(labelText: 'Display name'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _usernameController,
                maxLength: 32,
                decoration: const InputDecoration(labelText: 'Username', hintText: 'optional'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _bioController,
                maxLines: 3,
                maxLength: 280,
                decoration: const InputDecoration(labelText: 'Bio', alignLabelWithHint: true),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _timezoneController,
                maxLength: 64,
                decoration: const InputDecoration(labelText: 'Timezone'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
              if (_saved) ...[
                const SizedBox(height: 12),
                Text('Saved.', style: TextStyle(color: Theme.of(context).colorScheme.primary)),
              ],
              const SizedBox(height: 16),
              FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Saving...' : 'Save changes')),
            ],
          );
        },
      ),
    );
  }
}
