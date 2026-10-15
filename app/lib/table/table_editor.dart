import 'package:flutter/material.dart';

import '../canvas/stroke.dart';
import '../ui/theme.dart';

/// "Sisipkan tabel": rows (with the title row) and columns (REQ-21).
class TableSizeDialog extends StatefulWidget {
  const TableSizeDialog({super.key});

  static const title = 'Sisipkan tabel';
  static const rows = 'Baris';
  static const cols = 'Kolom';
  static const note = 'Baris pertama berisi judul kolom.';
  static const cancel = 'Batal';
  static const insert = 'Sisipkan';

  @override
  State<TableSizeDialog> createState() => _TableSizeDialogState();
}

class _TableSizeDialogState extends State<TableSizeDialog> {
  int _rows = 5, _cols = 3;

  Widget _stepper(
    String label,
    int value,
    int min,
    int max,
    ValueChanged<int> set,
  ) {
    final style = Theme.of(context).textTheme;
    return Row(
      children: [
        SizedBox(width: 120, child: Text(label, style: style.titleLarge)),
        IconButton.outlined(
          tooltip: 'Kurangi $label',
          constraints: const BoxConstraints.tightFor(
            width: AppSizes.primaryTarget,
            height: AppSizes.primaryTarget,
          ),
          onPressed: value > min ? () => setState(() => set(value - 1)) : null,
          icon: const Icon(Icons.remove),
        ),
        SizedBox(
          width: 72,
          child: Text(
            '$value',
            textAlign: TextAlign.center,
            style: style.headlineSmall,
          ),
        ),
        IconButton.outlined(
          tooltip: 'Tambah $label',
          constraints: const BoxConstraints.tightFor(
            width: AppSizes.primaryTarget,
            height: AppSizes.primaryTarget,
          ),
          onPressed: value < max ? () => setState(() => set(value + 1)) : null,
          icon: const Icon(Icons.add),
        ),
        const SizedBox(width: AppSizes.space16),
        Text('$min–$max', style: style.bodyLarge),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(TableSizeDialog.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _stepper(
            TableSizeDialog.rows,
            _rows,
            TableItem.minRows,
            TableItem.maxRows,
            (v) => _rows = v,
          ),
          const SizedBox(height: AppSizes.space16),
          _stepper(
            TableSizeDialog.cols,
            _cols,
            TableItem.minCols,
            TableItem.maxCols,
            (v) => _cols = v,
          ),
          const SizedBox(height: AppSizes.space16),
          Text(
            TableSizeDialog.note,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text(TableSizeDialog.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop<(int, int)>(context, (_rows, _cols)),
          child: const Text(TableSizeDialog.insert),
        ),
      ],
    );
  }
}

/// "Isi tabel": every cell as a text field, opened at the tapped cell; the
/// keyboard's next key walks along the row. Simpan is one undo step.
class TableEditor extends StatefulWidget {
  const TableEditor({
    super.key,
    required this.cells,
    this.row = 0,
    this.col = 0,
  });

  final List<List<String>> cells;

  /// Cell that gets the keyboard first.
  final int row, col;

  static const title = 'Isi tabel';
  static const note =
      'Baris pertama: judul kolom. Kolom pertama: nilai x atau nama. '
      'Kolom lain: angka (koma desimal boleh).';
  static const cancel = 'Batal';
  static const save = 'Simpan';

  @override
  State<TableEditor> createState() => _TableEditorState();
}

class _TableEditorState extends State<TableEditor> {
  late final List<List<TextEditingController>> _fields = [
    for (final row in widget.cells)
      [for (final c in row) TextEditingController(text: c)],
  ];
  late final List<List<FocusNode>> _focus = [
    for (final row in widget.cells) [for (final _ in row) FocusNode()],
  ];

  @override
  void dispose() {
    for (final row in _fields) {
      for (final f in row) {
        f.dispose();
      }
    }
    for (final row in _focus) {
      for (final f in row) {
        f.dispose();
      }
    }
    super.dispose();
  }

  void _save() => Navigator.pop<List<List<String>>>(context, [
    for (final row in _fields) [for (final f in row) f.text.trim()],
  ]);

  @override
  Widget build(BuildContext context) {
    final rows = _fields.length, cols = _fields.first.length;
    return AlertDialog(
      title: const Text(TableEditor.title),
      content: SizedBox(
        width: 1100,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              TableEditor.note,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: AppSizes.space16),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    for (var r = 0; r < rows; r++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSizes.space8),
                        child: Row(
                          children: [
                            for (var c = 0; c < cols; c++) ...[
                              if (c > 0) const SizedBox(width: AppSizes.space8),
                              Expanded(child: _cell(r, c, rows, cols)),
                            ],
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text(TableEditor.cancel),
        ),
        FilledButton(onPressed: _save, child: const Text(TableEditor.save)),
      ],
    );
  }

  Widget _cell(int r, int c, int rows, int cols) {
    final last = r == rows - 1 && c == cols - 1;
    final field = TextField(
      key: ValueKey('sel-$r-$c'),
      controller: _fields[r][c],
      focusNode: _focus[r][c],
      autofocus: r == widget.row && c == widget.col,
      maxLength: TableItem.maxCellLength,
      // Series cells get the number keyboard; titles and column 0 text.
      keyboardType: r > 0 && c > 0
          ? const TextInputType.numberWithOptions(decimal: true, signed: true)
          : TextInputType.text,
      textInputAction: last ? TextInputAction.done : TextInputAction.next,
      onSubmitted: (_) {
        if (last) {
          _save();
        } else {
          final next = c + 1 < cols ? (r, c + 1) : (r + 1, 0);
          _focus[next.$1][next.$2].requestFocus();
        }
      },
      style: TextStyle(
        fontSize: AppSizes.textBody,
        fontWeight: r == 0 ? FontWeight.w700 : FontWeight.w400,
      ),
      decoration: InputDecoration(
        border: const OutlineInputBorder(),
        counterText: '',
        isDense: true,
        filled: r == 0,
        fillColor: AppColors.background,
        hintText: r == 0 ? 'Judul' : null,
      ),
    );
    return Semantics(
      label: r == 0 ? 'Judul kolom ${c + 1}' : 'Baris ${r + 1}, kolom ${c + 1}',
      child: field,
    );
  }
}
