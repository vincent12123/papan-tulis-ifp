import 'package:flutter/material.dart';

import '../canvas/ink_canvas.dart';
import '../canvas/ink_controller.dart';
import '../canvas/stroke.dart';
import '../peraga/peraga_specs.dart';
import '../solid/solid_geometry.dart';
import '../solid/solid_painter.dart';
import '../ui/theme.dart';

/// Where the bottom toolbar sits, so it can be reached from either side of a
/// large panel (SCR-01, A11Y-05).
enum ToolbarDock { left, center, right }

enum PenMenu { color, width, shape, peraga }

/// Icons of the Peraga menu (REQ-26–28).
const peragaIcons = <PeragaKind, IconData>{
  PeragaKind.bandul: Icons.av_timer,
  PeragaKind.parabola: Icons.sports_baseball_outlined,
  PeragaKind.pegas: Icons.waves,
  PeragaKind.bidangMiring: Icons.signal_cellular_null,
  PeragaKind.indikator: Icons.colorize_outlined,
  PeragaKind.logamAsam: Icons.bubble_chart_outlined,
  PeragaKind.pemanasan: Icons.thermostat,
  PeragaKind.pembakaran: Icons.local_fire_department_outlined,
};

/// Labels and icons of the Bentuk menu; null is Otomatis (P-07).
const shapeChoices = <({ShapeType? type, String label, IconData icon})>[
  (type: null, label: 'Otomatis', icon: Icons.auto_fix_high),
  (type: ShapeType.garis, label: 'Garis', icon: Icons.horizontal_rule),
  (type: ShapeType.persegi, label: 'Persegi', icon: Icons.crop_square),
  (type: ShapeType.lingkaran, label: 'Lingkaran', icon: Icons.circle_outlined),
  (type: ShapeType.segitiga, label: 'Segitiga', icon: Icons.change_history),
  (type: ShapeType.panah, label: 'Panah', icon: Icons.arrow_right_alt),
];

/// Bottom toolbar of SCR-01: tools, current color and width, and a button to
/// move the bar. Tools from later checkpoints are added here as they land.
class BoardToolbar extends StatelessWidget {
  const BoardToolbar({
    super.key,
    required this.ink,
    required this.tool,
    required this.dock,
    required this.openMenu,
    required this.onTool,
    required this.onMenu,
    required this.onMove,
    required this.onImage,
  });

  /// Height of the bar: a tool button plus padding.
  static const height =
      AppSizes.primaryTarget + AppSizes.space16 + AppSizes.space16;

  final InkController ink;
  final CanvasTool tool;
  final ToolbarDock dock;
  final PenMenu? openMenu;
  final ValueChanged<CanvasTool> onTool;
  final ValueChanged<PenMenu?> onMenu;
  final VoidCallback onMove;

  /// Gambar: pick a picture and insert it (an action, not a mode).
  final VoidCallback onImage;

