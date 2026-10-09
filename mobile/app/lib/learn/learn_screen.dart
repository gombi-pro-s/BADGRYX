import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../i18n/locale.dart';
import '../mentor/mentor_screen.dart';
import '../mentor/modes.dart';
import 'lesson.dart';

/// Mirrors `learn/page.tsx` + `learn/[pathId]/page.tsx` +
/// `learn/[pathId]/[moduleId]/[lessonId]/page.tsx` + `mark-read.tsx` +
/// `quiz-attempt.tsx` -- the learner-facing reader apps/web's own admin
/// authoring screens (ADR 0055) never had a mobile counterpart for.
/// Everything here is plain RLS-scoped Postgrest/RPC, no Route Handler:
/// `learning_paths`/`modules`/`lessons` are staff-write/anyone-reads-
/// published, `lesson_progress` is owner-read-write-own
/// (`lesson_progress_own`), and grading runs exclusively through the
/// real `submit_quiz_attempt()` RPC, same as every quiz in this app.
///
/// Lesson content renders as plain text, not a rendered Markdown
/// article: no markdown-rendering package exists anywhere in this app
/// yet (every other `*_markdown` field -- announcements, reports, the
/// admin lesson editor -- is shown as raw text too, including on the
/// learner-facing dashboard), so this stays consistent with that
/// existing convention rather than introducing the app's first one. See
/// ADR 0060.
/// Also reads the device's stored locale (ADR 0065) and the matching
/// `learning_path_translations` rows -- the same second round-trip
/// `/learn/page.tsx` makes rather than a join, since that table's own
/// RLS already scopes it to exactly the published path ids above.
Future<(List<LearningPathSummary>, Map<String, List<LearningPathTranslation>>, String)> fetchLearningPaths(
  SupabaseClient client,
) async {
  final rows = await client
      .from('learning_paths')
      .select('id, title, description')
      .eq('published', true)
      .order('order_index');
  final paths = (rows as List).map((row) => LearningPathSummary.fromRow(row as Map<String, dynamic>)).toList();

  final locale = await LocaleStore.getLocale();
  final translationRows = paths.isEmpty
      ? const []
      : await client
          .from('learning_path_translations')
          .select('path_id, locale, title, description')
          .inFilter('path_id', paths.map((p) => p.id).toList());
  final translationsByPathId = <String, List<LearningPathTranslation>>{};
  for (final row in translationRows) {
    final t = LearningPathTranslation.fromRow(row as Map<String, dynamic>);
    (translationsByPathId[t.pathId] ??= []).add(t);
  }

  return (paths, translationsByPathId, locale);
}

class LearnPathsListScreen extends StatefulWidget {
  const LearnPathsListScreen({super.key});

  @override
  State<LearnPathsListScreen> createState() => _LearnPathsListScreenState();
}

class _LearnPathsListScreenState extends State<LearnPathsListScreen> {
  late Future<(List<LearningPathSummary>, Map<String, List<LearningPathTranslation>>, String)> _future;

