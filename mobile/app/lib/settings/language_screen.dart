import 'package:flutter/material.dart';

import '../i18n/locale.dart';

/// Mirrors `/settings`'s own "Language" section (`LocaleSwitcher`,
/// `settings.language.*` dictionary keys) -- the one piece of that page
/// this app has any use for, since mobile has no Profile/Security/
/// Privacy screens of its own yet (Billing already exists as its own
/// "More" entry). This is the first and only screen on mobile that
/// reads or writes the locale this app's translation tables
/// (`announcement_translations` since ADR 0038, `learning_path_
/// translations`/`lesson_translations` since ADR 0064) have always had
/// a write side for but never a read side -- see ADR 0065.
class LanguageScreen extends StatefulWidget {
  const LanguageScreen({super.key});

  @override
  State<LanguageScreen> createState() => _LanguageScreenState();
}

class _LanguageScreenState extends State<LanguageScreen> {
  late Future<String> _future;

  static const Map<String, String> _labels = {'en': 'English', 'es': 'Español'};

  @override
  void initState() {
    super.initState();
    _future = LocaleStore.getLocale();
  }

  Future<void> _select(String locale) async {
    await LocaleStore.setLocale(locale);
    setState(() => _future = LocaleStore.getLocale());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Language')),
      body: FutureBuilder<String>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final current = snapshot.data ?? defaultLocale;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Applies to the content that supports translation -- currently announcements and learning '
                "paths/lessons. Everything else in this app's own UI stays in English for now. Changing this "
                "takes effect the next time a screen loads (pull to refresh on Home, or re-open Learn).",
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              RadioGroup<String>(
                groupValue: current,
                onChanged: (value) => value == null ? null : _select(value),
                child: Column(
                  children: [
                    for (final locale in supportedLocales)
                      RadioListTile<String>(value: locale, title: Text(_labels[locale] ?? locale)),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
