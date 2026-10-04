import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_quiz.dart';

/// Mirrors `admin/quizzes/page.tsx` + `[quizId]/page.tsx` + `actions.ts` +
/// `questions-manager.tsx` -- plain RLS-scoped Postgrest CRUD throughout
/// (`quizzes`/`quiz_skills` are staff-write/anyone-read,
/// `quiz_questions`/`quiz_choices` are staff-only full stop -- see
/// `20260921000009_content_model_rls.sql`), no Route Handler needed, same
/// shape as the CTF Challenges screen (ADR 0053). There is no "edit quiz"
/// form on the web admin UI either -- once created, a quiz's own fields
/// (slug/title/passing score/time limit/hint policy/exam flag) are fixed;
/// only its published state, skills, and questions change afterward -- so
/// this screen doesn't add one.
Future<List<AdminQuiz>> fetchAdminQuizzes(SupabaseClient client) async {
  final rows = await client.from('quizzes').select('id, slug, title, is_exam, published').order('title');
  return (rows as List).map((row) => AdminQuiz.fromRow(row as Map<String, dynamic>)).toList();
}

class AdminQuizzesScreen extends StatefulWidget {
  const AdminQuizzesScreen({super.key});

  @override
  State<AdminQuizzesScreen> createState() => _AdminQuizzesScreenState();
}

class _AdminQuizzesScreenState extends State<AdminQuizzesScreen> {
  late Future<List<AdminQuiz>> _future;

  @override
  void initState() {
    super.initState();
    _future = fetchAdminQuizzes(Supabase.instance.client);
  }

  Future<void> _refresh() async {
    final next = fetchAdminQuizzes(Supabase.instance.client);
    setState(() => _future = next);
    await next;
  }