  String get _moveLabel => switch (dock) {
    ToolbarDock.left => 'Pindahkan bilah alat ke tengah',
    ToolbarDock.center => 'Pindahkan bilah alat ke kanan',
    ToolbarDock.right => 'Pindahkan bilah alat ke kiri',
  };

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      elevation: AppSizes.elevation,
      borderRadius: BorderRadius.circular(AppSizes.radiusLarge),
      child: Padding(
        padding: const EdgeInsets.all(AppSizes.space8),
        child: ListenableBuilder(
          listenable: ink.stateRevision,
          builder: (context, _) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ToolButton(
                icon: Icons.edit,
                label: 'Pena',
                selected: tool == CanvasTool.pen,
                onTap: () => onTool(CanvasTool.pen),
              ),
              ToolButton(
                icon: Icons.backspace_outlined,
                label: 'Penghapus',
                selected: tool == CanvasTool.eraser,
                onTap: () => onTool(CanvasTool.eraser),
              ),
              ToolButton(
                icon: Icons.highlight_alt,
                label: 'Pilih',
                selected: tool == CanvasTool.select,
                onTap: () => onTool(CanvasTool.select),
              ),
              ToolButton(
                icon: Icons.category_outlined,
                label: 'Bentuk',
                selected: tool == CanvasTool.shape || openMenu == PenMenu.shape,
                onTap: () =>
                    onMenu(openMenu == PenMenu.shape ? null : PenMenu.shape),
              ),
              ToolButton(
                icon: Icons.image_outlined,
                label: 'Gambar',
                selected: false,
                onTap: onImage,
              ),
              ToolButton(
                icon: Icons.science_outlined,
                label: 'Peraga',
                selected: openMenu == PenMenu.peraga,
                onTap: () =>
                    onMenu(openMenu == PenMenu.peraga ? null : PenMenu.peraga),
              ),
              ToolButton(
                icon: Icons.pan_tool_outlined,
                label: 'Geser',
                selected: tool == CanvasTool.pan,
                onTap: () => onTool(CanvasTool.pan),
              ),
              const _Divider(),
              ToolButton(
                label: 'Warna',
                showLabel: false,
                selected: openMenu == PenMenu.color,
                onTap: () =>
                    onMenu(openMenu == PenMenu.color ? null : PenMenu.color),
                iconWidget: Container(
                  width: AppSizes.toolIcon - 4,
                  height: AppSizes.toolIcon - 4,
                  decoration: BoxDecoration(
                    color: ink.color,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.border),
                  ),
                ),
              ),
              ToolButton(
                label: 'Ketebalan',
                showLabel: false,
                selected: openMenu == PenMenu.width,
                onTap: () =>
                    onMenu(openMenu == PenMenu.width ? null : PenMenu.width),
                iconWidget: SizedBox(
                  width: AppSizes.toolIcon,
                  height: AppSizes.toolIcon,
                  child: Center(
                    child: Container(
                      width: AppSizes.toolIcon,
                      height: ink.width,
                      decoration: BoxDecoration(
                        color: AppColors.text,
                        borderRadius: BorderRadius.circular(ink.width),
                      ),
                    ),
                  ),
                ),
              ),
              const _Divider(),
              ToolButton(
                icon: Icons.swap_horiz,
                label: 'Pindah',
                showLabel: false,
                tooltip: _moveLabel,
                selected: false,
                onTap: onMove,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Palette shown above the toolbar. Picking a color or width also switches
/// back to the pen, so changing color takes 2 taps (TSK-01).
class PenMenuPanel extends StatelessWidget {
  const PenMenuPanel({
    super.key,
    required this.menu,
    required this.ink,
    required this.onPicked,
    this.shape,
    this.shapeSelected = false,
    this.onShape,
    this.onSolid,
    this.onPeraga,
    this.onQuiz,
    this.boardTheme = BoardTheme.putih,
    this.onTheme,
  });

  final PenMenu menu;
  final InkController ink;
  final VoidCallback onPicked;

  /// Current Bentuk choice (null = Otomatis) and whether Bentuk is active.
  final ShapeType? shape;
  final bool shapeSelected;
  final ValueChanged<ShapeType?>? onShape;

  /// Places a 3D solid (REQ-23); listed after the flat shapes.
  final ValueChanged<SolidKind>? onSolid;

  /// Places an alat peraga (REQ-26, REQ-28) / starts a quiz (REQ-27).
  final ValueChanged<PeragaKind>? onPeraga;
  final VoidCallback? onQuiz;

  /// Tema papan (REQ-29), chosen in the Warna menu.
  final BoardTheme boardTheme;
  final ValueChanged<BoardTheme>? onTheme;

  @override
  Widget build(BuildContext context) {
    final children = switch (menu) {
      PenMenu.peraga => const <Widget>[],
      PenMenu.shape => [
        for (final c in shapeChoices)
          ToolButton(
            icon: c.icon,
            label: c.label,
            selected: shapeSelected && shape == c.type,
            onTap: () => onShape?.call(c.type),
          ),
      ],
      PenMenu.color => [
        for (final pen in PenColors.all)
          ToolButton(
            label: pen.label,
            selected: ink.color == pen.color,
            onTap: () {
              ink.setColor(pen.color);
              onPicked();
            },
            iconWidget: Container(
              width: AppSizes.toolIcon,
              height: AppSizes.toolIcon,
              decoration: BoxDecoration(
                color: pen.color,
                shape: BoxShape.circle,
              ),
            ),
          ),
      ],
      PenMenu.width => [
        for (final w in PenWidths.all)
          ToolButton(
            label: w.label,
            selected: ink.width == w.width,
            onTap: () {
              ink.setWidth(w.width);
              onPicked();
            },
            iconWidget: SizedBox(
              width: AppSizes.toolIcon,
              height: AppSizes.toolIcon,
              child: Center(
                child: Container(
                  width: AppSizes.toolIcon,
                  height: w.width,
                  decoration: BoxDecoration(
                    color: AppColors.text,
                    borderRadius: BorderRadius.circular(w.width),
                  ),
                ),
              ),
            ),
          ),
      ],
    };
    return Material(
      color: AppColors.surface,
      elevation: AppSizes.elevation,
      borderRadius: BorderRadius.circular(AppSizes.radiusLarge),
      child: Padding(
        padding: const EdgeInsets.all(AppSizes.space8),
        child: menu == PenMenu.color && onTheme != null
            // Colors, then chalk and the board color (REQ-29).
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(mainAxisSize: MainAxisSize.min, children: children),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ToolButton(
                        label: 'Kapur',
                        icon: Icons.gesture,
                        selected: ink.chalk,
                        onTap: () => ink.setChalk(!ink.chalk),
                      ),
                      const _Divider(),
                      for (final theme in BoardTheme.values)
                        ToolButton(
                          label: 'Papan ${theme.label.toLowerCase()}',
                          selected: boardTheme == theme,
                          onTap: () => onTheme!(theme),
                          iconWidget: Container(
                            width: AppSizes.toolIcon,
                            height: AppSizes.toolIcon - 8,
                            decoration: BoxDecoration(
                              color: theme.color,
                              border: Border.all(color: AppColors.border),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              )
            : menu == PenMenu.peraga
            // Physics on top (with the quiz), chemistry below.
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final fisika in [true, false])
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final kind in PeragaKind.values)
                          if (kind.fisika == fisika)
                            ToolButton(
                              label: kind.label,
                              selected: false,
                              icon: peragaIcons[kind],
                              onTap: () => onPeraga?.call(kind),
                            ),
                        if (fisika)
                          ToolButton(
                            label: 'Kuis',
                            selected: false,
                            icon: Icons.quiz_outlined,
                            onTap: () => onQuiz?.call(),
                          ),
                      ],
                    ),
                ],
              )
            : menu == PenMenu.shape && onSolid != null
            // Flat shapes on top, solids (REQ-23) below: one row would not
            // fit a 1920-px panel.
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(mainAxisSize: MainAxisSize.min, children: children),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final kind in SolidKind.values)
                        ToolButton(
                          label: kind.label,
                          selected: false,
                          onTap: () => onSolid!(kind),
                          iconWidget: SolidIcon(kind),
                        ),
                    ],
                  ),
                ],
              )
            : Row(mainAxisSize: MainAxisSize.min, children: children),
      ),
    );
  }
}

