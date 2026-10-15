import 'dart:math' as math;

/// Bangun ruang (SPEC 1.9, REQ-23): the solids a teacher can place, their
/// faces in 3D, how each face hinges open into a net, and the cut plane.
/// Pure math, no Flutter, so it is easy to test.
enum SolidKind {
  kubus('Kubus'),
  balok('Balok'),
  prisma('Prisma'),
  limas('Limas'),
  tabung('Tabung'),
  kerucut('Kerucut'),
  bola('Bola');

  const SolidKind(this.label);
  final String label;

  /// A sphere has no net.
  bool get hasNet => this != SolidKind.bola;
}

class Vec3 {
  const Vec3(this.x, this.y, this.z);
  final double x, y, z;

  Vec3 operator +(Vec3 o) => Vec3(x + o.x, y + o.y, z + o.z);
  Vec3 operator -(Vec3 o) => Vec3(x - o.x, y - o.y, z - o.z);
  Vec3 operator *(double k) => Vec3(x * k, y * k, z * k);
  double dot(Vec3 o) => x * o.x + y * o.y + z * o.z;
  Vec3 cross(Vec3 o) =>
      Vec3(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x);
  double get length => math.sqrt(dot(this));
  Vec3 get unit => this * (1 / length);

  /// Rotated by [angle] around the line through [a] with direction [axis]
  /// (unit vector), right-hand rule (Rodrigues).
  Vec3 rotateAround(Vec3 a, Vec3 axis, double angle) {
    final p = this - a;
    final c = math.cos(angle), s = math.sin(angle);
    final r = p * c + axis.cross(p) * s + axis * (axis.dot(p) * (1 - c));
    return r + a;
  }

  @override
  String toString() =>
      '(${x.toStringAsFixed(3)}, ${y.toStringAsFixed(3)}, ${z.toStringAsFixed(3)})';
}

/// One flat face. Vertices run counter-clockwise seen from outside, so
/// [normal] points outward. [hinge] is the edge (two vertex indices of this
/// face) it turns around when the net opens; it lies on the [parent] face.
class Face {
  Face(this.points, {this.parent, this.hinge, this.smoothEdges = const {}});

  final List<Vec3> points;
  final int? parent;
  final (int, int)? hinge;

  /// Edge indices i (edge points[i] → points[i+1]) that are not real edges
  /// but facets of a curved surface: drawn only on the outline.
  final Set<int> smoothEdges;

  Vec3 get normal {
    final n = (points[1] - points[0]).cross(points[2] - points[0]);
    return n.unit;
  }

  Vec3 get centroid {
    var c = const Vec3(0, 0, 0);
    for (final p in points) {
      c = c + p;
    }
    return c * (1 / points.length);
  }
}

class Solid {
  Solid(this.kind, this.faces, this.labels, this.cut);

  final SolidKind kind;
  final List<Face> faces;

  /// Named corners (A, B, …) shown on polyhedra.
  final Map<String, Vec3> labels;

  /// The cut plane polygon (bidang potong) inside the closed solid.
  final List<Vec3> cut;

  /// Faces with the net opened by [t] (0 = closed solid, 1 = flat net).
  List<List<Vec3>> unfolded(double t) {
    if (t <= 0 || !kind.hasNet) return [for (final f in faces) f.points];
    final out = List<List<Vec3>?>.filled(faces.length, null);
    List<Vec3> place(int i) {
      final done = out[i];
      if (done != null) return done;
      final face = faces[i];
      final parent = face.parent;
      final hinge = face.hinge;
      if (parent == null || hinge == null) return out[i] = face.points;
      final a = face.points[hinge.$1], b = face.points[hinge.$2];
      final axis = (b - a).unit;
      final angle = _flatAngle(face, faces[parent], a, axis) * t;
      final local = [
        for (final p in face.points) p.rotateAround(a, axis, angle),
      ];
      // Then follow the parent as it opens (its own hinge chain).
      final moved = _carry(parent, local, place);
      return out[i] = moved;
    }

    for (var i = 0; i < faces.length; i++) {
      place(i);
    }
    return [for (final f in out) f!];
  }

  /// Moves [points] (attached to face [i]) the way face i moves.
  List<Vec3> _carry(int i, List<Vec3> points, List<Vec3> Function(int) place) {
    final from = faces[i].points;
    final to = place(i);
    // Rigid motion of face i: from its folded frame to its placed frame.
    final f0 = _frame(from), f1 = _frame(to);
    return [for (final p in points) _fromFrame(f1, _toFrame(f0, p))];
  }

