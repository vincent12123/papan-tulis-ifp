import 'package:flutter/material.dart';

import '../canvas/stroke.dart';
import '../server/server_client.dart';
import '../ui/theme.dart';

/// What the teacher wrote for a quiz (REQ-27).
typedef QuizDraft = ({String title, List<(String, String)> pairs});

/// Kuis pencocokan: up to six pairs (left ↔ right), typed by the teacher or
/// suggested by the AI from what is on the page and then checked.
class QuizEditor extends StatefulWidget {
  const QuizEditor({super.key, this.suggest});

  /// Asks the AI for pairs from the page; null hides the button.
  final Future<List<(String, String)>> Function()? suggest;

  static const title = 'Kuis pencocokan';
  static const titleField = 'Judul kuis';
  static const defaultTitle = 'Pasangkan dengan benar';
  static const left = 'Kiri (soal)';
  static const right = 'Kanan (jawaban)';
  static const addPair = 'Tambah pasangan';
  static const suggestButton = 'Isi dari papan (AI)';
  static const suggesting = 'AI menyusun pasangan dari isi papan…';
  static const suggestFailed =
      'AI belum bisa menyusun kuis dari papan ini. Tulis pasangannya sendiri.';
  static const tooFew = 'Isi paling sedikit 2 pasangan lengkap.';
  static const cancel = 'Batal';
  static const create = 'Buat kuis';
  static const maxLength = 60;

  @override
  State<QuizEditor> createState() => _QuizEditorState();
}

class _QuizEditorState extends State<QuizEditor> {
  final _title = TextEditingController(text: QuizEditor.defaultTitle);
  final List<(TextEditingController, TextEditingController)> _rows = [];
  bool _busy = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    for (var i = 0; i < 3; i++) {
      _addRow();
    }
  }

  void _addRow([String a = '', String b = '']) => _rows.add((
    TextEditingController(text: a),
    TextEditingController(text: b),
  ));

  @override
  void dispose() {
    _title.dispose();
    for (final (a, b) in _rows) {
      a.dispose();
      b.dispose();
    }
    super.dispose();
  }

  List<(String, String)> get _pairs => [
    for (final (a, b) in _rows)
      if (a.text.trim().isNotEmpty && b.text.trim().isNotEmpty)
        (a.text.trim(), b.text.trim()),
  ];

  Future<void> _suggest() async {
    setState(() {
      _busy = true;
      _message = QuizEditor.suggesting;
    });
    List<(String, String)> pairs = const [];
    try {
      pairs = await widget.suggest!();
    } on ServerFailure {
      pairs = const [];
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (pairs.length < 2) {
        _message = QuizEditor.suggestFailed;
        return;
      }
      _message = null;
      for (final (a, b) in _rows) {
        a.dispose();
        b.dispose();
      }
      _rows.clear();
      for (final (a, b) in pairs.take(QuizItem.maxPairs)) {
        _addRow(a, b);
      }
    });
  }

  void _create() {
    final pairs = _pairs;
    if (pairs.length < 2) {
      setState(() => _message = QuizEditor.tooFew);
      return;
    }
    final title = _title.text.trim();
    Navigator.pop<QuizDraft>(context, (
      title: title.isEmpty ? QuizEditor.defaultTitle : title,
      pairs: pairs,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    InputDecoration box(String label) => InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
      counterText: '',
    );
    return AlertDialog(
      title: const Text(QuizEditor.title),
      content: SizedBox(
        width: 900,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _title,
                maxLength: QuizEditor.maxLength,
                decoration: box(QuizEditor.titleField),
              ),
              const SizedBox(height: AppSizes.space16),
              for (var i = 0; i < _rows.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSizes.space8),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _rows[i].$1,
                          maxLength: QuizEditor.maxLength,
                          decoration: box('${QuizEditor.left} ${i + 1}'),
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: AppSizes.space8,
                        ),
                        child: Icon(Icons.compare_arrows),
                      ),
                      Expanded(
                        child: TextField(
                          controller: _rows[i].$2,
                          maxLength: QuizEditor.maxLength,
                          decoration: box('${QuizEditor.right} ${i + 1}'),
                        ),
                      ),
                    ],
                  ),
                ),
              Wrap(
                spacing: AppSizes.space8,
                children: [
                  if (_rows.length < QuizItem.maxPairs)
                    OutlinedButton.icon(
                      onPressed: _busy ? null : () => setState(_addRow),
                      icon: const Icon(Icons.add),
                      label: const Text(QuizEditor.addPair),
                    ),
                  if (widget.suggest != null)
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _suggest,
                      icon: const Icon(Icons.auto_awesome),
                      label: const Text(QuizEditor.suggestButton),
                    ),
                ],
              ),
              if (_message != null) ...[
                const SizedBox(height: AppSizes.space16),
                Text(_message!, style: theme.textTheme.bodyLarge),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text(QuizEditor.cancel),
        ),
        FilledButton(
          onPressed: _busy ? null : _create,
          child: const Text(QuizEditor.create),
        ),
      ],
    );
  }
}
