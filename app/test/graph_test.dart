import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whiteboard_ifp/canvas/ink_canvas.dart';
import 'package:whiteboard_ifp/canvas/ink_controller.dart';
import 'package:whiteboard_ifp/canvas/stroke.dart';
import 'package:whiteboard_ifp/data/stroke_codec.dart';
import 'package:whiteboard_ifp/graph/expression.dart';
import 'package:whiteboard_ifp/graph/graph_painter.dart';
import 'package:whiteboard_ifp/ui/theme.dart';

double ev(String f, double x, [Map<String, double> p = const {}]) =>
    Expression.parse(f).evaluate(x, p);

GraphItem sampleGraph({Rect rect = const Rect.fromLTWH(100, 100, 720, 450)}) =>
    GraphItem(
      id: 'g',
      rect: rect,
      functions: const [
        GraphFunction('y = x² − 3', PenColors.red),
        GraphFunction('y = A sin x + B', PenColors.blue),
      ],
      params: const [
        GraphParam(name: 'A', min: -5, max: 5, value: 1),
        GraphParam(name: 'B', min: -5, max: 5, value: 0),
      ],
      xMin: -6,
      xMax: 6,
      yMin: -4,
      yMax: 6,
    );

void main() {
  group('AC-86 Expression', () {
    test('handles the formulas from the video', () {
      expect(ev('y = x² − 3', 2), 1);
      final e = Expression.parse('y = A sin x + B');
      expect(e.parameters, {'A', 'B'});
      expect(e.evaluate(math.pi / 2, {'A': 2, 'B': 1}), closeTo(3, 1e-9));
    });

    test('implicit multiplication and function arguments', () {
      expect(ev('2x', 3), 6);
      expect(ev('3(x+1)', 1), 6);
      expect(ev('Asinx', math.pi / 2, {'A': 4}), closeTo(4, 1e-9));
      expect(ev('sin 2x', math.pi / 4), closeTo(1, 1e-9));
      expect(ev('2πx', 1), closeTo(2 * math.pi, 1e-9));
      expect(ev('-x^2', 3), -9, reason: 'power binds tighter than minus');
      expect(ev('2^3^2', 0), 512, reason: 'right associative');
    });

    test('functions, constants, absolute value, decimal comma', () {
      expect(ev('√x', 9), 3);
      expect(ev('sqrt(x)', 16), 4);
      expect(ev('|x - 5|', 2), 3);
      expect(ev('log x', 1000), closeTo(3, 1e-9));
      expect(ev('ln(e)', 0), closeTo(1, 1e-9));
      expect(ev('0,5x', 4), 2);
      expect(ev('f(x) = x ÷ 2', 8), 4);
    });

    test('undefined points are NaN, not crashes', () {
      expect(ev('1/x', 0).isNaN, isTrue);
      expect(ev('sqrt(x)', -1).isNaN, isTrue);
      expect(ev('ln x', -2).isNaN, isTrue);
      expect(ev('tan x', 1).isFinite, isTrue);
    });

    for (final bad in [
      '',
      '__import__("os")',
      'x; rm -rf /',
      'x +',
      '(x + 1',
      'sin(',
      'x # 2',
      'eval(x)',
      'a' * 300,
    ]) {
      test(
        'AC-85 rejects "${bad.length > 20 ? '${bad.substring(0, 20)}…' : bad}"',
        () {
          expect(() => Expression.parse(bad), throwsFormatException);
        },
      );
    }

    test('deep nesting is refused instead of overflowing', () {
      expect(
        () => Expression.parse('${'(' * 150}x${')' * 150}'),
        throwsFormatException,
      );
    });
  });

  group('GraphItem', () {
    test('parses its formulas once; unreadable ones are null', () {
      final g = GraphItem(
        id: 'g',
        rect: Rect.zero,
        functions: const [
          GraphFunction('x^2', PenColors.red),
          GraphFunction('import os', PenColors.blue),
        ],
        params: const [],
        xMin: -1,
        xMax: 1,
        yMin: -1,
        yMax: 1,
      );
      expect(g.expressions[0], isNotNull);
      expect(g.expressions[1], isNull);
    });

    test('slider values stay within min..max', () {
      final g = sampleGraph().withParam('A', 99);
      expect(g.params.first.value, 5);
      expect(g.params.last.value, 0);
    });

    test('AC-87 codec round-trip keeps formulas, params, axes, place', () {
      final g = sampleGraph().withParam('B', 2);
      final back =
          ItemCodec.decode(
                kind: ObjectKind.of(g),
                id: 'g',
                z: 4,
                data: ItemCodec.encode(g),
              )!
              as GraphItem;
      expect(back.rect, g.rect);
      expect(back.functions.map((f) => f.formula), [
        'y = x² − 3',
        'y = A sin x + B',
      ]);
      expect(back.functions.last.color, PenColors.blue);
      expect(back.values, {'A': 1.0, 'B': 2.0});
      expect([back.xMin, back.xMax, back.yMin, back.yMax], [-6, 6, -4, 6]);
      expect(ObjectKind.of(g), 'grafik');
    });

    test('damaged graph data is detected', () {
      expect(
        () => ItemCodec.decode(
          kind: ObjectKind.graph,
          id: 'g',
          z: 1,
          data:
              '{"v":1,"x":0,"y":0,"w":1,"h":1,"sumbu":[5,1,0,1],'
              '"fungsi":[],"parameter":[]}',
        ),
        throwsFormatException,
      );
    });

    test('layout: slider hit testing and value mapping', () {
      final layout = GraphLayout(sampleGraph());
      final track = layout.sliders.first;
      expect(layout.sliderAt(track.center), 0);
      expect(layout.sliderAt(layout.sliders.last.center), 1);
      expect(layout.sliderAt(sampleGraph().rect.bottomLeft), isNull);
      expect(layout.valueAt(0, track.left), -5);
      expect(layout.valueAt(0, track.right), 5);
      expect(layout.valueAt(0, track.center.dx), closeTo(0, 0.3));
    });

    test('formulas from the AI are shown as people write them', () {
      expect(prettyFormula('y = x^2 - 3'), 'y = x² − 3');
      expect(prettyFormula('y = A*sin(x) + B'), 'y = A sin(x) + B');
      expect(prettyFormula('y = 2*x - 1'), 'y = 2 x − 1');
      expect(prettyFormula('y = -x^2'), 'y = -x²');
      expect(prettyFormula('y = sqrt(x)'), 'y = √(x)');
    });

    test('numbers use the Indonesian decimal comma', () {
      expect(formatNumber(1.5), '1,5');
      expect(formatNumber(-2), '-2');
      expect(formatNumber(0.25), '0,25');
      expect(niceStep(1.3), 2);
      expect(niceStep(0.07), 0.1);
    });
  });

  group('AC-84 slider on the board', () {
    late InkController ink;
    setUp(() {
      ink = InkController()..addItem(sampleGraph());
    });
    tearDown(() => ink.dispose());

    Future<void> pump(WidgetTester tester, CanvasTool tool) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: InkCanvas(controller: ink, tool: ValueNotifier(tool)),
        ),
      );
    }

    for (final tool in [CanvasTool.pen, CanvasTool.eraser, CanvasTool.select]) {
      testWidgets('dragging slider A moves the curve with ${tool.name}', (
        tester,
      ) async {
        await pump(tester, tool);
        final layout = GraphLayout(ink.items.single as GraphItem);
        final g = await tester.startGesture(layout.knob(0));
        await g.moveTo(layout.sliders.first.centerRight);
        await tester.pump();
        expect(
          (ink.transformPreview! as GraphItem).values['A'],
          5,
          reason: 'curve follows live while dragging',
        );
        await g.up();
        await tester.pump();
        final graph = ink.items.single as GraphItem;
        expect(graph.values['A'], 5);
        expect(ink.strokes, isEmpty, reason: 'no ink drawn on the slider');

        ink.undo();
        expect((ink.items.single as GraphItem).values['A'], 1);
        await tester.pumpWidget(const SizedBox());
      });
    }

    testWidgets('with Geser the slider is not moved', (tester) async {
      await pump(tester, CanvasTool.pan);
      final layout = GraphLayout(ink.items.single as GraphItem);
      final g = await tester.startGesture(layout.knob(0));
      await g.moveTo(layout.sliders.first.centerRight);
      await g.up();
      await tester.pump();
      expect((ink.items.single as GraphItem).values['A'], 1);
      await tester.pumpWidget(const SizedBox());
    });

    test('pictures and graphs are not erased', () {
      ink.eraserDown(1, sampleGraph().rect.center, radius: 50);
      ink.eraserUp(1);
      expect(ink.items.single, isA<GraphItem>());
    });
  });
}
