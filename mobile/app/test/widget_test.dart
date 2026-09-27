import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icorepen/main.dart';

void main() {
  testWidgets('shows the config-missing screen when Supabase env is not set', (WidgetTester tester) async {
    // No --dart-define was passed to this test run, so SupabaseEnv.isConfigured
    // is false and the app must fail closed, not crash trying to reach a
    // real Supabase client that was never initialized.
    await tester.pumpWidget(const IcorePenApp());
    await tester.pumpAndSettle();

    expect(find.textContaining('Supabase is not configured.'), findsOneWidget);
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
