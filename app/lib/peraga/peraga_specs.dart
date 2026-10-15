import 'dart:math' as math;

/// Alat peraga (SPEC 1.11): physics simulations (REQ-26) and virtual
/// chemistry labs (REQ-28) placed on the board. Each kind has a few
/// parameters a teacher drags, and a time-driven animation.
enum PeragaKind {
  bandul('Bandul', fisika: true),
  parabola('Gerak parabola', fisika: true),
  pegas('Pegas', fisika: true),
  bidangMiring('Bidang miring', fisika: true),
  indikator('Indikator asam-basa'),
  logamAsam('Logam + asam'),
  pemanasan('Kelarutan fenol'),
  pembakaran('Pembakaran');

  const PeragaKind(this.label, {this.fisika = false});
  final String label;
  final bool fisika;

  PeragaSpec get spec => peragaSpecs[this]!;
}

/// One slider: [name] is the key in the item's values.
class PeragaParam {
  const PeragaParam(
    this.name,
    this.label,
    this.min,
    this.max,
    this.initial, {
    this.unit = '',
    this.step = 0.1,
    this.choices,
  });

  final String name, label, unit;
  final double min, max, initial, step;

  /// A choice instead of a number (e.g. which indicator): the value is the
  /// index, shown by name.
  final List<String>? choices;

  double snap(double v) {
    final s = (v / step).round() * step;
    return double.parse(s.clamp(min, max).toStringAsFixed(4));
  }

  String show(double v) {
    final c = choices;
    if (c != null) return c[v.round().clamp(0, c.length - 1)];
    final digits = step >= 1 ? 0 : (step >= 0.1 ? 1 : 2);
    final text = v.toStringAsFixed(digits).replaceAll('.', ',');
    return unit.isEmpty ? text : '$text $unit';
  }
}

class PeragaSpec {
  const PeragaSpec(this.params, this.readout);
  final List<PeragaParam> params;

  /// What the experiment shows in numbers, for the given values.
  final String Function(Map<String, double> v) readout;

  Map<String, double> get defaults => {
    for (final p in params) p.name: p.initial,
  };
}

String _n(double v, [int digits = 2]) =>
    v.toStringAsFixed(digits).replaceAll('.', ',');

/// pH ranges at school level.
String phName(double ph) => ph < 6.5
    ? 'asam'
    : ph <= 7.5
    ? 'netral'
    : 'basa';

const indicatorNames = ['Universal', 'Lakmus', 'Fenolftalein'];
const metalNames = ['Mg', 'Zn', 'Fe', 'Cu'];

/// Relative reaction rate with a dilute acid (Cu does not react).
const metalRate = [1.0, 0.55, 0.25, 0.0];

final Map<PeragaKind, PeragaSpec> peragaSpecs = {
  PeragaKind.bandul: PeragaSpec(
    const [
      PeragaParam('L', 'Panjang tali', 0.5, 2.5, 1.2, unit: 'm'),
      PeragaParam('g', 'Gravitasi', 1.6, 24.8, 9.8, unit: 'm/s²', step: 0.2),
      PeragaParam('sudut', 'Simpangan', 5, 40, 25, unit: '°', step: 1),
    ],
    (v) =>
        'Periode T = 2π√(L/g) = ${_n(2 * math.pi * math.sqrt(v['L']! / v['g']!))} s',
  ),
  PeragaKind.parabola: PeragaSpec(
    const [
      PeragaParam('v0', 'Kecepatan awal', 5, 30, 18, unit: 'm/s', step: 1),
      PeragaParam('sudut', 'Sudut', 10, 80, 45, unit: '°', step: 1),
      PeragaParam('g', 'Gravitasi', 1.6, 24.8, 9.8, unit: 'm/s²', step: 0.2),
    ],
    (v) {
      final a = v['sudut']! * math.pi / 180;
      final v0 = v['v0']!, g = v['g']!;
      final h = v0 * v0 * math.pow(math.sin(a), 2) / (2 * g);
      final r = v0 * v0 * math.sin(2 * a) / g;
      return 'Tinggi maks ${_n(h, 1)} m · Jarak ${_n(r, 1)} m';
    },
  ),
  PeragaKind.pegas: PeragaSpec(
    const [
      PeragaParam('k', 'Konstanta pegas', 5, 100, 40, unit: 'N/m', step: 1),
      PeragaParam('m', 'Massa', 0.2, 5, 1, unit: 'kg'),
      PeragaParam('A', 'Amplitudo', 0.05, 0.3, 0.15, unit: 'm', step: 0.01),
    ],
    (v) =>
        'Periode T = 2π√(m/k) = ${_n(2 * math.pi * math.sqrt(v['m']! / v['k']!))} s',
  ),
  PeragaKind.bidangMiring: PeragaSpec(
    const [
      PeragaParam('sudut', 'Kemiringan', 5, 60, 30, unit: '°', step: 1),
      PeragaParam('mu', 'Koefisien gesek', 0, 0.8, 0.2, step: 0.05),
      PeragaParam('g', 'Gravitasi', 1.6, 24.8, 9.8, unit: 'm/s²', step: 0.2),
    ],
    (v) {
      final a = inclineAcceleration(v);
      return a <= 0
          ? 'Balok diam: tan θ ≤ μ (gesekan menahan)'
          : 'a = g(sin θ − μ cos θ) = ${_n(a)} m/s²';
    },
  ),
  PeragaKind.indikator: PeragaSpec(const [
    PeragaParam('pH', 'pH larutan', 1, 14, 3, step: 0.5),
    PeragaParam(
      'indikator',
      'Indikator',
      0,
      2,
      0,
      step: 1,
      choices: indicatorNames,
    ),
  ], (v) => 'pH ${_n(v['pH']!, 1)} → ${phName(v['pH']!)}'),
  PeragaKind.logamAsam: PeragaSpec(
    const [
      PeragaParam('logam', 'Logam', 0, 3, 0, step: 1, choices: metalNames),
      PeragaParam('M', 'Konsentrasi HCl', 0.1, 2, 1, unit: 'M'),
    ],
    (v) {
      final i = v['logam']!.round();
      return switch (i) {
        0 => 'Mg + 2HCl → MgCl₂ + H₂↑ (cepat)',
        1 => 'Zn + 2HCl → ZnCl₂ + H₂↑ (sedang)',
        2 => 'Fe + 2HCl → FeCl₂ + H₂↑ (lambat)',
        _ => 'Cu + HCl → tidak bereaksi (Cu di bawah H)',
      };
    },
  ),
  PeragaKind.pemanasan: PeragaSpec(
    const [PeragaParam('suhu', 'Suhu', 20, 90, 25, unit: '°C', step: 1)],
    (v) => v['suhu']! >= 66
        ? 'Fenol + air: larut sempurna, jernih (di atas ±66 °C)'
        : 'Fenol + air: keruh, dua lapisan (di bawah ±66 °C)',
  ),
  PeragaKind.pembakaran: PeragaSpec(
    const [
      PeragaParam('O2', 'Pasokan oksigen', 10, 100, 100, unit: '%', step: 5),
    ],
    (v) => v['O2']! >= 70
        ? 'Sempurna: CH₄ + 2O₂ → CO₂ + 2H₂O (nyala biru)'
        : 'Tidak sempurna: menghasilkan CO dan jelaga (nyala kuning)',
  ),
};

/// Down-slope acceleration on the incline; 0 when friction holds it.
double inclineAcceleration(Map<String, double> v) {
  final a = v['sudut']! * math.pi / 180;
  final acc = v['g']! * (math.sin(a) - v['mu']! * math.cos(a));
  return acc > 0 ? acc : 0;
}
