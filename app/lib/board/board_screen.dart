import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../ai/ai_dialog.dart';
import '../ai/area_capture.dart';
import '../ai/graph_builder.dart';
import '../canvas/ink_canvas.dart';
import '../canvas/ink_painters.dart';
import '../canvas/stroke.dart';
import '../diagnostics/device_report.dart';
import '../diagnostics/diagnostics_actions.dart';
import '../diagnostics/fps_meter.dart';
import '../canvas/media_images.dart';
import '../server/server_client.dart';
import '../ui/notices.dart';
import '../ui/theme.dart';
import 'board_document.dart';
import 'board_toolbar.dart';
import 'media_import.dart';
import 'page_panel.dart';
import 'smart_menu.dart';
import 'smart_suggest.dart';
import 'video_dialog.dart';
import '../peraga/peraga_specs.dart';
import '../peraga/quiz_editor.dart';
import '../lesson/lesson_session.dart';
import '../lesson/lesson_widgets.dart';
import '../solid/solid_geometry.dart';
import '../mandarin/mandarin_painter.dart';
import '../mandarin/mandarin_voice.dart';
import '../table/table_data.dart';
import '../table/table_editor.dart';

/// SCR-01 Papan. Opens with the pen active so writing needs no taps (TSK-01).
///
/// Checkpoint 4 adds Pilih, Bentuk, Gambar, and page backgrounds. Teks,
/// sharing, and AI arrive in later checkpoints together with their buttons.
class BoardScreen extends StatefulWidget {
  const BoardScreen({
    super.key,
    required this.doc,
    required this.onHome,
    this.importer,
    this.ai,
    this.formulas,
    this.videos,
    this.lesson,
    this.mandarin,
    this.voice,
    this.diagnostics = kDiagnostics,
    this.collectReport,
  });

  final BoardDocument doc;
  final VoidCallback onHome;

  /// Inserts pictures and backgrounds; null hides nothing but makes Gambar
  /// and Pasang latar do nothing (tests without storage).
  final MediaImporter? importer;

  /// Asisten AI (SCR-05); null hides the button (tests without a server).
  final AiRunner? ai;

  /// Menu pintar on the school server (REQ-22); null hides the bar.
  final FormulaRecognizer? formulas;

  /// School experiment videos (REQ-24); null hides the video button.
  final VideoSource? videos;

  /// Rekam kelas (REQ-25); null hides the Rekam button.
  final LessonSession? lesson;

  /// Pinyin & arti on the school server (REQ-30); null hides the button.
  final MandarinLookup? mandarin;

  /// The panel's Mandarin voice (REQ-30); null = no voice.
  final MandarinVoice? voice;

  static const pastedText =
      'Hasil AI ditempel di papan. Geser atau ubah sesuai kebutuhan.';

  // Menu pintar notices (ux-flow 1.5).
  static const graphPasted = 'Grafik ditempel di samping rumus.';
  static const tidyDone =
      'Rumus dirapikan. Tekan Undo untuk kembali ke tulisan tangan.';
  static const solveDone = 'Penyelesaian ditempel di samping persamaan.';
  static const balanceDone = 'Persamaan setara ditempel di samping reaksi.';
  static String summaryPasted(int page) =>
      'Ringkasan ditempel di halaman $page.';
  static String peragaPlaced(String name) =>
      '$name ditempel. Atur nilainya, lalu tekan Putar.';
  static const quizPlaced =
      'Kuis ditempel. Siswa mengetuk kartu kiri lalu pasangannya di kanan.';
  static const tablePlaced = 'Tabel ditempel. Ketuk sel untuk mengisinya.';
  static const mandarinPlaced =
      'Kartu pinyin & arti ditempel di samping tulisan.';
  static const mandarinUnavailable =
      'Kamus Mandarin sedang tidak tersedia. Coba lagi beberapa menit lagi.';
  static const noHanzi =
      'Tidak ada aksara Mandarin yang dikenali. Tulis lebih jelas, lalu '
      'lingkari lagi.';
  static const chartPlaced =
      'Grafik ditempel di samping tabel. Ubah angka di tabel, grafik ikut berubah.';
  static const tableNoNumbers =
      'Tabel belum berisi angka. Isi kolom kedua dan seterusnya dengan angka, '
      'lalu coba lagi.';
  static const tableLimit = 'Tabel paling banyak 20 baris dan 6 kolom.';
  static const chartNeedsNumbers =
      'Garis dan Titik butuh angka di kolom pertama.';
  static String solidFromSketch(String name) =>
      'Sketsa menjadi $name. Tekan Undo untuk kembali ke sketsa.';
  static String solidPlaced(String name) =>
      '$name ditempel. Geser jari di atasnya untuk memutar.';
  final bool diagnostics;
  final ReportCollector? collectReport;

  static const emptyHint =
      'Halaman kosong. Mulai menulis dengan jari atau stylus.';
  static String imageRejected(String name) =>
      '$name tidak bisa dipakai sebagai gambar. '
      'Pilih berkas gambar (PNG atau JPG) yang tidak rusak.';
  static String backgroundRejected(String name) =>
      '$name tidak bisa dipakai sebagai latar. '
      'Pilih berkas PDF atau gambar yang tidak rusak.';
  static String pdfLocked(String name) =>
      '$name terkunci kata sandi. Buka kuncinya dulu, lalu pilih lagi.';
  static String pdfTruncated(String name, int total) =>
      '$name punya $total halaman. Yang dipasang hanya 5 halaman pertama.';

