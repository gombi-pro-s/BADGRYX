import 'package:flutter_test/flutter_test.dart';
import 'package:icorepen/config/env.dart';

void main() {
  group('isSupabaseConfigured', () {
    test('false when both values are empty', () {
      expect(isSupabaseConfigured('', ''), isFalse);
    });

    test('false when only the URL is set', () {
      expect(isSupabaseConfigured('https://x.supabase.co', ''), isFalse);
    });

    test('false when only the anon key is set', () {
      expect(isSupabaseConfigured('', 'anon-key'), isFalse);
    });

    test('true when both are set', () {
      expect(isSupabaseConfigured('https://x.supabase.co', 'anon-key'), isTrue);
    });
  });

  test('SupabaseEnv.isConfigured is false with no --dart-define supplied (this test run)', () {
    // Compile-time constants read via String.fromEnvironment default to ''
    // unless --dart-define is passed to `flutter test` -- proves the app
    // genuinely fails closed (ConfigMissingScreen, see main_test.dart)
    // rather than silently using a placeholder URL/key.
    expect(SupabaseEnv.isConfigured, isFalse);
  });
}