  /// Rotation that turns [face] around its hinge until it lies in its
  /// parent's plane, on the outside.
  static double _flatAngle(Face face, Face parent, Vec3 a, Vec3 axis) {
    final target = parent.normal;
    final n = face.normal;
    final cosA = n.dot(target).clamp(-1.0, 1.0);
    final angle = math.acos(cosA);
    // Pick the direction that makes the normal match the parent's.
    final turned = n.rotateAround(const Vec3(0, 0, 0), axis, angle);
    return turned.dot(target) > 0.999 ? angle : -angle;
  }

  static (Vec3, Vec3, Vec3, Vec3) _frame(List<Vec3> pts) {
    final o = pts[0];
    final u = (pts[1] - pts[0]).unit;
    final w = u.cross(pts[2] - pts[0]).unit;
    final v = w.cross(u);
    return (o, u, v, w);
  }

  static Vec3 _toFrame((Vec3, Vec3, Vec3, Vec3) f, Vec3 p) {
    final d = p - f.$1;
    return Vec3(d.dot(f.$2), d.dot(f.$3), d.dot(f.$4));
  }

  static Vec3 _fromFrame((Vec3, Vec3, Vec3, Vec3) f, Vec3 c) =>
      f.$1 + f.$2 * c.x + f.$3 * c.y + f.$4 * c.z;

  static Solid of(SolidKind kind) => switch (kind) {
    SolidKind.kubus => _box(kind, 1, 1, 1),
    SolidKind.balok => _box(kind, 1.6, 0.9, 1),
    SolidKind.prisma => _prism(kind, 3, 0.62, 1.3, labelled: true),
    SolidKind.limas => _pyramid(kind, 4, 0.8, 1.2, labelled: true),
    SolidKind.tabung => _prism(kind, 28, 0.55, 1.3, labelled: false),
    SolidKind.kerucut => _pyramid(kind, 28, 0.6, 1.3, labelled: false),
    SolidKind.bola => _sphere(),
  };

  /// Box: bottom ABCD, top EFGH; net is the cross with the top on the front.
  static Solid _box(SolidKind kind, double w, double h, double d) {
    final x = w / 2, y = h / 2, z = d / 2;
    final a = Vec3(-x, -y, z), b = Vec3(x, -y, z), c = Vec3(x, -y, -z);
    final dd = Vec3(-x, -y, -z), e = Vec3(-x, y, z), f = Vec3(x, y, z);
    final g = Vec3(x, y, -z), hh = Vec3(-x, y, -z);
    final faces = [
      Face([a, dd, c, b]), // 0 bottom (normal down)
      Face([a, b, f, e], parent: 0, hinge: (0, 1)), // 1 front
      Face([b, c, g, f], parent: 0, hinge: (0, 1)), // 2 right
      Face([c, dd, hh, g], parent: 0, hinge: (0, 1)), // 3 back
      Face([dd, a, e, hh], parent: 0, hinge: (0, 1)), // 4 left
      Face([e, f, g, hh], parent: 1, hinge: (0, 1)), // 5 top, on the front
    ];
    return Solid(
      kind,
      faces,
      {'A': a, 'B': b, 'C': c, 'D': dd, 'E': e, 'F': f, 'G': g, 'H': hh},
      [a, c, g, e], // bidang diagonal ACGE
    );
  }

  static List<Vec3> _ring(int n, double r, double y) => [
    for (var i = 0; i < n; i++)
      Vec3(
        r * math.cos(math.pi / 2 + 2 * math.pi * i / n),
        y,
        r * math.sin(math.pi / 2 + 2 * math.pi * i / n),
      ),
  ];