  static const storageFullText =
      'Papan belum tersimpan karena ruang penyimpanan panel penuh. '
      'Hapus papan lama di Beranda, lalu lanjutkan menulis.';

  @override
  State<BoardScreen> createState() => _BoardScreenState();
}

class _BoardScreenState extends State<BoardScreen> {
  late final FpsMeter _fps = FpsMeter(
    isWriting: () => widget.doc.page.ink.isWriting,
  );
  final GlobalKey _canvasKey = GlobalKey();

  final ValueNotifier<CanvasTool> _tool = ValueNotifier(CanvasTool.pen);

  /// Bentuk choice; null = Otomatis.
  final ValueNotifier<ShapeType?> _shape = ValueNotifier(null);
  bool _importing = false;
  ToolbarDock _dock = ToolbarDock.center;
  PenMenu? _menu;
  bool _pagesOpen = false;

  BoardDocument get doc => widget.doc;

  @override
  void initState() {
    super.initState();
    if (widget.diagnostics) _fps.start();
    doc.queue.status.addListener(_saveStatusChanged);
    _loadTheme();
  }

  @override
  void didUpdateWidget(BoardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.doc != widget.doc) {
      oldWidget.doc.queue.status.removeListener(_saveStatusChanged);
      widget.doc.queue.status.addListener(_saveStatusChanged);
      _theme = BoardTheme.putih;
      _loadTheme();
    }
  }

  @override
  void dispose() {
    doc.queue.status.removeListener(_saveStatusChanged);
    _fps.dispose();
    _tool.dispose();
    _shape.dispose();
    super.dispose();
  }

  void _saveStatusChanged() {
    if (doc.queue.status.value == SaveStatus.storageFull && mounted) {
      Notices.failure(context, BoardScreen.storageFullText);
    }
  }

  void _moveToolbar() => setState(() {
    _dock = switch (_dock) {
      ToolbarDock.left => ToolbarDock.center,
      ToolbarDock.center => ToolbarDock.right,
      ToolbarDock.right => ToolbarDock.left,
    };
  });

  Alignment get _dockAlignment => switch (_dock) {
    ToolbarDock.left => Alignment.bottomLeft,
    ToolbarDock.center => Alignment.bottomCenter,
    ToolbarDock.right => Alignment.bottomRight,
  };

  Size _canvasSize() =>
      _canvasKey.currentContext?.size ?? MediaQuery.sizeOf(context);

  void _addPage() {
    final n = doc.addPage();
    Notices.success(context, 'Halaman $n ditambahkan.');
  }

  void _setTool(CanvasTool tool) {
    if (tool != CanvasTool.select) doc.page.ink.select(null);
    _tool.value = tool;
  }

  /// Visible part of the open page, in canvas coordinates.
  Rect _visibleArea() {
    final size = _canvasSize();
    final view = doc.page.view;
    return Rect.fromPoints(
      view.toCanvas(Offset.zero),
      view.toCanvas(Offset(size.width, size.height)),
    );
  }

  Future<void> _insertImage() async {
    final importer = widget.importer;
    if (importer == null || _importing) return;
    setState(() => _menu = null);
    _importing = true;
    try {
      final result = await importer.insertImage(_visibleArea());
      if (!mounted) return;
      switch (result) {
        case ImageInserted():
          setState(() => _tool.value = CanvasTool.select);
        case ImportRejected(:final name):
          Notices.failure(context, BoardScreen.imageRejected(name));
        default:
          break;
      }
    } finally {
      _importing = false;
    }
  }

  Future<void> _setBackground() async {
    final importer = widget.importer;
    if (importer == null || _importing) return;
    _importing = true;
    try {
      final result = await importer.setBackground(
        _visibleArea(),
        _canvasSize(),
      );
      if (!mounted) return;
      switch (result) {
        case BackgroundSet(
          :final firstPage,
          :final pageCount,
          :final name,
          :final truncatedFrom,
        ):
          final pages = pageCount == 1
              ? 'halaman $firstPage'
              : 'halaman $firstPage sampai ${firstPage + pageCount - 1}';
          if (truncatedFrom != null) {
            Notices.warning(
              context,
              'Latar terpasang di $pages. '
              '${BoardScreen.pdfTruncated(name, truncatedFrom)}',
            );
          } else {
            Notices.success(context, 'Latar terpasang di $pages.');
          }
        case ImportRejected(:final name, :final locked):
          Notices.failure(
            context,
            locked
                ? BoardScreen.pdfLocked(name)
                : BoardScreen.backgroundRejected(name),
          );
        default:
          break;
      }
    } finally {
      _importing = false;
    }
  }

  /// SCR-05: the circled area (or, for Ringkas papan, the visible page)
  /// goes to the AI; "Tempel ke papan" puts the result next to it.
  Future<void> _openAi() async {
    final runner = widget.ai;
    if (runner == null) return;
    final page = doc.page;
    final area = page.ink.area.value;
    final visible = _visibleArea();
    final result = await showDialog<AiPaste>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AiDialog(
        run: runner,
        hasArea: area != null,
        capture: () => captureArea(
          area: area ?? visible,
          items: page.ink.items,
          background: page.background,
          media: doc.images,
        ),
      ),
    );
    if (result == null || !mounted) return;
    final ink = page.ink;
    final scale = page.view.scale;
    final PageItem item;
    switch (result) {
      case PasteGraph(:final graph):
        item = graph.copyAs(ink.newId()).withRect(_graphRect(visible, area));
      case PasteText(:final text):
        final fontSize = 28 / scale;
        final width = (visible.width * 0.4).clamp(200 / scale, 900 / scale);
        final painter = TextPainter(
          text: TextSpan(
            text: text,
            style: TextStyle(fontSize: fontSize, height: 1.3),
          ),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: width);
        final rect = placeResult(Size(width, painter.height), visible, area);
        painter.dispose();
        item = TextItem(
          id: ink.newId(),
          text: text,
          rect: rect,
          fontSize: fontSize,
          color: PenColors.black,
        );
    }
    ink.clearArea();
    ink.addItem(item);
    setState(() => _tool.value = CanvasTool.select);
    ink.select(item.id);
    Notices.success(context, BoardScreen.pastedText);
  }

  /// Graph frame next to the circled area, sized to the visible page.
  Rect _graphRect(Rect visible, Rect? area) {
    final h = visible.height * 0.55;
    return placeResult(Size(h * 1.6, h), visible, area);
  }

  /// Strokes written inside [area]: what the circle is about.
  List<Stroke> _strokesIn(PageState page, Rect area) => [
    for (final item in page.ink.items)
      if (item is Stroke && area.contains(item.bounds.center)) item,
  ];

  /// PNG of the circled area plus the ink color most of it is written in.
  Future<FormulaInsight> _recognizeArea(Rect area) async {
    final recognize = widget.formulas;
    final page = doc.page;
    if (recognize == null) throw const ServerError();
    final png = await captureArea(
      area: area,
      items: page.ink.items,
      background: page.background,
      media: doc.images,
    );
    if (png == null) throw const ServerError();
    final counts = <Color, int>{};
    void note(FormulaInsight insight) =>
        widget.lesson?.noteFormulas(insight.formulas);
    for (final s in _strokesIn(page, area)) {
      counts[s.color] = (counts[s.color] ?? 0) + s.points.length;
    }
    final ink = counts.isEmpty
        ? PenColors.black
        : counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
    final hex = (ink.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0');
    final insight = await recognize(png, '#${hex.toUpperCase()}');
    note(insight);
    return insight;
  }

  void _finish(PageItem item, String notice) {
    final ink = doc.page.ink;
    ink.clearArea();
    setState(() => _tool.value = CanvasTool.select);
    ink.select(item.id);
    Notices.success(context, notice);
  }

  void _placeGraph(Rect area, FormulaInsight insight) {
    final data = insight.graph;
    final ink = doc.page.ink;
    final graph = data == null
        ? null
        : buildGraph(data, _graphRect(_visibleArea(), area), ink.newId());
    if (graph == null) {
      Notices.failure(context, SmartAreaBar.noFormula);
      return;
    }
    ink.addItem(graph);
    _finish(graph, BoardScreen.graphPasted);
  }

  /// Saves a typeset picture with the board's media.
  Future<String?> _store(TypesetImage picture) async {
    final media = doc.media;
    if (media == null) return null;
    final name = await media.save(picture.png, 'png');
    doc.images.put(name, await decodeImage(picture.png));
    return name;
  }

  /// Size the typeset formula like the handwriting it replaces.
  double _typesetScale(Rect written, FormulaInsight insight) => math.min(
    written.width / insight.tidy.size.width,
    written.height / insight.tidy.size.height,
  );

  Rect _written(PageState page, Rect area) {
    final strokes = _strokesIn(page, area);
    if (strokes.isEmpty) return area;
    return strokes.map((s) => s.bounds).reduce((a, b) => a.expandToInclude(b));
  }

  Future<void> _tidy(Rect area, FormulaInsight insight) async {
    final page = doc.page;
    final name = await _store(insight.tidy);
    if (!mounted) return;
    if (name == null) {
      Notices.failure(context, SmartAreaBar.unavailable);
      return;
    }
    final written = _written(page, area);
    final scale = _typesetScale(written, insight);
    final size = insight.tidy.size * scale;
    final rect = Rect.fromLTWH(
      written.left,
      written.center.dy - size.height / 2,
      size.width,
      size.height,
    );
    final item = ImageItem(id: page.ink.newId(), file: name, rect: rect);
    page.ink.replaceItems(_strokesIn(page, area), [item]);
    _finish(item, BoardScreen.tidyDone);
  }

  Future<void> _solve(Rect area, FormulaInsight insight) async {
    final solution = insight.solution;
    if (solution == null) return;
    final page = doc.page;
    final name = await _store(solution);
    if (!mounted) return;
    if (name == null) {
      Notices.failure(context, SmartAreaBar.unavailable);
      return;
    }
    final scale = _typesetScale(_written(page, area), insight);
    final rect = placeResult(solution.size * scale, _visibleArea(), area);
    final item = ImageItem(id: page.ink.newId(), file: name, rect: rect);
    page.ink.addItem(item);
    _finish(
      item,
      insight.kind == 'kimia' ? BoardScreen.balanceDone : BoardScreen.solveDone,
    );
  }

  /// Bangun ruang (REQ-23) in the middle of the visible page. The tool
  /// stays one that turns it with a finger (not Pilih or Geser).
  void _placeSolid(SolidKind kind) {
    final visible = _visibleArea();
    final h = visible.height * 0.55;
    final rect = Rect.fromCenter(
      center: visible.center,
      width: h * 1.1,
      height: h,
    );
    final ink = doc.page.ink;
    ink.addItem(SolidItem(id: ink.newId(), kind: kind, rect: rect));
    setState(() {
      _menu = null;
      if (_tool.value == CanvasTool.select || _tool.value == CanvasTool.pan) {
        _setTool(CanvasTool.pen);
      }
    });
    Notices.success(context, BoardScreen.solidPlaced(kind.label));
  }

  Future<void> _startLesson() async {
    final lesson = widget.lesson;
    if (lesson == null || !await confirmLessonRecording(context)) return;
    final error = await lesson.start();
    if (error != null && mounted) Notices.failure(context, error);
  }

  Future<void> _openLesson() async {
    final lesson = widget.lesson;
    if (lesson == null) return;
    final choice = await showDialog<LessonChoice>(
      context: context,
      builder: (_) => LessonResultDialog(session: lesson),
    );
    if (!mounted) return;
    switch (choice) {
      case LessonChoice.paste:
        final text = lesson.summary;
        await lesson.reset();
        if (text != null && mounted) _pasteSummary(text);
      case LessonChoice.retry:
        await lesson.retry();
      case LessonChoice.discard:
        await lesson.reset();
      case null:
        break;
    }
  }

  /// The lesson summary goes on a new page after the open one.
  void _pasteSummary(String text) {
    final n = doc.addPage();
    final page = doc.page;
    final visible = _visibleArea();
    final scale = page.view.scale;
    final fontSize = 28 / scale;
    final width = visible.width * 0.7;
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(fontSize: fontSize, height: 1.3),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: width);
    final rect = Rect.fromLTWH(
      visible.left + visible.width * 0.15,
      visible.top + 48 / scale,
      width,
      painter.height,
    );
    painter.dispose();
    page.ink.addItem(
      TextItem(
        id: page.ink.newId(),
        text: text,
        rect: rect,
        fontSize: fontSize,
        color: PenColors.black,
      ),
    );
    setState(() {});
    Notices.success(context, BoardScreen.summaryPasted(n));
  }

  /// Alat peraga (REQ-26, REQ-28) in the middle of the visible page; the
  /// tool stays one that lets its buttons and sliders work at once.
  void _placePeraga(PeragaKind kind) {
    final visible = _visibleArea();
    final h = visible.height * 0.66;
    final rect = Rect.fromCenter(
      center: visible.center,
      width: h * 1.05,
      height: h,
    );
    final ink = doc.page.ink;
    ink.addItem(PeragaItem(id: ink.newId(), kind: kind, rect: rect));
    setState(() {
      _menu = null;
      if (_tool.value == CanvasTool.select || _tool.value == CanvasTool.pan) {
        _setTool(CanvasTool.pen);
      }
    });
    Notices.success(context, BoardScreen.peragaPlaced(kind.label));
  }

  BoardTheme _theme = BoardTheme.putih;

  String get _themeKey => 'tema:${doc.id}';

  Future<void> _loadTheme() async {
    final saved = await doc.repo.appState(_themeKey);
    final theme = BoardTheme.values.where((t) => t.name == saved);
    if (theme.isNotEmpty && mounted) setState(() => _theme = theme.first);
  }

  /// Tema papan (REQ-29); the pen follows so writing stays visible.
  void _setTheme(BoardTheme theme) {
    final ink = doc.page.ink;
    if (theme.dark && ink.color == PenColors.black) {
      ink.setColor(PenColors.white);
    }
    if (!theme.dark && ink.color == PenColors.white) {
      ink.setColor(PenColors.black);
    }
    setState(() {
      _theme = theme;
      _menu = null;
    });
    doc.queue.run(() => doc.repo.setAppState(_themeKey, theme.name));
  }

  /// A simulation or lab the circled formulas suggest, beside them.
  void _peragaBeside(Rect area, PeragaKind kind) {
    final visible = _visibleArea();
    final h = visible.height * 0.66;
    final rect = placeResult(Size(h * 1.05, h), visible, area);
    final ink = doc.page.ink;
    final item = PeragaItem(id: ink.newId(), kind: kind, rect: rect);
    ink.addItem(item);
    ink.clearArea();
    Notices.success(context, BoardScreen.peragaPlaced(kind.label));
  }

  /// A sketched square/triangle/circle becomes a solid in its place
  /// (REQ-23); one Undo brings the sketch back.
  void _sketchToSolid(SketchHit sketch, SolidKind kind) {
    final scale = doc.page.view.scale;
    final h = math.max(sketch.bounds.height * 1.5, 320 / scale);
    final rect = Rect.fromCenter(
      center: sketch.bounds.center,
      width: h * 1.1,
      height: h,
    );
    final ink = doc.page.ink;
    final solid = SolidItem(id: ink.newId(), kind: kind, rect: rect);
    ink.replaceItems(sketch.source, [solid]);
    ink.clearArea();
    Notices.success(context, BoardScreen.solidFromSketch(kind.label));
  }

  /// Kuis (REQ-27): the teacher writes the pairs (or lets the AI suggest
  /// them from the page), then students match them at the board.
  /// Tabel (REQ-21): an empty table in the middle of the visible page, big
  /// enough that its text reads at least 20 sp on screen.
  Future<void> _newTable() async {
    setState(() => _menu = null);
    final size = await showDialog<(int, int)>(
      context: context,
      builder: (_) => const TableSizeDialog(),
    );
    if (size == null || !mounted) return;
    final (rows, cols) = size;
    final scale = doc.page.view.scale;
    final rect = Rect.fromCenter(
      center: _visibleArea().center,
      width: cols * 200 / scale,
      height: rows * 64 / scale,
    );
    final ink = doc.page.ink;
    ink.addItem(
      TableItem(
        id: ink.newId(),
        rect: rect,
        cells: TableItem.blank(rows, cols),
      ),
    );
    setState(() {
      // Tapping a cell fills it with any tool but Pilih and Geser.
      if (_tool.value == CanvasTool.select || _tool.value == CanvasTool.pan) {
        _setTool(CanvasTool.pen);
      }
    });
    Notices.success(context, BoardScreen.tablePlaced);
  }

  Future<void> _editTable(TableItem table, int row, int col) async {
    final cells = await showDialog<List<List<String>>>(
      context: context,
      builder: (_) => TableEditor(cells: table.cells, row: row, col: col),
    );
    if (cells == null || !mounted) return;
    doc.page.ink.updateTable(table.id, cells);
  }

  void _growTable(TableItem table, {required bool row}) {
    final r = table.rect;
    final full = row
        ? table.rows >= TableItem.maxRows
        : table.cols >= TableItem.maxCols;
    if (full) {
      Notices.failure(context, BoardScreen.tableLimit);
      return;
    }
    doc.page.ink.updateTable(
      table.id,
      row
          ? [...table.cells, List.filled(table.cols, '')]
          : [
              for (final cells in table.cells) [...cells, ''],
            ],
      rect: row
          ? Rect.fromLTWH(
              r.left,
              r.top,
              r.width,
              r.height + r.height / table.rows,
            )
          : Rect.fromLTWH(
              r.left,
              r.top,
              r.width + r.width / table.cols,
              r.height,
            ),
    );
  }

  /// Jadikan grafik from a table: drawn on the panel, no server (AC-185).
  void _chartFromTable(TableItem table, ChartKind kind) {
    final data = TableData(table.cells);
    if (!data.hasNumbers) {
      Notices.failure(context, BoardScreen.tableNoNumbers);
      return;
    }
    if (!data.allowedKinds.contains(kind)) {
      Notices.failure(context, BoardScreen.chartNeedsNumbers);
      return;
    }
    final rect = _besideTable(table.rect);
    final ink = doc.page.ink;
    final chart = ChartItem(
      id: ink.newId(),
      rect: rect,
      kind: kind,
      tableId: table.id,
      cells: table.cells,
    );
    ink.addItem(chart);
    ink.select(chart.id);
    Notices.success(context, BoardScreen.chartPlaced);
  }

  /// Pinyin & arti (REQ-30): asks the school server for the circled Hanzi
  /// and pastes a card beside the writing. The board is left as it was on
  /// any failure.
  Future<void> _mandarinCard(Rect area, FormulaInsight insight) async {
    final lookup = widget.mandarin;
    final text = insight.hanzi;
    if (lookup == null || text == null) return;
    final MandarinReading reading;
    try {
      reading = await lookup(text);
    } on ServerFailure catch (f) {
      if (!mounted) return;
      Notices.failure(context, switch (f) {
        ServerUnreachable() => SmartAreaBar.offline,
        PinRejected() || PinNotSetOnServer() => SmartAreaBar.notAllowed,
        PinLocked() => SmartAreaBar.locked,
        ServerValidation() || NoFormulaFound() => BoardScreen.noHanzi,
        _ => BoardScreen.mandarinUnavailable,
      });
      return;
    }
    if (!mounted) return;
    final ink = doc.page.ink;
    final card = MandarinItem(
      id: ink.newId(),
      rect: Rect.zero,
      hanzi: reading.hanzi,
      pinyin: reading.pinyin,
      translation: reading.translation,
      words: [
        for (final w in reading.words.take(MandarinItem.maxWords))
          (
            hanzi: w.hanzi,
            pinyin: w.pinyin,
            meaning: w.meaning,
            source: w.source,
          ),
      ],
    );
    final visible = _visibleArea();
    final width = math.min(visible.width * 0.42, 760 / doc.page.view.scale);
    final rect = placeResult(
      Size(width, MandarinLayout.heightFor(card, width)),
      visible,
      area,
    );
    final placed = card.withRect(rect);
    ink.addItem(placed);
    ink.clearArea();
    Notices.success(context, BoardScreen.mandarinPlaced);
  }

  /// A chart frame next to the table, on the side with more room, sized to
  /// fit the visible page (never on top of the table).
  Rect _besideTable(Rect table) {
    final visible = _visibleArea();
    final gap = 24 / doc.page.view.scale;
    final rightRoom = visible.right - table.right - gap * 2;
    final leftRoom = table.left - visible.left - gap * 2;
    final room = math.max(rightRoom, leftRoom);
    final minW = 480 / doc.page.view.scale;
    var w = math.min(visible.height * 0.75, math.max(room, minW));
    var h = w / 1.5;
    if (h > visible.height - gap * 2) {
      h = visible.height - gap * 2;
      w = h * 1.5;
    }
    final top = table.top.clamp(visible.top + gap, visible.bottom - gap - h);
    final left = rightRoom >= leftRoom || room < minW
        ? table.right + gap
        : table.left - gap - w;
    return Rect.fromLTWH(left, top.toDouble(), w, h);
  }

  Future<void> _newQuiz() async {
    setState(() => _menu = null);
    final runner = widget.ai;
    final quiz = await showDialog<QuizDraft>(
      context: context,
      builder: (_) => QuizEditor(
        suggest: runner == null
            ? null
            : () async {
                final page = doc.page;
                final png = await captureArea(
                  area: _visibleArea(),
                  items: page.ink.items,
                  background: page.background,
                  media: doc.images,
                );
                if (png == null) throw const ServerError();
                return (await runner('kuis', png)).quiz;
              },
      ),
    );
    if (quiz == null || !mounted) return;
    final visible = _visibleArea();
    final h = visible.height * (0.32 + 0.07 * quiz.pairs.length);
    final rect = Rect.fromCenter(
      center: visible.center,
      width: visible.height * 0.95,
      height: h,
    );
    final ink = doc.page.ink;
    ink.addItem(
      QuizItem(
        id: ink.newId(),
        rect: rect,
        title: quiz.title,
        pairs: quiz.pairs,
      ),
    );
    setState(() {
      if (_tool.value == CanvasTool.select || _tool.value == CanvasTool.pan) {
        _setTool(CanvasTool.pen);
      }
    });
    Notices.success(context, BoardScreen.quizPlaced);
  }

  void _removeBackground() {
    final n = doc.current.value + 1;
    doc.setBackground(n - 1, null);
    Notices.success(context, 'Latar halaman $n dilepas.');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: Listenable.merge([doc.current, doc.pagesRevision]),
          builder: (context, _) {
            final page = doc.page;
            return Column(
              children: [
                _TopBar(
                  doc: doc,
                  onHome: widget.onHome,
                  onAi: widget.ai == null ? null : _openAi,
                  lesson: widget.lesson == null
                      ? null
                      : LessonButton(
                          session: widget.lesson!,
                          onStart: _startLesson,
                          onOpen: _openLesson,
                        ),
                  trailing: widget.diagnostics
                      ? DiagnosticsActions(
                          ink: page.ink,
                          fps: _fps,
                          canvasSize: _canvasSize,
                          collectReport:
                              widget.collectReport ?? DeviceReport.collect,
                        )
                      : null,
                ),
                Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: KeyedSubtree(
                          key: _canvasKey,
                          // Touching the canvas (only the canvas, not the
                          // menu itself) closes an open menu; the touch
                          // still writes.
                          child: Listener(
                            behavior: HitTestBehavior.translucent,
                            onPointerDown: (_) {
                              if (_menu != null) setState(() => _menu = null);
                            },
                            child: InkCanvas(
                              controller: page.ink,
                              viewport: page.view,
                              tool: _tool,
                              shape: _shape,
                              media: doc.images,
                              color: _theme.color,
                              onTableCell: _editTable,
                              onSpeak: (text, slow) =>
                                  widget.voice?.speak(text, slow: slow),
                              target: () =>
                                  (ink: doc.page.ink, view: doc.page.view),
                            ),
                          ),
                        ),
                      ),
                      Positioned.fill(child: _EmptyHint(page: page)),
                      // "◀ Hlm 2/5 ▶ [＋]" sits at the left, just above the
                      // toolbar row (SCR-01 wireframe); an open color menu
                      // is drawn over it.
                      Positioned(
                        left: AppSizes.space16,
                        bottom:
                            AppSizes.space16 +
                            BoardToolbar.height +
                            AppSizes.space8,
                        child: _PageNav(
                          doc: doc,
                          onOpenPanel: () =>
                              setState(() => _pagesOpen = !_pagesOpen),
                          onAdd: _addPage,
                        ),
                      ),
                      Positioned.fill(
                        child: _SelectionActions(
                          page: page,
                          tool: _tool,
                          onAddRow: (t) => _growTable(t, row: true),
                          onAddColumn: (t) => _growTable(t, row: false),
                          onChart: _chartFromTable,
                        ),
                      ),
                      if (widget.formulas != null)
                        Positioned.fill(
                          child: SmartAreaBar(
                            page: page,
                            recognize: _recognizeArea,
                            sketch: (area) => sketchIn(page.ink.items, area),
                            actions: SmartActions(
                              onGraph: _placeGraph,
                              onTidy: _tidy,
                              onSolve: (a, i) => _solve(a, i),
                              onMandarin: widget.mandarin == null
                                  ? null
                                  : _mandarinCard,
                              onPeraga: _peragaBeside,
                              onSketch: _sketchToSolid,
                              onVideo: widget.videos == null
                                  ? null
                                  : (insight) => showDialog<void>(
                                      context: context,
                                      builder: (_) => VideoDialog(
                                        videos: insight.videos,
                                        source: widget.videos!,
                                      ),
                                    ),
                            ),
                          ),
                        ),
                      Positioned.fill(child: _bottomControls()),
                      if (_pagesOpen)
                        Positioned(
                          left: 0,
                          top: 0,
                          bottom: 0,
                          child: PagePanel(
                            doc: doc,
                            screen: MediaQuery.sizeOf(context),
                            onClose: () => setState(() => _pagesOpen = false),
                            onSetBackground: _setBackground,
                            onRemoveBackground: _removeBackground,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _bottomControls() {
    return Padding(
      padding: const EdgeInsets.all(AppSizes.space16),
      child: Align(
        alignment: _dockAlignment,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: switch (_dock) {
            ToolbarDock.left => CrossAxisAlignment.start,
            ToolbarDock.center => CrossAxisAlignment.center,
            ToolbarDock.right => CrossAxisAlignment.end,
          },
          children: [
            if (_menu != null) ...[
              PenMenuPanel(
                menu: _menu!,
                ink: doc.page.ink,
                shape: _shape.value,
                shapeSelected: _tool.value == CanvasTool.shape,
                onPicked: () => setState(() {
                  _menu = null;
                  // Color/width apply to the shape tool too; otherwise pen.
                  if (_tool.value != CanvasTool.shape) _setTool(CanvasTool.pen);
                }),
                onShape: (type) => setState(() {
                  _menu = null;
                  _shape.value = type;
                  _setTool(CanvasTool.shape);
                }),
                onSolid: _placeSolid,
                onPeraga: _placePeraga,
                onQuiz: _newQuiz,
                boardTheme: _theme,
                onTheme: _setTheme,
              ),
              const SizedBox(height: AppSizes.space8),
            ],
            BoardToolbar(
              ink: doc.page.ink,
              tool: _tool.value,
              dock: _dock,
              openMenu: _menu,
              onTool: (t) => setState(() {
                _setTool(t);
                _menu = null;
              }),
              onMenu: (m) => setState(() => _menu = m),
              onMove: _moveToolbar,
              onImage: _insertImage,
              onTable: _newTable,
            ),
          ],
        ),
      ),
    );
  }
}

/// "◀ Hlm 2/5 ▶ [＋]" above the toolbar (SCR-01): add a page in 1 tap, change
/// page in ≤ 2 taps (TSK-06).
class _PageNav extends StatelessWidget {
  const _PageNav({
    required this.doc,
    required this.onOpenPanel,
    required this.onAdd,
  });

  final BoardDocument doc;
  final VoidCallback onOpenPanel;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final i = doc.current.value;
    final n = doc.pages.length;
    return Material(
      color: AppColors.surface,
      elevation: AppSizes.elevation,
      borderRadius: BorderRadius.circular(AppSizes.radiusLarge),
      child: Padding(
        padding: const EdgeInsets.all(AppSizes.space4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Halaman sebelumnya',
              onPressed: i > 0 ? () => doc.goTo(i - 1) : null,
              icon: const Icon(Icons.chevron_left),
            ),
            Tooltip(
              message: 'Buka panel Halaman',
              child: TextButton(
                onPressed: onOpenPanel,
                child: Text('Hlm ${i + 1}/$n'),
              ),
            ),
            IconButton(
              tooltip: 'Halaman berikutnya',
              onPressed: i < n - 1 ? () => doc.goTo(i + 1) : null,
              icon: const Icon(Icons.chevron_right),
            ),
            IconButton(
              tooltip: 'Halaman baru',
              onPressed: onAdd,
              icon: const Icon(Icons.add),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.doc,
    required this.onHome,
    this.onAi,
    this.lesson,
    this.trailing,
  });

  final BoardDocument doc;
  final VoidCallback onHome;
  final VoidCallback? onAi;
  final Widget? lesson;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final ink = doc.page.ink;
    return Material(
      color: AppColors.surface,
      elevation: AppSizes.elevation,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSizes.space8,
          vertical: AppSizes.space4,
        ),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Beranda',
              onPressed: onHome,
              icon: const Icon(Icons.menu),
            ),
            const SizedBox(width: AppSizes.space8),
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: ValueListenableBuilder(
                      valueListenable: doc.title,
                      builder: (context, title, _) => Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  // Page number lives in the page control (ux-flow 1.4).
                  const SizedBox(width: AppSizes.space16),
                  Flexible(child: _SaveIndicator(status: doc.queue.status)),
                ],
              ),
            ),
            if (trailing != null) ...[
              Flexible(flex: 3, child: trailing!),
              const SizedBox(width: AppSizes.space16),
            ],
            if (lesson != null) ...[
              lesson!,
              const SizedBox(width: AppSizes.space8),
            ],
            if (onAi != null) ...[
              FilledButton.tonalIcon(
                onPressed: onAi,
                icon: const Icon(Icons.auto_awesome),
                label: const Text('Asisten AI'),
              ),
              const SizedBox(width: AppSizes.space8),
            ],
            ListenableBuilder(
              listenable: ink.stateRevision,
              builder: (context, _) => Row(
                children: [
                  IconButton(
                    tooltip: 'Undo',
                    onPressed: ink.canUndo ? ink.undo : null,
                    icon: const Icon(Icons.undo),
                  ),
                  IconButton(
                    tooltip: 'Redo',
                    onPressed: ink.canRedo ? ink.redo : null,
                    icon: const Icon(Icons.redo),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Save status (SCR-01 Berhasil, ux-flow 1.4): a quiet cloud icon when
/// saved ("Tersimpan" as tooltip and for screen readers), text only while
/// saving or when saving failed. Never blocks writing.
class _SaveIndicator extends StatelessWidget {
  const _SaveIndicator({required this.status});

  final ValueNotifier<SaveStatus> status;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: status,
      builder: (context, value, _) {
        if (value == SaveStatus.saved) {
          return Tooltip(
            message: 'Tersimpan',
            child: Semantics(
              label: 'Tersimpan',
              excludeSemantics: true,
              child: const Icon(
                Icons.cloud_done_outlined,
                color: AppColors.textMuted,
              ),
            ),
          );
        }
        final (text, color) = switch (value) {
          SaveStatus.storageFull ||
          SaveStatus.failed => ('Belum tersimpan', AppColors.danger),
          _ => ('Menyimpan…', AppColors.textMuted),
        };
        return Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: AppSizes.textBody, color: color),
        );
      },
    );
  }
}

/// Faint hint in the middle of an empty page; gone after the first stroke.
/// Ignores pointers so it never blocks writing.
class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.page});

  final PageState page;

  @override
  Widget build(BuildContext context) {
    final ink = page.ink;
    return IgnorePointer(
      child: ListenableBuilder(
        listenable: Listenable.merge([
          ink.committedRevision,
          ink.activeRevision,
          ink.background,
        ]),
        builder: (context, _) => ink.isEmpty && ink.background.value == null
            ? Center(
                child: Text(
                  BoardScreen.emptyHint,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              )
            : const SizedBox.shrink(),
      ),
    );
  }
}