/// A toolbar button: icon with a text label below. The active state uses a
/// container color, a border, bold text, and semantics — never color alone
/// (A11Y-02).
class ToolButton extends StatelessWidget {
  const ToolButton({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.iconWidget,
    this.tooltip,
    this.showLabel = true,
  }) : assert(icon != null || iconWidget != null);

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  final Widget? iconWidget;
  final String? tooltip;

  /// Tools keep their text; self-explaining buttons (color dot, line width,
  /// move toolbar) show the icon only, the label stays as tooltip and for
  /// screen readers (ux-flow 1.4).
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.primary : AppColors.text;
    return Semantics(
      button: true,
      selected: selected,
      label: tooltip ?? label,
      excludeSemantics: true,
      child: Tooltip(
        message: tooltip ?? label,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
          child: Container(
            constraints: const BoxConstraints(
              minWidth: AppSizes.primaryTarget + AppSizes.space16,
              minHeight: AppSizes.primaryTarget + AppSizes.space16,
            ),
            padding: const EdgeInsets.symmetric(horizontal: AppSizes.space8),
            decoration: BoxDecoration(
              color: selected ? AppColors.primaryContainer : null,
              border: Border.all(
                color: selected ? AppColors.primary : AppColors.surface,
                width: 2,
              ),
              borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                iconWidget ?? Icon(icon, size: AppSizes.toolIcon, color: color),
                if (showLabel) ...[
                  const SizedBox(height: AppSizes.space4),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: AppSizes.textBody,
                      color: color,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    height: AppSizes.primaryTarget,
    margin: const EdgeInsets.symmetric(horizontal: AppSizes.space8),
    color: AppColors.border,
  );
}
