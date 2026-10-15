import 'dart:math' as math;

/// A math formula parsed into a small expression tree (REQ-20).
///
/// Formulas come from the AI, so they are only ever parsed and evaluated
/// here — never executed as code. Supported: numbers, x, single-letter
/// parameters (A, B, k, …), π/pi, e, + − × ÷ ^ (also ², ³), parentheses,
/// |…|, implicit multiplication (2x, A sin x, 3(x+1)), and sin cos tan
/// asin acos atan sqrt/√ abs log (base 10) ln exp.
class Expression {
  Expression._(this.source, this._root, this.parameters);

  /// The formula as given, e.g. `A sin x + B`.
  final String source;
  final _Node _root;

  /// Parameter names used by the formula (every letter except x and e).
  final Set<String> parameters;

  static const maxLength = 200;

  /// Parses [source]; a leading `y =` / `f(x) =` is allowed. Throws
  /// [FormatException] with an Indonesian message when it is not a formula.
  static Expression parse(String source) {
    final text = source.trim();
    if (text.isEmpty || text.length > maxLength) {
      throw const FormatException('Rumus kosong atau terlalu panjang.');
    }
    final body = text.replaceFirst(
      RegExp(r'^\s*(y|f\s*\(\s*x\s*\))\s*=\s*', caseSensitive: false),
      '',
    );
    final parser = _Parser(_tokenize(body));
    final root = parser.parseExpression();
    parser.expectEnd();
    return Expression._(text, root, parser.parameters);
  }

  /// Value at [x]; NaN or infinite where the formula is undefined.
  double evaluate(double x, [Map<String, double> params = const {}]) =>
      _root.eval(x, params);
}

// --- tokens ------------------------------------------------------------------

enum _T { number, name, op, open, close, bar, end }

class _Token {
  const _Token(this.type, [this.text = '', this.value = 0]);
  final _T type;
  final String text;
  final double value;
}

const _functions = {
  'sin',
  'cos',
  'tan',
  'asin',
  'acos',
  'atan',
  'sqrt',
  'abs',
  'log',
  'ln',
  'exp',
};

List<_Token> _tokenize(String input) {
  final s = input
      .replaceAll('²', '^2')
      .replaceAll('³', '^3')
      .replaceAll('−', '-')
      .replaceAll('–', '-')
      .replaceAll('×', '*')
      .replaceAll('·', '*')
      .replaceAll('÷', '/')
      .replaceAll('√', 'sqrt')
      .replaceAll('π', 'pi')
      .replaceAll('**', '^');
  final tokens = <_Token>[];
  var i = 0;
  while (i < s.length) {
    final c = s[i];
    if (c.trim().isEmpty) {
      i++;
    } else if (RegExp(r'[0-9.,]').hasMatch(c)) {
      final start = i;
      while (i < s.length && RegExp(r'[0-9.,]').hasMatch(s[i])) {
        i++;
      }
      // Indonesian decimals use a comma.
      final raw = s.substring(start, i).replaceAll(',', '.');
      final value = double.tryParse(raw);
      if (value == null) throw FormatException('Angka tidak dikenal: $raw');
      tokens.add(_Token(_T.number, raw, value));
    } else if (RegExp(r'[A-Za-z]').hasMatch(c)) {
      final start = i;
      while (i < s.length && RegExp(r'[A-Za-z]').hasMatch(s[i])) {
        i++;
      }
      tokens.addAll(_splitWord(s.substring(start, i)));
    } else if ('+-*/^'.contains(c)) {
      tokens.add(_Token(_T.op, c));
      i++;
    } else if (c == '(') {
      tokens.add(const _Token(_T.open));
      i++;
    } else if (c == ')') {
      tokens.add(const _Token(_T.close));
      i++;
    } else if (c == '|') {
      tokens.add(const _Token(_T.bar));
      i++;
    } else {
      throw FormatException('Tanda tidak dikenal: $c');
    }
  }
  tokens.add(const _Token(_T.end));
  return tokens;
}

/// Splits letters into function names, `pi`, and single-letter names, so
/// `Asinx` reads as A · sin · x. Function names match lowercase only, so a
/// capital parameter is never swallowed (`Asin` is A · sin, not asin). More
/// than two plain letters in a row (`eval`, `import`) are words, not math,
/// and are refused.
List<_Token> _splitWord(String word) {
  final names = _functions.toList()..sort((a, b) => b.length - a.length);
  final out = <_Token>[];
  var rest = word;
  var plainRun = 0;
  while (rest.isNotEmpty) {
    final fn = names.where(rest.startsWith).firstOrNull;
    if (fn != null) {
      out.add(_Token(_T.name, fn));
      rest = rest.substring(fn.length);
      plainRun = 0;
    } else if (rest.startsWith('pi')) {
      out.add(const _Token(_T.name, 'pi'));
      rest = rest.substring(2);
      plainRun = 0;
    } else {
      if (++plainRun > 2) {
        throw FormatException('Kata tidak dikenal dalam rumus: $word');
      }
      out.add(_Token(_T.name, rest[0]));
      rest = rest.substring(1);
    }
  }
  return out;
}

