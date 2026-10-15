"""LaTeX formulas → checked graph data with SymPy (SPEC 1.8, REQ-20).

The recognizer's LaTeX is only trusted after SymPy has parsed it and every
part of the expression is on a whitelist: the variable x, single-letter
parameters, numbers, + - * / ^, and sin, cos, tan, sqrt, log, ln, exp, abs.
Anything else (stray symbols, imaginary unit, unknown functions) drops the
line. The formula then goes to the panel as plain text in the syntax of its
own math parser (app/lib/graph/expression.dart); nothing is executed.
"""

from __future__ import annotations

import json
import math
import re

import sympy as sp
from sympy.core.function import AppliedUndef
from sympy.printing.str import StrPrinter

from .ai import MAX_FUNCTIONS, MAX_PARAMS, parse_graph

X = sp.Symbol("x")


class Log10(sp.Function):
    """Base-10 log, as "log" is read in Indonesian schools."""

    def _latex(self, printer):
        arg = printer._print(self.args[0])
        return r"\log{\left(" + arg + r" \right)}"


_ALLOWED_FUNCS = (sp.sin, sp.cos, sp.tan, sp.log, sp.exp, sp.Abs, Log10)
_FUNCTION_LHS = re.compile(r"^(y|[fgh]\(x\))$")
_SPACED_NAMES = re.compile(
    r"(?<![A-Za-z\\])(s\s*i\s*n|c\s*o\s*s|t\s*a\s*n|l\s*o\s*g|l\s*n|e\s*x\s*p)(?![A-Za-z])"
)


def clean_latex(latex: str) -> str:
    """Undoes the recognizer's spacing and naming quirks."""
    s = latex
    for junk in (r"\!", r"\,", r"\;", r"\:", r"\quad", r"\displaystyle", r"\left", r"\right", "~"):
        s = s.replace(junk, " ")
    s = re.sub(
        r"\\(?:operatorname|mathrm)\s*\{([^}]*)\}",
        lambda m: (
            "\\" + m.group(1).replace(" ", "")
            if m.group(1).replace(" ", "") in _NAMES
            else m.group(0)
        ),
        s,
    )
    s = re.sub(r"\\(?:mathbf|boldsymbol|mathit|mathrm|bf)\s*\{([^{}]*)\}", r" \1 ", s)
    # Handwritten x is sometimes read as a Greek kappa or chi.
    s = re.sub(r"\\(?:varkappa|kappa|chi)(?![A-Za-z])", "x", s)
    s = re.sub(r"\\l\s*o\s*g\b", r"\\log", s)
    s = _SPACED_NAMES.sub(lambda m: "\\" + re.sub(r"\s", "", m.group(1)), s)
    s = s.replace(r"\lg", r"\log_{10}")
    s = re.sub(r"\\log(?!_)", r"\\log_{10}", s)
    s = s.replace(r"\div", "/")
    return re.sub(r"\s+", " ", s).strip()


_NAMES = {"sin", "cos", "tan", "log", "ln", "exp"}


def _function_side(latex: str) -> str | None:
    """The right-hand side of y = …, f(x) = …; a lone expression as is."""
    parts = latex.split("=")
    if len(parts) == 1:
        return parts[0]
    if len(parts) != 2:
        return None
    lhs, rhs = (re.sub(r"[\s{}]", "", p) for p in parts)
    if _FUNCTION_LHS.match(lhs):
        return parts[1]
    if _FUNCTION_LHS.match(rhs):
        return parts[0]
    return None


def _rebuild(e: sp.Basic) -> sp.Basic:
    """parse_latex leaves sums unevaluated; rebuild for a tidy, ordered form."""
    if not e.args:
        return e
    return e.func(*(_rebuild(a) for a in e.args))


def _to_log10(e: sp.Basic) -> sp.Basic:
    """log(u)/log(10) (what SymPy makes of \\log_{10} u) back to log10(u)."""
    if isinstance(e, sp.Mul):
        inv = sp.Pow(sp.log(10), -1)
        if inv in e.args:
            logs = [a for a in e.args if isinstance(a, sp.log)]
            if logs:
                rest = list(e.args)
                rest.remove(inv)
                rest.remove(logs[0])
                return sp.Mul(Log10(logs[0].args[0]), *rest)
    return e


def to_expression(latex: str) -> sp.Expr | None:
    """A whitelisted SymPy expression in x, or None."""
    side = _function_side(clean_latex(latex))
    if side is None or not side.strip():
        return None
    return parse_side(side)


