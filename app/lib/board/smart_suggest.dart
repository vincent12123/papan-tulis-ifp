import 'dart:ui';

import '../canvas/shapes.dart';
import '../canvas/stroke.dart';
import '../peraga/peraga_specs.dart';
import '../server/server_client.dart';
import '../solid/solid_geometry.dart';

/// More of the menu pintar, worked out on the panel without AI (SPEC 1.11):
/// physics formulas suggest a simulation, reactions a virtual lab, and a
/// sketched square/triangle/circle a 3D solid.

/// Peraga that fit what was recognized (REQ-26, REQ-28).
List<PeragaKind> peragaFor(FormulaInsight insight) {
  if (insight.kind == 'kimia') return labsFor(insight.formulas.join(' '));
  final text = insight.formulas.join(' ');
  bool has(String symbol) =>
      RegExp('(?<![A-Za-z\\\\])$symbol(?![a-z])').hasMatch(text);
  return [
    if (has('T') && has('L') && has('g')) PeragaKind.bandul,
    if (has('T') && has('m') && has('k')) PeragaKind.pegas,
  ];
}

const _acidsBases = {
  'HCl',
  'H2SO4',
  'HNO3',
  'CH3COOH',
  'NaOH',
  'KOH',
  'Ca(OH)2',
  'NH3',
  'NH4OH',
};
const _metals = {'Mg', 'Zn', 'Fe', 'Cu'};
const _fuels = {'CH4', 'C2H6', 'C3H8', 'C4H10', 'C2H5OH', 'C2H6O'};

/// Labs for the formulas in a reaction's LaTeX (\mathrm{H}_{2}… → H2).
List<PeragaKind> labsFor(String latex) {
  final plain = latex
      .replaceAllMapped(RegExp(r'\\mathrm\{([^}]*)\}'), (m) => m[1]!)
      .replaceAllMapped(RegExp(r'_\{(\d+)\}'), (m) => m[1]!)
      .replaceAll(RegExp(r'\\[a-zA-Z]+|[{}\s,\\]'), ' ');
  final species = plain
      .split(RegExp(r'[ +]'))
      .map((s) => s.replaceFirst(RegExp(r'^\d+'), ''))
      .where((s) => s.isNotEmpty)
      .toSet();
  final acid = species.intersection({'HCl', 'H2SO4'}).isNotEmpty;
  return [
    if (species.intersection(_metals).isNotEmpty && acid) PeragaKind.logamAsam,
    if (species.intersection(_acidsBases).isNotEmpty) PeragaKind.indikator,
    if (species.contains('C6H5OH')) PeragaKind.pemanasan,
    if (species.intersection(_fuels).isNotEmpty && species.contains('O2'))
      PeragaKind.pembakaran,
  ];
}

/// A sketched shape in a circled area that can become a solid (REQ-23).
typedef SketchHit = ({
  List<SolidKind> kinds,
  List<PageItem> source,
  Rect bounds,
});

SketchHit? sketchIn(List<PageItem> items, Rect area) {
  PageItem? best;
  ShapeType? type;
  for (final item in items) {
    if (!area.contains(item.bounds.center)) continue;
    final ShapeType? t = switch (item) {
      ShapeItem() => item.type,
      Stroke() => recognizeShape(item.points)?.type,
      _ => null,
    };
    if (t == null || t == ShapeType.garis || t == ShapeType.panah) continue;
    final size = item.bounds.width * item.bounds.height;
    final current = best;
    if (current == null ||
        size > current.bounds.width * current.bounds.height) {
      best = item;
      type = t;
    }
  }
  if (best == null) return null;
  // Only when the shape is what the circle is about, not a doodle beside
  // a formula.
  final others = items.where(
    (i) => i != best && i is Stroke && area.contains(i.bounds.center),
  );
  if (others.length > 2) return null;
  return (
    kinds: switch (type!) {
      ShapeType.persegi => const [SolidKind.kubus, SolidKind.balok],
      ShapeType.segitiga => const [SolidKind.limas, SolidKind.kerucut],
      _ => const [SolidKind.bola, SolidKind.tabung],
    },
    source: [best, ...others],
    bounds: best.bounds,
  );
}
