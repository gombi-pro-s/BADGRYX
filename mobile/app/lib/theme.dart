import 'package:flutter/material.dart';

/// The same brand tokens as apps/web/src/app/globals.css, not Flutter's
/// default Material seed colors -- light background #ffffff / accent
/// #0d7d7d, dark background #0a0d12 / accent #2dd4bf.
const Color _accentLight = Color(0xFF0D7D7D);
const Color _accentDark = Color(0xFF2DD4BF);
const Color _backgroundDark = Color(0xFF0A0D12);

ThemeData buildLightTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: _accentLight, brightness: Brightness.light).copyWith(
    primary: _accentLight,
    surface: Colors.white,
  );
  return ThemeData(useMaterial3: true, colorScheme: scheme, scaffoldBackgroundColor: Colors.white);
}

ThemeData buildDarkTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: _accentDark, brightness: Brightness.dark).copyWith(
    primary: _accentDark,
    surface: _backgroundDark,
  );
  return ThemeData(useMaterial3: true, colorScheme: scheme, scaffoldBackgroundColor: _backgroundDark);
}