// --- parser ------------------------------------------------------------------

class _Parser {
  _Parser(this.tokens);

  final List<_Token> tokens;
  final Set<String> parameters = {};
  int _pos = 0;
  int _depth = 0;

  _Token get _peek => tokens[_pos];
  _Token _next() => tokens[_pos++];

  void expectEnd() {
    if (_peek.type != _T.end) {
      throw const FormatException('Rumus tidak lengkap atau ada sisa tanda.');
    }
  }

  _Node parseExpression() {
    if (++_depth > 60) throw const FormatException('Rumus terlalu bersarang.');
    var left = _term();
    while (_peek.type == _T.op && (_peek.text == '+' || _peek.text == '-')) {
      final op = _next().text;
      final right = _term();
      left = _Binary(op, left, right);
    }
    _depth--;
    return left;
  }

  bool get _startsFactor =>
      _peek.type == _T.number ||
      _peek.type == _T.name ||
      _peek.type == _T.open ||
      _peek.type == _T.bar;

  _Node _term() {
    var left = _unary();
    while (true) {
      if (_peek.type == _T.op && (_peek.text == '*' || _peek.text == '/')) {
        final op = _next().text;
        left = _Binary(op, left, _unary());
      } else if (_startsFactor && _peek.type != _T.bar) {
        // Implicit multiplication: 2x, A sin x, 3(x + 1).
        left = _Binary('*', left, _power());
      } else {
        return left;
      }
    }
  }

  _Node _unary() {
    if (_peek.type == _T.op && (_peek.text == '-' || _peek.text == '+')) {
      final op = _next().text;
      final inner = _unary();
      return op == '-' ? _Negate(inner) : inner;
    }
    return _power();
  }

  _Node _power() {
    final base = _primary();
    if (_peek.type == _T.op && _peek.text == '^') {
      _next();
      return _Binary('^', base, _unary()); // right-associative
    }
    return base;
  }

  _Node _primary() {
    final t = _next();
    switch (t.type) {
      case _T.number:
        return _Const(t.value);
      case _T.open:
        final inner = parseExpression();
        if (_next().type != _T.close) {
          throw const FormatException('Kurung tutup kurang.');
        }
        return inner;
      case _T.bar:
        final inner = parseExpression();
        if (_next().type != _T.bar) {
          throw const FormatException('Tanda nilai mutlak | kurang.');
        }
        return _Call('abs', inner);
      case _T.name:
        if (_functions.contains(t.text)) {
          // sin(x), or sin x / sin 2x without parentheses: the argument
          // is the tight product of numbers and letters that follows.
          if (_peek.type == _T.open) return _Call(t.text, _primary());
          var arg = _power();
          while ((_peek.type == _T.number || _peek.type == _T.name) &&
              !_functions.contains(_peek.text)) {
            arg = _Binary('*', arg, _power());
          }
          return _Call(t.text, arg);
        }
        if (t.text == 'pi') return const _Const(math.pi);
        if (t.text == 'x' || t.text == 'X') return const _X();
        if (t.text == 'e') return const _Const(math.e);
        parameters.add(t.text);
        return _Param(t.text);
      default:
        throw const FormatException('Rumus tidak lengkap.');
    }
  }
}

// --- tree --------------------------------------------------------------------

sealed class _Node {
  const _Node();
  double eval(double x, Map<String, double> p);
}

class _Const extends _Node {
  const _Const(this.v);
  final double v;
  @override
  double eval(double x, Map<String, double> p) => v;
}

class _X extends _Node {
  const _X();
  @override
  double eval(double x, Map<String, double> p) => x;
}

class _Param extends _Node {
  const _Param(this.name);
  final String name;
  @override
  double eval(double x, Map<String, double> p) => p[name] ?? 1;
}

class _Negate extends _Node {
  const _Negate(this.inner);
  final _Node inner;
  @override
  double eval(double x, Map<String, double> p) => -inner.eval(x, p);
}

class _Binary extends _Node {
  const _Binary(this.op, this.a, this.b);
  final String op;
  final _Node a, b;
  @override
  double eval(double x, Map<String, double> p) {
    final l = a.eval(x, p), r = b.eval(x, p);
    return switch (op) {
      '+' => l + r,
      '-' => l - r,
      '*' => l * r,
      '/' => r == 0 ? double.nan : l / r,
      _ => math.pow(l, r).toDouble(),
    };
  }
}

class _Call extends _Node {
  const _Call(this.name, this.arg);
  final String name;
  final _Node arg;
  @override
  double eval(double x, Map<String, double> p) {
    final v = arg.eval(x, p);
    return switch (name) {
      'sin' => math.sin(v),
      'cos' => math.cos(v),
      'tan' => math.tan(v),
      'asin' => math.asin(v),
      'acos' => math.acos(v),
      'atan' => math.atan(v),
      'sqrt' => v < 0 ? double.nan : math.sqrt(v),
      'abs' => v.abs(),
      'log' => v <= 0 ? double.nan : math.log(v) / math.ln10,
      'ln' => v <= 0 ? double.nan : math.log(v),
      _ => math.exp(v),
    };
  }
}
