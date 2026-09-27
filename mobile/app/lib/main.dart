import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth/auth_gate.dart';
import 'config/env.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (SupabaseEnv.isConfigured) {
    await Supabase.initialize(url: SupabaseEnv.url, publishableKey: SupabaseEnv.anonKey);
  }
  runApp(const IcorePenApp());
}

class IcorePenApp extends StatelessWidget {
  const IcorePenApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'iCorePen',
      debugShowCheckedModeBanner: false,
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      home: SupabaseEnv.isConfigured ? const AuthGate() : const ConfigMissingScreen(),
    );
  }
}

/// Supabase is this app's only backend -- unlike Turnstile/billing on the
/// web app (optional enhancements that degrade gracefully without keys),
/// there is no functional app without it. Failing loudly and clearly here
/// beats a Supabase client throwing a confusing error deep in a widget
/// tree the first time a screen tries to query something.
class ConfigMissingScreen extends StatelessWidget {
  const ConfigMissingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Supabase is not configured.\n\n'
            'Run with:\n'
            'flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...\n\n'
            'See mobile/app/README.md.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
