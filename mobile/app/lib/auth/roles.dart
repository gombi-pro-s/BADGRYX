import 'package:supabase_flutter/supabase_flutter.dart';

/// Mirrors lib/auth/session.ts's getUserRoles(): every platform_role row
/// the current user holds, read straight from `user_roles` under
/// `user_roles_select_own_or_admin`'s RLS -- a plain user already has
/// implicit 'user' standing (handle_new_user()'s trigger, never a stored
/// row), which isStaffRole() below never cares about anyway.
Future<List<String>> fetchUserRoles(SupabaseClient client, String userId) async {
  final rows = await client.from('user_roles').select('role').eq('user_id', userId);
  return (rows as List).map((row) => (row as Map<String, dynamic>)['role'] as String).toList();
}

/// Mirrors is_staff() (20260921000002_profiles_and_rbac.sql): admin or
/// moderator. This decides only whether to show the Admin entry point in
/// the More screen -- every admin table/action this app's admin screens
/// read or write is still gated by the exact same RLS/SECURITY DEFINER
/// checks a browser client gets, so a wrong answer here could only ever
/// hide a real button, never grant a real permission.
bool isStaffRole(List<String> roles) => roles.contains('admin') || roles.contains('moderator');