  Future<void> _openCreate() async {
    final created = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const AdminCreateQuizScreen()));
    if (created == true) await _refresh();
  }

  Future<void> _openDetail(String quizId) async {
    final changed = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => AdminQuizDetailScreen(quizId: quizId)));
    if (changed == true) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Quizzes')),
      floatingActionButton: FloatingActionButton(
        onPressed: _openCreate,
        tooltip: 'New quiz',
        child: const Icon(Icons.add),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<AdminQuiz>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(child: Text('Could not load quizzes: ${snapshot.error}'));
            }
            final quizzes = snapshot.data ?? [];
            if (quizzes.isEmpty) {
              return ListView(
                children: const [
                  Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('No quizzes yet. Create the first one with the + button.'),
                  ),
                ],
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: quizzes.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final quiz = quizzes[index];
                return Card(
                  child: ListTile(
                    title: Text(quiz.title),
                    subtitle: quiz.isExam ? const Text('Exam') : null,
                    trailing: Chip(label: Text(quiz.published ? 'Published' : 'Draft')),
                    onTap: () => _openDetail(quiz.id),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class AdminCreateQuizScreen extends StatefulWidget {
  const AdminCreateQuizScreen({super.key});

  @override
  State<AdminCreateQuizScreen> createState() => _AdminCreateQuizScreenState();
}

class _AdminCreateQuizScreenState extends State<AdminCreateQuizScreen> {
  final _titleController = TextEditingController();
  final _slugController = TextEditingController();
  final _passingScoreController = TextEditingController(text: '70');
  final _timeLimitController = TextEditingController();
  String _hintPolicy = 'full';
  bool _isExam = false;
  bool _saving = false;
  String? _error;

  Future<void> _save() async {
    final title = _titleController.text.trim();
    final slug = _slugController.text.trim();
    final passingScore = num.tryParse(_passingScoreController.text.trim());
    if (title.isEmpty) {
      setState(() => _error = 'Title is required.');
      return;
    }
    if (!isValidQuizSlug(slug)) {
      setState(() => _error = 'Lowercase letters, numbers, hyphens only.');
      return;
    }
    if (passingScore == null || passingScore < 0 || passingScore > 100) {
      setState(() => _error = 'Passing score must be between 0 and 100.');
      return;
    }
    final timeLimitText = _timeLimitController.text.trim();
    final timeLimit = timeLimitText.isEmpty ? null : int.tryParse(timeLimitText);
    if (timeLimitText.isNotEmpty && (timeLimit == null || timeLimit < 1 || timeLimit > 600)) {
      setState(() => _error = 'Time limit must be between 1 and 600 minutes.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await Supabase.instance.client.from('quizzes').insert({
        'slug': slug,
        'title': title,
        'passing_score': passingScore,
        'is_exam': _isExam,
        'time_limit_minutes': timeLimit,
        'hint_policy': _hintPolicy,
      });
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      final message = e is PostgrestException && e.code == '23505'
          ? 'That slug is already in use.'
          : 'Could not create the quiz.';
      setState(() {
        _error = message;
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New quiz')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(controller: _titleController, maxLength: 200, decoration: const InputDecoration(labelText: 'Title')),
          const SizedBox(height: 12),
          TextField(
            controller: _slugController,
            decoration: const InputDecoration(labelText: 'Slug', hintText: 'sqli-quiz'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _passingScoreController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Passing score (%)'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _hintPolicy,
            decoration: const InputDecoration(labelText: 'Hint policy'),
            items: quizHintPolicies
                .map((p) => DropdownMenuItem(value: p, child: Text(p[0].toUpperCase() + p.substring(1))))
                .toList(),
            onChanged: (value) => setState(() => _hintPolicy = value ?? 'full'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _timeLimitController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Time limit (min, optional)'),
          ),
          const SizedBox(height: 8),
          CheckboxListTile(
            value: _isExam,
            onChanged: (value) => setState(() => _isExam = value ?? false),
            title: const Text('This is an exam'),
            subtitle: const Text('Records "assessment" skill evidence instead of "quiz"'),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 16),
          FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Creating...' : 'Create quiz')),
        ],
      ),
    );
  }
}

class AdminQuizDetailScreen extends StatefulWidget {
  const AdminQuizDetailScreen({super.key, required this.quizId});

  final String quizId;

  @override
  State<AdminQuizDetailScreen> createState() => _AdminQuizDetailScreenState();
}

class _AdminQuizDetailScreenState extends State<AdminQuizDetailScreen> {
  bool _loading = true;
  bool _changed = false;
  String? _error;
  AdminQuiz? _quiz;
  List<Map<String, dynamic>> _allSkills = const [];
  Set<String> _selectedSkillIds = {};
  bool _skillsSaving = false;
  bool _skillsSaved = false;
  List<AdminQuizQuestion> _questions = const [];
  String? _deletingQuestionId;

  final _questionTextController = TextEditingController();
  List<QuizChoiceDraft> _draftChoices = [QuizChoiceDraft(), QuizChoiceDraft()];
  bool _addingQuestion = false;
  String? _addQuestionError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final client = Supabase.instance.client;
      final quizRow = await client
          .from('quizzes')
          .select('id, slug, title, is_exam, published')
          .eq('id', widget.quizId)
          .single();
      final allSkillsRows = await client.from('skills').select('id, name').order('name');
      final quizSkillRows = await client.from('quiz_skills').select('skill_id').eq('quiz_id', widget.quizId);
      await _loadQuestions(client);
      setState(() {
        _quiz = AdminQuiz.fromRow(quizRow);
        _allSkills = (allSkillsRows as List).cast<Map<String, dynamic>>();
        _selectedSkillIds = (quizSkillRows as List).map((r) => r['skill_id'] as String).toSet();
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Could not load this quiz.';
        _loading = false;
      });
    }
  }

  Future<void> _loadQuestions(SupabaseClient client) async {
    final questionRows =
        await client
                .from('quiz_questions')
                .select('id, question_text, order_index')
                .eq('quiz_id', widget.quizId)
                .order('order_index')
            as List;
    final questionIds = questionRows.map((r) => r['id'] as String).toList();
    final choicesByQuestion = <String, List<AdminQuizChoice>>{};
    if (questionIds.isNotEmpty) {
      final choiceRows = await client
          .from('quiz_choices')
          .select('id, question_id, choice_text, is_correct, order_index')
          .inFilter('question_id', questionIds)
          .order('order_index');
      for (final row in choiceRows as List) {
        final map = row as Map<String, dynamic>;
        final list = choicesByQuestion.putIfAbsent(map['question_id'] as String, () => []);
        list.add(AdminQuizChoice.fromRow(map));
      }
    }
    setState(() {
      _questions = questionRows
          .map((row) => AdminQuizQuestion.fromRow(row as Map<String, dynamic>, choicesByQuestion[row['id']] ?? []))
          .toList();
    });
  }

  Future<void> _togglePublished(bool value) async {
    final client = Supabase.instance.client;
    try {
      await client.from('quizzes').update({'published': value}).eq('id', widget.quizId);
      await client.rpc(
        'log_audit_event',
        params: {'p_action': value ? 'quiz.published' : 'quiz.unpublished', 'p_target_type': 'quiz', 'p_target_id': widget.quizId},
      );
      setState(() {
        _quiz = AdminQuiz(id: _quiz!.id, slug: _quiz!.slug, title: _quiz!.title, isExam: _quiz!.isExam, published: value);
        _changed = true;
      });
    } catch (e) {
      setState(() => _error = 'Could not change the published state.');
    }
  }

  Future<void> _saveSkills() async {
    setState(() {
      _skillsSaving = true;
      _skillsSaved = false;
    });
    final client = Supabase.instance.client;
    try {
      await client.from('quiz_skills').delete().eq('quiz_id', widget.quizId);
      if (_selectedSkillIds.isNotEmpty) {
        await client
            .from('quiz_skills')
            .insert(_selectedSkillIds.map((skillId) => {'quiz_id': widget.quizId, 'skill_id': skillId}).toList());
      }
      _changed = true;
      setState(() {
        _skillsSaving = false;
        _skillsSaved = true;
      });
    } catch (e) {
      setState(() {
        _skillsSaving = false;
        _error = 'Could not save skills.';
      });
    }
  }

  Future<void> _addQuestion() async {
    final trimmed = trimmedNonEmptyChoices(_draftChoices);
    final choicesError = quizChoicesError(trimmed);
    if (_questionTextController.text.trim().isEmpty) {
      setState(() => _addQuestionError = 'Question text is required.');
      return;
    }
    if (choicesError != null) {
      setState(() => _addQuestionError = choicesError);
      return;
    }
    setState(() {
      _addingQuestion = true;
      _addQuestionError = null;
    });
    final client = Supabase.instance.client;
    try {
      final question = await client
          .from('quiz_questions')
          .insert({
            'quiz_id': widget.quizId,
            'question_text': _questionTextController.text.trim(),
            'question_type': 'single_choice',
          })
          .select('id')
          .single();
      await client.from('quiz_choices').insert(
        List.generate(
          trimmed.length,
          (i) => {
            'question_id': question['id'],
            'choice_text': trimmed[i].text,
            'is_correct': trimmed[i].isCorrect,
            'order_index': i,
          },
        ),
      );
      _questionTextController.clear();
      _changed = true;
      setState(() {
        _draftChoices = [QuizChoiceDraft(), QuizChoiceDraft()];
        _addingQuestion = false;
      });
      await _loadQuestions(client);
    } catch (e) {
      setState(() {
        _addingQuestion = false;
        _addQuestionError = 'Failed to create question.';
      });
    }
  }

  Future<void> _deleteQuestion(String questionId) async {
    setState(() => _deletingQuestionId = questionId);
    final client = Supabase.instance.client;
    try {
      await client.from('quiz_questions').delete().eq('id', questionId);
      _changed = true;
      await _loadQuestions(client);
    } catch (e) {
      setState(() => _error = 'Could not remove this question.');
    } finally {
      setState(() => _deletingQuestionId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final quiz = _quiz;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        Navigator.of(context).pop(_changed);
      },
      child: Scaffold(
        appBar: AppBar(title: Text(quiz?.title ?? 'Quiz')),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : quiz == null
            ? Center(child: Text(_error ?? 'Not found.'))
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  SwitchListTile(
                    title: const Text('Published'),
                    value: quiz.published,
                    onChanged: _togglePublished,
                  ),
                  const SizedBox(height: 16),
                  Text('Skills assessed', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _allSkills.map((skill) {
                      final id = skill['id'] as String;
                      final selected = _selectedSkillIds.contains(id);
                      return FilterChip(
                        label: Text(skill['name'] as String),
                        selected: selected,
                        onSelected: (value) {
                          setState(() {
                            _skillsSaved = false;
                            if (value) {
                              _selectedSkillIds.add(id);
                            } else {
                              _selectedSkillIds.remove(id);
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      OutlinedButton(
                        onPressed: _skillsSaving ? null : _saveSkills,
                        child: Text(_skillsSaving ? 'Saving...' : 'Save skills'),
                      ),
                      if (_skillsSaved && !_skillsSaving) ...[const SizedBox(width: 12), const Text('Saved.')],
                    ],
                  ),
                  const SizedBox(height: 24),
                  Text('Questions', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  if (_questions.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: Text('No questions yet. The quiz cannot be graded without one.'),
                    )
                  else
                    ..._questions.map(
                      (q) => Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(child: Text(q.questionText, style: const TextStyle(fontWeight: FontWeight.w500))),
                                  TextButton(
                                    onPressed: _deletingQuestionId == q.id ? null : () => _deleteQuestion(q.id),
                                    child: Text(_deletingQuestionId == q.id ? 'Removing...' : 'Remove'),
                                  ),
                                ],
                              ),
                              ...q.choices.map(
                                (c) => Row(
                                  children: [
                                    Icon(
                                      c.isCorrect ? Icons.check_circle : Icons.radio_button_unchecked,
                                      size: 16,
                                      color: c.isCorrect ? Colors.green : Theme.of(context).colorScheme.outline,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(c.text, style: Theme.of(context).textTheme.bodySmall),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          controller: _questionTextController,
                          maxLines: 2,
                          decoration: const InputDecoration(labelText: 'Question'),
                        ),
                        const SizedBox(height: 8),
                        const Text('Choices (check the correct one(s))'),
                        ...List.generate(_draftChoices.length, (i) {
                          final choice = _draftChoices[i];
                          return Row(
                            children: [
                              Checkbox(
                                value: choice.isCorrect,
                                onChanged: (value) => setState(() => choice.isCorrect = value ?? false),
                              ),
                              Expanded(
                                child: TextField(
                                  decoration: InputDecoration(labelText: 'Choice ${i + 1}'),
                                  onChanged: (value) => choice.text = value,
                                ),
                              ),
                            ],
                          );
                        }),
                        TextButton(
                          onPressed: () => setState(() => _draftChoices.add(QuizChoiceDraft())),
                          child: const Text('+ Add choice'),
                        ),
                        if (_addQuestionError != null)
                          Text(_addQuestionError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                        const SizedBox(height: 8),
                        FilledButton(
                          onPressed: _addingQuestion ? null : _addQuestion,
                          child: Text(_addingQuestion ? 'Adding...' : 'Add question'),
                        ),
                      ],
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ],
                ],
              ),
      ),
    );
  }
}