  @override
  void initState() {
    super.initState();
    _future = fetchLearningPaths(Supabase.instance.client);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Learn')),
      body: FutureBuilder<(List<LearningPathSummary>, Map<String, List<LearningPathTranslation>>, String)>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Could not load learning paths: ${snapshot.error}'));
          }
          final (paths, translationsByPathId, locale) = snapshot.data ?? (<LearningPathSummary>[], <String, List<LearningPathTranslation>>{}, defaultLocale);
          if (paths.isEmpty) {
            return const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('No learning paths are published yet.')));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: paths.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final path = paths[index];
              final text = pickPathText(path, translationsByPathId[path.id] ?? const [], locale);
              return Card(
                child: ListTile(
                  title: Text(text.title),
                  subtitle: text.description != null ? Text(text.description!) : null,
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => LearnPathDetailScreen(pathId: path.id)),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class LearnPathDetailScreen extends StatefulWidget {
  const LearnPathDetailScreen({super.key, required this.pathId});

  final String pathId;

  @override
  State<LearnPathDetailScreen> createState() => _LearnPathDetailScreenState();
}

class _PathDetailData {
  _PathDetailData({
    required this.path,
    required this.pathTranslation,
    required this.modules,
    required this.lessonsByModule,
    required this.lessonTranslationsByLessonId,
    required this.completedLessonIds,
    required this.locale,
  });

  final LearningPathSummary path;
  final LearningPathTranslation? pathTranslation;
  final List<Map<String, dynamic>> modules;
  final Map<String, List<LessonSummary>> lessonsByModule;
  final Map<String, List<LessonTranslation>> lessonTranslationsByLessonId;
  final Set<String> completedLessonIds;
  final String locale;
}

class _LearnPathDetailScreenState extends State<LearnPathDetailScreen> {
  late Future<_PathDetailData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_PathDetailData> _load() async {
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser!.id;
    final pathRow = await client
        .from('learning_paths')
        .select('id, title, description')
        .eq('id', widget.pathId)
        .eq('published', true)
        .single();
    final moduleRows = await client
        .from('modules')
        .select('id, title, order_index')
        .eq('path_id', widget.pathId)
        .eq('published', true)
        .order('order_index');
    final lessonRows = await client
        .from('lessons')
        .select('id, module_id, title, order_index, estimated_minutes')
        .eq('published', true)
        .order('order_index');
    final progressRows = await client.from('lesson_progress').select('lesson_id, completed_at').eq('user_id', userId);

    final path = LearningPathSummary.fromRow(pathRow);
    final lessons = (lessonRows as List).map((row) => LessonSummary.fromRow(row as Map<String, dynamic>)).toList();
    final completedLessonIds = (progressRows as List)
        .where((row) => (row as Map<String, dynamic>)['completed_at'] != null)
        .map((row) => (row as Map<String, dynamic>)['lesson_id'] as String)
        .toSet();

    final locale = await LocaleStore.getLocale();
    final pathTranslationRow = await client
        .from('learning_path_translations')
        .select('path_id, locale, title, description')
        .eq('path_id', widget.pathId)
        .eq('locale', 'es')
        .maybeSingle();
    final lessonTranslationRows = lessons.isEmpty
        ? const []
        : await client
            .from('lesson_translations')
            .select('lesson_id, locale, title, content_markdown')
            .inFilter('lesson_id', lessons.map((l) => l.id).toList());
    final lessonTranslationsByLessonId = <String, List<LessonTranslation>>{};
    for (final row in lessonTranslationRows) {
      final t = LessonTranslation.fromRow(row as Map<String, dynamic>);
      (lessonTranslationsByLessonId[t.lessonId] ??= []).add(t);
    }

    return _PathDetailData(
      path: path,
      pathTranslation: pathTranslationRow != null ? LearningPathTranslation.fromRow(pathTranslationRow) : null,
      modules: (moduleRows as List).cast<Map<String, dynamic>>(),
      lessonsByModule: groupLessonsByModule(lessons),
      lessonTranslationsByLessonId: lessonTranslationsByLessonId,
      completedLessonIds: completedLessonIds,
      locale: locale,
    );
  }

  Future<void> _refresh() async {
    final next = _load();
    setState(() => _future = next);
    await next;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Path')),
      body: FutureBuilder<_PathDetailData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return Center(child: Text('Could not load this path: ${snapshot.error}'));
          }
          final data = snapshot.data!;
          final pathText = pickPathText(data.path, data.pathTranslation != null ? [data.pathTranslation!] : const [], data.locale);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(pathText.title, style: Theme.of(context).textTheme.headlineSmall),
              if (pathText.description != null) ...[
                const SizedBox(height: 4),
                Text(pathText.description!),
              ],
              const SizedBox(height: 16),
              for (final mod in data.modules) ...[
                if ((data.lessonsByModule[mod['id'] as String] ?? const <LessonSummary>[]).isNotEmpty) ...[
                  Text(
                    (mod['title'] as String).toUpperCase(),
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                  const SizedBox(height: 4),
                  Card(
                    child: Column(
                      children: (data.lessonsByModule[mod['id'] as String] ?? const <LessonSummary>[]).map((lesson) {
                        final completed = data.completedLessonIds.contains(lesson.id);
                        final lessonText = pickLessonText(
                          (title: lesson.title, contentMarkdown: ''),
                          data.lessonTranslationsByLessonId[lesson.id] ?? const [],
                          data.locale,
                        );
                        return ListTile(
                          title: Text(lessonText.title),
                          trailing: Text(
                            completed ? 'Read' : '${lesson.estimatedMinutes} min',
                            style: completed ? TextStyle(color: Theme.of(context).colorScheme.primary) : null,
                          ),
                          onTap: () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => LessonViewerScreen(
                                  pathId: widget.pathId,
                                  moduleId: mod['id'] as String,
                                  lessonId: lesson.id,
                                ),
                              ),
                            );
                            await _refresh();
                          },
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ],
            ],
          );
        },
      ),
    );
  }
}

class LessonViewerScreen extends StatefulWidget {
  const LessonViewerScreen({super.key, required this.pathId, required this.moduleId, required this.lessonId});

  final String pathId;
  final String moduleId;
  final String lessonId;

  @override
  State<LessonViewerScreen> createState() => _LessonViewerScreenState();
}

