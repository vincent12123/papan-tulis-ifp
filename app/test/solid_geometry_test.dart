import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:whiteboard_ifp/solid/solid_geometry.dart';

double _area(List<Vec3> pts) {
  var sum = const Vec3(0, 0, 0);
  for (var i = 1; i + 1 < pts.length; i++) {
    sum = sum + (pts[i] - pts[0]).cross(pts[i + 1] - pts[0]);
  }
  return sum.length / 2;
}

Vec3 _normal(List<Vec3> pts) => (pts[1] - pts[0]).cross(pts[2] - pts[0]).unit;

void main() {
  group('REQ-23 bangun ruang geometry', () {
    for (final kind in SolidKind.values) {
      test('${kind.label}: every face points outward', () {
        final solid = Solid.of(kind);
        for (final f in solid.faces) {
          expect(
            f.normal.dot(f.centroid),
            greaterThan(0),
            reason: 'face at ${f.centroid}',
          );
        }
      });
    }

    for (final kind in SolidKind.values.where((k) => k.hasNet)) {
      test('${kind.label}: the net opens flat on the base, sizes kept', () {
        final solid = Solid.of(kind);
        final net = solid.unfolded(1);
        final baseY = solid.faces.first.points.first.y;
        for (var i = 0; i < net.length; i++) {
          for (final p in net[i]) {
            expect(p.y, closeTo(baseY, 1e-6), reason: 'face $i lies flat');
          }
          expect(
            _normal(net[i]).y,
            closeTo(-1, 1e-6),
            reason: 'face $i faces the same way as the base',
          );
          expect(
            _area(net[i]),
            closeTo(_area(solid.faces[i].points), 1e-6),
            reason: 'face $i keeps its size',
          );
        }
      });

      test('${kind.label}: net faces do not pile on top of each other', () {
        final net = Solid.of(kind).unfolded(1);
        final centers = [
          for (final f in net)
            f.fold(const Vec3(0, 0, 0), (a, b) => a + b) * (1 / f.length),
        ];
        for (var i = 0; i < centers.length; i++) {
          for (var j = i + 1; j < centers.length; j++) {
            expect(
              (centers[i] - centers[j]).length,
              greaterThan(1e-3),
              reason: 'faces $i and $j overlap',
            );
          }
        }
      });
    }

    test('closed at 0, half open in between', () {
      final solid = Solid.of(SolidKind.kubus);
      final closed = solid.unfolded(0);
      expect(closed[5].first.y, closeTo(0.5, 1e-9));
      final half = solid.unfolded(0.5);
      // The front face is at 45 degrees halfway.
      final front = _normal(half[1]);
      expect(front.y.abs(), closeTo(math.sqrt1_2, 1e-6));
    });

    test('a cylinder opens into a rectangle, a cone into a sector', () {
      final solid = Solid.of(SolidKind.tabung);
      final cylinder = solid.unfolded(1);
      final sides = cylinder.sublist(1, cylinder.length - 1);
      // The strip runs along the base edge the first side hinges on.
      final first = solid.faces[1].points;
      final along = (first[0] - first[1]).unit;
      final across = const Vec3(0, -1, 0).cross(along);
      final a = [for (final p in sides.expand((f) => f)) p.dot(along)];
      final b = [for (final p in sides.expand((f) => f)) p.dot(across)];
      final circumference = 2 * 28 * 0.55 * math.sin(math.pi / 28);
      expect(
        a.reduce(math.max) - a.reduce(math.min),
        closeTo(circumference, 1e-6),
        reason: 'the side strip is as long as the rim',
      );
      expect(
        b.reduce(math.max) - b.reduce(math.min),
        closeTo(1.3, 1e-6),
        reason: 'and as wide as the cylinder is tall',
      );

      // A cone's slanted faces fan out around the apex: all at slant height.
      final coneSolid = Solid.of(SolidKind.kerucut);
      final cone = coneSolid.unfolded(1);
      final apex = cone[1][2];
      final slant = math.sqrt(0.6 * 0.6 + 1.3 * 1.3);
      for (final f in cone.sublist(1)) {
        expect((f[2] - apex).length, closeTo(0, 1e-6), reason: 'one apex');
        expect((f[0] - apex).length, closeTo(slant, 1e-6));
      }
    });

    test('a cube has labels A–H and a diagonal cut plane', () {
      final solid = Solid.of(SolidKind.kubus);
      expect(solid.labels.keys, ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H']);
      expect(solid.cut.length, 4);
      expect(Solid.of(SolidKind.bola).kind.hasNet, isFalse);
    });
  });
}