def parse_side(side: str, *, allow_y: bool = False) -> sp.Expr | None:
    """One side of a cleaned formula as a whitelisted SymPy expression.

    [allow_y] lets equations such as x + y = 5 use y as an unknown; in a
    function y = … it would make no sense on the right-hand side."""
    from sympy.parsing.latex import parse_latex

    if not side.strip():
        return None
    try:
        expr = parse_latex(side)
    except Exception:  # LaTeXParsingError and anything the grammar trips on
        return None
    if not isinstance(expr, sp.Expr):
        return None
    expr = _rebuild(expr).subs({sp.Symbol("e"): sp.E, sp.Symbol("pi"): sp.pi})
    expr = expr.replace(lambda e: isinstance(e, sp.Mul), _to_log10)

    if expr.has(sp.I, sp.zoo, sp.oo, -sp.oo, sp.nan):
        return None
    for s in expr.free_symbols:
        # I, l, O, o are far more often a misread 1 or 0 than a parameter.
        banned = "IlOo" if allow_y else "yIlOo"
        if not re.fullmatch(r"[A-Za-z]", s.name) or s.name in banned:
            return None
    for f in expr.atoms(sp.Function):
        if isinstance(f, AppliedUndef) or not isinstance(f, _ALLOWED_FUNCS):
            return None
    if any(
        isinstance(a, (sp.Derivative, sp.Integral, sp.Sum, sp.Limit))
        for a in sp.preorder_traversal(expr)
    ):
        return None
    return expr


class _AppPrinter(StrPrinter):
    """Prints in the panel parser's syntax: ^, ln, log (base 10), abs, π."""

    def _print_log(self, e):
        return f"ln({self._print(e.args[0])})"

    def _print_Log10(self, e):
        return f"log({self._print(e.args[0])})"

    def _print_Abs(self, e):
        return f"abs({self._print(e.args[0])})"

    def _print_Exp1(self, e):
        return "e"

    def _print_Pi(self, e):
        return "\u03c0"

    def _print_Float(self, e):
        return format(float(e), "g")


def to_formula(expr: sp.Expr) -> str:
    return "y = " + _AppPrinter().doprint(expr).replace("**", "^")


def _samples(expr: sp.Expr, params: list[str], x_min: float, x_max: float) -> list[float]:
    fixed = expr.subs({sp.Symbol(p): 1 for p in params})
    fixed = fixed.replace(Log10, lambda u: sp.log(u) / sp.log(10))
    values = []
    for i in range(41):
        x = x_min + (x_max - x_min) * i / 40
        try:
            v = complex(fixed.subs(X, x).evalf())
        except (TypeError, ValueError, ZeroDivisionError):
            continue
        if abs(v.imag) < 1e-9 and math.isfinite(v.real):
            values.append(v.real)
    return values


def split_rows(latex: str) -> list[str]:
    """Formulas written close together reach the recognizer as one image and
    come back as one block (\\begin{matrix} a \\\\ b \\end{matrix}); split it
    into one formula per row again."""
    s = re.sub(r"\\begin\s*\{[a-z*]+\}(\s*\{[^}]*\})?", " ", latex)
    s = re.sub(r"\\end\s*\{[a-z*]+\}", " ", s)
    return [row.replace("&", " ").strip() for row in s.split("\\\\") if row.strip()]


def build_graph(latex_lines: list[str]) -> dict:
    """Graph data in the same shape as parse_graph: fungsi, parameter, sumbu.

    Lines that are not a drawable function of x are left out; an empty
    "fungsi" means nothing usable was found (tanpa_rumus)."""
    exprs = []
    for latex in (row for line in latex_lines for row in split_rows(line)):
        expr = to_expression(latex)
        if expr is not None and len(exprs) < MAX_FUNCTIONS:
            exprs.append(expr)
    params = sorted({s.name for e in exprs for s in e.free_symbols} - {"x"})
    if len(params) > MAX_PARAMS:
        return {"fungsi": [], "parameter": [], "sumbu": {}}

    trig = any(e.has(sp.sin, sp.cos, sp.tan) for e in exprs)
    x_min, x_max = (-6.28, 6.28) if trig else (-10.0, 10.0)
    kept, values = [], []
    for e in exprs:
        v = _samples(e, params, x_min, x_max)
        if len(v) >= 10:  # at least a quarter of the axis can be drawn
            kept.append(e)
            values += v
    if values:
        values.sort()
        lo = values[int(len(values) * 0.05)]
        hi = values[int(len(values) * 0.95) - 1] if len(values) > 1 else values[0]
        lo, hi = min(lo, -1.0), max(hi, 1.0)
        pad = (hi - lo) * 0.1
        y_min, y_max = max(lo - pad, -1000.0), min(hi + pad, 1000.0)
    else:
        y_min, y_max = -10.0, 10.0
    used = sorted({s.name for e in kept for s in e.free_symbols} - {"x"})
    data = {
        "fungsi": [to_formula(e) for e in kept],
        "parameter": [{"nama": p, "min": -5, "maks": 5, "nilai": 1} for p in used],
        "sumbu": {
            "x_min": x_min,
            "x_maks": x_max,
            "y_min": round(y_min, 2),
            "y_maks": round(y_max, 2),
        },
    }
    # Same checks as any other graph answer (character whitelist, limits).
    return parse_graph(json.dumps(data))