  /// Prism (n = 3) or cylinder (large n). The sides chain one after the
  /// other so a cylinder opens into one rectangle, like the real net.
  static Solid _prism(
    SolidKind kind,
    int n,
    double r,
    double h, {
    required bool labelled,
  }) {
    final bottom = _ring(n, r, -h / 2), top = _ring(n, r, h / 2);
    final smooth = !labelled;
    final faces = <Face>[
      Face(bottom), // 0 bottom (the ring runs clockwise seen from below)
    ];
    for (var i = 0; i < n; i++) {
      final j = (i + 1) % n;
      faces.add(
        Face(
          [bottom[j], bottom[i], top[i], top[j]],
          parent: i == 0 ? 0 : i, // first side on the base, then a chain
          hinge: i == 0 ? (0, 1) : (1, 2), // shared with the previous side
          smoothEdges: smooth ? {1, 3} : const {},
        ),
      );
    }
    // Top lid on the first side's top edge.
    final lid = top.reversed.toList();
    final first = faces[1].points;
    final k = lid.indexOf(first[3]);
    faces.add(
      Face(
        [for (var i = 0; i < n; i++) lid[(k + i) % n]],
        parent: 1,
        hinge: (0, 1),
      ),
    );
    // The hinge of the lid must be its edge shared with side 1 (top[1]→top[0]).
    final lidFace = faces.last;
    final hingeA = lidFace.points.indexOf(first[3]);
    final hingeB = lidFace.points.indexOf(first[2]);
    faces[faces.length - 1] = Face(
      lidFace.points,
      parent: 1,
      hinge: (hingeA, hingeB),
    );
    final names = labelled
        ? {
            for (var i = 0; i < n; i++) String.fromCharCode(65 + i): bottom[i],
            for (var i = 0; i < n; i++) String.fromCharCode(65 + n + i): top[i],
          }
        : <String, Vec3>{};
    final cut = labelled
        ? _ring(n, r, 0) // cross-section halfway up
        : [
            Vec3(-r, -h / 2, 0),
            Vec3(r, -h / 2, 0),
            Vec3(r, h / 2, 0),
            Vec3(-r, h / 2, 0),
          ];
    return Solid(kind, faces, names, cut);
  }

  /// Pyramid (n = 4) or cone (large n). The slanted faces chain so a cone
  /// opens into one sector.
  static Solid _pyramid(
    SolidKind kind,
    int n,
    double r,
    double h, {
    required bool labelled,
  }) {
    final base = n == 4
        ? [
            for (var i = 0; i < 4; i++)
              Vec3(
                r *
                    math.cos(math.pi / 4 + math.pi / 2 * i) *
                    math.sqrt2 /
                    2 *
                    1.4,
                -h / 2,
                r *
                    math.sin(math.pi / 4 + math.pi / 2 * i) *
                    math.sqrt2 /
                    2 *
                    1.4,
              ),
          ]
        : _ring(n, r, -h / 2);
    final apex = Vec3(0, h / 2, 0);
    final faces = <Face>[Face(base)];
    for (var i = 0; i < n; i++) {
      final j = (i + 1) % n;
      faces.add(
        Face(
          [base[j], base[i], apex],
          parent: labelled || i == 0 ? 0 : i,
          hinge: labelled || i == 0 ? (0, 1) : (1, 2),
          smoothEdges: labelled ? const {} : {1, 2},
        ),
      );
    }
    final names = labelled
        ? {
            for (var i = 0; i < n; i++) String.fromCharCode(65 + i): base[i],
            'T': apex,
          }
        : <String, Vec3>{};
    final cut = labelled
        ? [for (final p in base) Vec3(p.x / 2, 0, p.z / 2)] // halfway up
        : [Vec3(-r, -h / 2, 0), Vec3(r, -h / 2, 0), apex];
    return Solid(kind, faces, names, cut);
  }

  static Solid _sphere() {
    const rings = 12, segments = 24, r = 0.7;
    Vec3 at(int ring, int seg) {
      final phi = math.pi * ring / rings;
      final theta = 2 * math.pi * seg / segments;
      return Vec3(
        r * math.sin(phi) * math.cos(theta),
        r * math.cos(phi),
        r * math.sin(phi) * math.sin(theta),
      );
    }

    final faces = <Face>[];
    for (var i = 0; i < rings; i++) {
      for (var j = 0; j < segments; j++) {
        final pts = [at(i, j), at(i + 1, j), at(i + 1, j + 1), at(i, j + 1)];
        // Drop the repeated pole point so every face has a usable normal.
        final unique = <Vec3>[];
        for (final p in pts) {
          if (unique.every((q) => (q - p).length > 1e-9)) unique.add(p);
        }
        faces.add(
          Face(unique.reversed.toList(), smoothEdges: const {0, 1, 2, 3}),
        );
      }
    }
    return Solid(SolidKind.bola, faces, const {}, [
      for (var j = 0; j < 48; j++)
        Vec3(
          r * math.cos(2 * math.pi * j / 48),
          0,
          r * math.sin(2 * math.pi * j / 48),
        ),
    ]);
  }
}
