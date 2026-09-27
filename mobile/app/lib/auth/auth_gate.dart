import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../home/home_shell.dart';
import 'login_screen.dart';

/// Reactively swaps between LoginScreen and HomeShell based on the real
/// Supabase Auth session -- no app-level "isLoggedIn" flag to drift out
/// of sync, the stream IS the source of truth.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final session = snapshot.data?.session ?? Supabase.instance.client.auth.currentSession;
        if (session != null) return const HomeShell();
        return const LoginScreen();
      },
    );
  }
}