/// "Hapus" next to the item selected with Pilih (REQ-07, REQ-08).
class _SelectionActions extends StatelessWidget {
  const _SelectionActions({
    required this.page,
    required this.tool,
    required this.onAddRow,
    required this.onAddColumn,
    required this.onChart,
  });

  final PageState page;
  final ValueListenable<CanvasTool> tool;

  /// Table buttons (REQ-21).
  final ValueChanged<TableItem> onAddRow, onAddColumn;
  final void Function(TableItem table, ChartKind kind) onChart;

  @override
  Widget build(BuildContext context) {
    final ink = page.ink;
    return ListenableBuilder(
      listenable: Listenable.merge([
        ink.selected,
        ink.activeRevision,
        page.view.revision,
        tool,
      ]),
      builder: (context, _) {
        final item = ink.selectedItem;
        if (item == null ||
            tool.value != CanvasTool.select ||
            ink.transformPreview != null) {
          return const SizedBox.shrink();
        }
        final frame = selectionFrame(ink, page.view, item);
        final delete = FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
          onPressed: ink.deleteSelected,
          icon: const Icon(Icons.delete_outline),
          label: const Text('Hapus'),
        );
        return Stack(
          children: [
            if (item is TableItem)
              // Under the table (above it when it sits low), so the buttons
              // never cover a chart placed beside it.
              Positioned(
                left: frame.left,
                top:
                    frame.bottom + 120 < MediaQuery.sizeOf(context).height - 200
                    ? frame.bottom + AppSizes.space24
                    : null,
                bottom:
                    frame.bottom + 120 < MediaQuery.sizeOf(context).height - 200
                    ? null
                    : MediaQuery.sizeOf(context).height -
                          frame.top +
                          AppSizes.space24,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: math.max(frame.width, 360),
                  ),
                  child: Wrap(
                    spacing: AppSizes.space8,
                    runSpacing: AppSizes.space8,
                    children: [
                      _TableChartButton(
                        table: item,
                        onChart: (kind) => onChart(item, kind),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => onAddRow(item),
                        icon: const Icon(Icons.table_rows_outlined),
                        label: const Text('Tambah baris'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => onAddColumn(item),
                        icon: const Icon(Icons.view_column_outlined),
                        label: const Text('Tambah kolom'),
                      ),
                      delete,
                    ],
                  ),
                ),
              )
            else
              Positioned(
                left: frame.right + AppSizes.space16,
                top: frame.top,
                child: delete,
              ),
          ],
        );
      },
    );
  }
}