class _LessonViewerScreenState extends State<LessonViewerScreen> {
  late Future<(LessonDetail, LessonText, LessonQuiz?)> _future;
  bool _marked = false;
  final Map<String, String> _answers = {};
  ({bool passed, num score})? _result;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<(LessonDetail, LessonText, LessonQuiz?)> _load() async {
    final client = Supabase.instance.client;
    final lessonRow = await client
        .from('lessons')
        .select('id, title, content_markdown, module_id')
        .eq('id', widget.lessonId)
        .eq('published', true)
        .single();
    final lesson = LessonDetail.fromRow(lessonRow);

    final locale = await LocaleStore.getLocale();
    final translationRow = await client
        .from('lesson_translations')
        .select('lesson_id, locale, title, content_markdown')
        .eq('lesson_id', widget.lessonId)
        .eq('locale', 'es')
        .maybeSingle();
    final lessonText = pickLessonText(
      (title: lesson.title, contentMarkdown: lesson.contentMarkdown),
      translationRow != null ? [LessonTranslation.fromRow(translationRow)] : const [],
      locale,
    );

    await _markRead();

    final linkedQuiz = await client
        .from('quizzes')
        .select('id')
        .eq('lesson_id', widget.lessonId)
        .eq('published', true)
        .maybeSingle();
    if (linkedQuiz == null) return (lesson, lessonText, null);

    final quizRows = await client
        .from('quiz_questions_for_attempt')
        .select('quiz_id, title, passing_score, question_id, question_text, question_type, choice_id, choice_text')
        .eq('quiz_id', linkedQuiz['id'] as String);
    if ((quizRows as List).isEmpty) return (lesson, lessonText, null);

    return (lesson, lessonText, groupLessonQuizRows(quizRows.cast<Map<String, dynamic>>()));
  }

  /// Mirrors `mark-read.tsx`'s own "once per mount" upsert -- UX
  /// convenience, not the real "theory" skill evidence gate (that's
  /// passing the lesson's own quiz); `lesson_progress_own` RLS is the
  /// actual enforcement either way.
  Future<void> _markRead() async {
    if (_marked) return;
    _marked = true;
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser!.id;
    await client.from('lesson_progress').upsert(
      {'user_id': userId, 'lesson_id': widget.lessonId, 'completed_at': DateTime.now().toUtc().toIso8601String()},
      onConflict: 'user_id,lesson_id',
    );
  }

  Future<void> _submitQuiz(LessonQuiz quiz) async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final payload = buildLessonQuizAnswerPayload(quiz.questions, _answers);
      final data = await Supabase.instance.client.rpc(
        'submit_quiz_attempt',
        params: {'p_quiz_id': quiz.quizId, 'p_answers': payload},
      );
      final attempt = data as Map<String, dynamic>;
      setState(() {
        _result = (passed: attempt['passed'] as bool, score: attempt['score'] as num);
        _submitting = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Lesson')),
      body: FutureBuilder<(LessonDetail, LessonText, LessonQuiz?)>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return Center(child: Text('Could not load this lesson: ${snapshot.error}'));
          }
          final (lesson, lessonText, quiz) = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  Expanded(child: Text(lessonText.title, style: Theme.of(context).textTheme.headlineSmall)),
                  TextButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => MentorScreen(
                          contextType: 'lesson',
                          contextId: lesson.id,
                          initialMode: MentorMode.teach,
                          focusTitle: lessonText.title,
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.psychology_outlined, size: 18),
                    label: const Text('Mentor'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(lessonText.contentMarkdown),
              if (quiz != null) ...[
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: _result != null
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${_result!.passed ? 'Passed' : 'Not yet'} — ${_result!.score}% '
                              '(passing: ${quiz.passingScore}%)',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: _result!.passed
                                    ? Theme.of(context).colorScheme.primary
                                    : Theme.of(context).colorScheme.error,
                              ),
                            ),
                            if (!_result!.passed)
                              TextButton(
                                onPressed: () => setState(() {
                                  _result = null;
                                  _answers.clear();
                                }),
                                child: const Text('Try again'),
                              ),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(quiz.title, style: Theme.of(context).textTheme.titleSmall),
                            const SizedBox(height: 12),
                            for (final question in quiz.questions) ...[
                              Text(question.questionText),
                              RadioGroup<String>(
                                groupValue: _answers[question.questionId],
                                onChanged: (value) => setState(() => _answers[question.questionId] = value!),
                                child: Column(
                                  children: question.choices
                                      .map(
                                        (choice) => RadioListTile<String>(
                                          value: choice.choiceId,
                                          title: Text(choice.choiceText),
                                          dense: true,
                                          contentPadding: EdgeInsets.zero,
                                        ),
                                      )
                                      .toList(),
                                ),
                              ),
                              const SizedBox(height: 8),
                            ],
                            if (_error != null)
                              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                            FilledButton(
                              onPressed: _submitting ? null : () => _submitQuiz(quiz),
                              child: Text(_submitting ? 'Submitting...' : 'Submit answers'),
                            ),
                          ],
                        ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
