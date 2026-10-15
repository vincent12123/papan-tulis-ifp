"""Menu pintar (SPEC 1.9, REQ-22): what is written in a circled area and
what can be done with it, computed without any language model.

Each recognized line becomes a function (y = …), an equation (x² = 4,
x + y = 5) or a plain expression. The area takes the "strongest" kind:
any function → fungsi (Jadikan grafik, Rapikan rumus); otherwise any
equation → persamaan (Rapikan rumus, Selesaikan); otherwise ekspresi
(Rapikan rumus). Equations are solved exactly by SymPy, limited to
polynomial (and rational) equations so a request can never hang.
"""

from __future__ import annotations

import re
from dataclasses import dataclass

import sympy as sp

from .formula_math import (
    _FUNCTION_LHS,
    MAX_FUNCTIONS,
    build_graph,
    clean_latex,
    parse_side,
    split_rows,
)

MAX_ROWS = 4
MAX_UNKNOWNS = 3
MAX_DEGREE = 4


@dataclass
class Row:
    kind: str  # "fungsi" | "persamaan" | "ekspresi"
    latex: str  # as written (cleaned recognizer LaTeX): "Rapikan" keeps the form
    tidy: str  # SymPy's LaTeX, used when mathtext cannot draw [latex]
    source: str  # recognizer LaTeX, for Jadikan grafik
    lhs: sp.Expr | None = None
    rhs: sp.Expr | None = None


@dataclass
class Insight:
    kind: str
    rows: list[Row]
    graph: dict | None
    # LaTeX lines of the solution; [] = no real solution; None = not offered.
    solution: list[str] | None


def _tex(e: sp.Expr) -> str:
    return sp.latex(e, ln_notation=True)


def _as_written(cleaned: str) -> str:
    """The recognizer's LaTeX, ready for mathtext: no base-10 marker (added
    only for SymPy), no spaces around ^ and _ (mathtext then drops the
    superscript: "x ^ { 2 }" came out as "x 2"), full-size fractions so
    they read from the back of the class."""
    s = cleaned.replace(r"\log_{10}", r"\log")
    s = re.sub(r"\s*([\^_])\s*", r"\1", s)
    s = re.sub(r"\{\s+", "{", re.sub(r"\s+\}", "}", s))
    # "A sin x" should not read as "Asin x".
    s = re.sub(r"(?<=[A-Za-z0-9})])\s*\\(sin|cos|tan|log|ln|exp)\b", r"\\,\\\1", s)
    return re.sub(r"\\frac(?![a-z])", r"\\dfrac", s)


def read_row(latex: str) -> Row | None:
    cleaned = clean_latex(latex)
    written = _as_written(cleaned)
    parts = cleaned.split("=")
    if len(parts) == 1:
        expr = parse_side(parts[0])
        return None if expr is None else Row("ekspresi", written, _tex(expr), latex)
    if len(parts) != 2:
        return None
    left, right = (re.sub(r"[\s{}]", "", p) for p in parts)
    if _FUNCTION_LHS.match(left) or _FUNCTION_LHS.match(right):
        side = parts[1] if _FUNCTION_LHS.match(left) else parts[0]
        expr = parse_side(side)
        if expr is None:
            return None
        name = left if _FUNCTION_LHS.match(left) else right
        return Row("fungsi", written, f"{name} = {_tex(expr)}", latex)
    lhs = parse_side(parts[0], allow_y=True)
    rhs = parse_side(parts[1], allow_y=True)
    if lhs is None or rhs is None:
        return None
    return Row("persamaan", written, f"{_tex(lhs)} = {_tex(rhs)}", latex, lhs, rhs)


def _solve(rows: list[Row]) -> list[str] | None:
    equations = [sp.Eq(r.lhs, r.rhs) for r in rows if r.kind == "persamaan"]
    unknowns = sorted({s for e in equations for s in e.free_symbols}, key=lambda s: s.name)
    if not equations or not 0 < len(unknowns) <= MAX_UNKNOWNS:
        return None
    if len(unknowns) != len(equations):
        return None  # x + y = 5 alone has infinitely many solutions
    for eq in equations:
        numerator = sp.together(eq.lhs - eq.rhs).as_numer_denom()[0]
        if not numerator.is_polynomial(*unknowns):
            return None
        if sp.Poly(numerator, *unknowns).total_degree() > MAX_DEGREE:
            return None
    if len(unknowns) == 1:
        x = unknowns[0]
        found = sp.solveset(equations[0], x, domain=sp.S.Reals)
        if not isinstance(found, sp.FiniteSet):
            return None if found != sp.S.EmptySet else []
        values = sorted(found, key=lambda v: float(sp.N(v)))
        return [f"{_tex(x)} = {_tex(v)}" for v in values]
    answers = sp.solve(equations, unknowns, dict=True)
    lines = []
    for a in answers:
        if len(a) != len(unknowns) or not all(v.is_real for v in a.values()):
            continue
        lines.append(",\\; ".join(f"{_tex(u)} = {_tex(a[u])}" for u in unknowns))
    return lines


def analyze(latex_lines: list[str]) -> Insight | None:
    """None when no line is a usable formula (tanpa_rumus)."""
    rows = []
    for line in latex_lines:
        for part in split_rows(line):
            row = read_row(part)
            if row is not None and len(rows) < MAX_ROWS:
                rows.append(row)
    if not rows:
        return None
    kinds = {r.kind for r in rows}
    if "fungsi" in kinds:
        functions = [r.source for r in rows if r.kind == "fungsi"][:MAX_FUNCTIONS]
        graph = build_graph(functions)
        return Insight("fungsi", rows, graph if graph["fungsi"] else None, None)
    if "persamaan" in kinds:
        return Insight("persamaan", rows, None, _solve(rows))
    return Insight("ekspresi", rows, None, None)