/// "Jadikan grafik" on a selected table, then Garis / Batang / Titik
/// (REQ-21). Garis and Titik are off while column 0 holds text.
class _TableChartButton extends StatelessWidget {
  const _TableChartButton({required this.table, required this.onChart});

  final TableItem table;
  final ValueChanged<ChartKind> onChart;

  @override
  Widget build(BuildContext context) {
    final data = TableData(table.cells);
    final allowed = data.allowedKinds;
    return MenuAnchor(
      menuChildren: [
        for (final kind in ChartKind.values)
          MenuItemButton(
            onPressed: allowed.contains(kind) ? () => onChart(kind) : null,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: AppSizes.target),
              child: Align(
                alignment: Alignment.centerLeft,
                widthFactor: 1,
                child: Text(
                  kind.label,
                  style: const TextStyle(fontSize: AppSizes.textBody),
                ),
              ),
            ),
          ),
        if (!allowed.contains(ChartKind.garis))
          Padding(
            padding: const EdgeInsets.all(AppSizes.space12),
            child: Text(
              BoardScreen.chartNeedsNumbers,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
      ],
      builder: (context, menu, _) => FilledButton.icon(
        onPressed: () {
          if (!data.hasNumbers) {
            Notices.failure(context, BoardScreen.tableNoNumbers);
          } else if (menu.isOpen) {
            menu.close();
          } else {
            menu.open();
          }
        },
        icon: const Icon(Icons.insert_chart_outlined),
        label: const Text('Jadikan grafik'),
      ),
    );
  }
}
