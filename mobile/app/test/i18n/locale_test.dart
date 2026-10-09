import 'package:flutter_test/flutter_test.dart';
import 'package:icorepen/i18n/locale.dart';

void main() {
  group('isSupportedLocale', () {
    test('en and es are supported', () {
      expect(isSupportedLocale('en'), isTrue);
      expect(isSupportedLocale('es'), isTrue);
    });

    test('an unrecognized value is not supported', () {
      expect(isSupportedLocale('fr'), isFalse);
      expect(isSupportedLocale(''), isFalse);
    });
  });

  test('defaultLocale is en', () {
    expect(defaultLocale, 'en');
  });
}
