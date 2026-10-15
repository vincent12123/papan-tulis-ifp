"""Kimia (SPEC 1.9, REQ-24): chemical formulas and reactions in a circled
area, read from the formula recognizer's LaTeX. No language model.

A row is chemistry when it has a reaction arrow, or when every term is a
valid formula of element symbols (2Na, Cl₂, NaCl, C₆H₅OH). Reactions are
checked for balance by counting atoms and, when unbalanced, balanced exactly
with the null space of the atom matrix (SymPy). Typeset LaTeX uses upright
element symbols with subscripts, as in a chemistry book.
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from math import lcm

import sympy as sp

ELEMENTS = set(
    """H He Li Be B C N O F Ne Na Mg Al Si P S Cl Ar K Ca Sc Ti V Cr Mn Fe Co Ni
    Cu Zn Ga Ge As Se Br Kr Rb Sr Y Zr Nb Mo Tc Ru Rh Pd Ag Cd In Sn Sb Te I Xe
    Cs Ba La Ce Pr Nd Pm Sm Eu Gd Tb Dy Ho Er Tm Yb Lu Hf Ta W Re Os Ir Pt Au Hg
    Tl Pb Bi Po At Rn Fr Ra Ac Th Pa U Np Pu Am Cm""".split()
)
# Two-letter symbols that handwriting recognition invents more often than a
# teacher writes them (Fl, Lv, Ts…) are left out above on purpose.

_ARROW = re.compile(
    r"\\(?:xrightarrow\s*(?:\[[^\]]*\])?\s*\{[^}]*\}|longrightarrow|rightarrow|to|"
    r"rightleftharpoons|leftrightarrow)|→|->"
)
_WRAPPERS = re.compile(
    r"\\(?:mathrm|mathsf|mathcal|mathbf|mathit|boldsymbol|textrm|text|operatorname|sf|rm)\s*"
)
_TERM = re.compile(r"^(\d*)([A-Za-z0-9()]+)$")


@dataclass
class Species:
    coefficient: int
    formula: str  # "Cl2", "C6H5OH"
    atoms: dict[str, int]


@dataclass
class Reaction:
    left: list[Species]
    right: list[Species]  # empty for a lone formula


@dataclass
class ChemInsight:
    rows: list[Reaction]
    latex: list[str]
    species: list[str]
    # None: nothing to balance (no reaction); True/False otherwise.
    balanced: bool | None
    # LaTeX of the balanced reactions when some were not balanced.
    balanced_latex: list[str] | None


def _normalize(latex: str) -> str:
    """The recognizer's LaTeX as plain text: 2Na+Cl2->2NaCl."""
    s = latex
    for junk in (r"\!", r"\,", r"\;", r"\:", r"\quad", "~", r"\left", r"\right"):
        s = s.replace(junk, " ")
    s = _ARROW.sub(" -> ", s)
    s = re.sub(r"\^\s*\{\s*\}", "", s)  # empty superscripts
    s = re.sub(r"\^\s*\{[^}]*\}|\^\s*[+\-0-9]", "", s)  # charges: ignored
    s = _WRAPPERS.sub("", s)
    # "_{ \mathsf{2} }" leaves "_{ {2} }": drop the inner braces.
    while True:
        t = re.sub(r"\{\s*\{([^{}]*)\}\s*\}", r"{\1}", s)
        if t == s:
            break
        s = t
    # Usual misreadings of handwritten chemistry.
    s = re.sub(r"\\mid|\|", "l", s)
    s = s.replace(r"\star", "+").replace(r"\ast", "+")
    s = s.replace(r"\ell", "l").replace(r"\cdot", "")
    s = re.sub(r"_\s*\{\s*\+\s*\}", "+", s)
    s = re.sub(r"_\s*\{\s*([0-9]+)\s*\}", r"\1", s)
    s = re.sub(r"_\s*([0-9])", r"\1", s)
    s = s.replace("{", "").replace("}", "")
    s = re.sub(r"\s+", "", s)
    s = s.replace("CI", "Cl")  # carbon-iodine is far rarer than chlorine
    s = re.sub(r"Fl(?![a-z])", "Fe", s)  # a looped e read as l
    return s


def _parse_formula(text: str) -> dict[str, int] | None:
    """Atom counts of Ca(OH)2 → {Ca: 1, O: 2, H: 2}; None if not a formula."""
    atoms: dict[str, int] = {}
    stack: list[dict[str, int]] = [atoms]
    i = 0
    while i < len(text):
        ch = text[i]
        if ch == "(":
            stack.append({})
            i += 1
        elif ch == ")":
            if len(stack) == 1:
                return None
            group = stack.pop()
            j = i + 1
            while j < len(text) and text[j].isdigit():
                j += 1
            n = int(text[i + 1 : j] or 1)
            for k, v in group.items():
                stack[-1][k] = stack[-1].get(k, 0) + v * n
            i = j
        elif ch.isupper():
            two = text[i : i + 2]
            if len(two) == 2 and two[1].islower() and two in ELEMENTS:
                symbol, i = two, i + 2
            elif ch in ELEMENTS:
                symbol, i = ch, i + 1
            else:
                return None
            j = i
            while j < len(text) and text[j].isdigit():
                j += 1
            n = int(text[i:j] or 1)
            if n == 0:
                return None
            stack[-1][symbol] = stack[-1].get(symbol, 0) + n
            i = j
        else:
            return None
    if len(stack) != 1 or not atoms:
        return None
    return atoms


def _parse_side(side: str) -> list[Species] | None:
    out = []
    for term in side.split("+"):
        match = _TERM.match(term)
        if not match:
            return None
        atoms = _parse_formula(match.group(2))
        if atoms is None:
            return None
        out.append(Species(int(match.group(1) or 1), match.group(2), atoms))
    return out


def read_reaction(latex: str) -> Reaction | None:
    """A chemical formula or reaction, or None when the row is not chemistry."""
    text = _normalize(latex)
    if not text or ("=" in text and "->" not in text):
        # x = 2 is mathematics; 2Na + Cl2 = 2NaCl is rare enough to ignore.
        return None
    sides = text.split("->")
    if len(sides) > 2 or any(not s for s in sides):
        return None
    parsed = [_parse_side(s) for s in sides]
    if any(p is None for p in parsed):
        return None
    left = parsed[0]
    right = parsed[1] if len(parsed) == 2 else []
    if not right:
        # Without an arrow, require something unmistakably chemical: a
        # two-letter element or a formula with several atoms (not "B" or "C").
        everything = left
        if not any(
            any(len(el) == 2 for el in s.atoms) or sum(s.atoms.values()) > 1 for s in everything
        ):
            return None
    return Reaction(left, right)


def _species_tex(s: Species, coefficient: int | None = None) -> str:
    c = s.coefficient if coefficient is None else coefficient
    body = re.sub(r"([A-Z][a-z]?)", r"\\mathrm{\1}", s.formula)
    body = re.sub(r"(?<=[}\)])(\d+)", r"_{\1}", body)
    return (f"{c}\\," if c != 1 else "") + body


def reaction_tex(r: Reaction, coefficients: list[int] | None = None) -> str:
    cs = coefficients or [s.coefficient for s in r.left + r.right]
    left = " + ".join(_species_tex(s, c) for s, c in zip(r.left, cs, strict=False))
    if not r.right:
        return left
    right = " + ".join(_species_tex(s, c) for s, c in zip(r.right, cs[len(r.left) :], strict=False))
    return f"{left} \\rightarrow {right}"


def _counts(species: list[Species], coefficients: list[int]) -> dict[str, int]:
    total: dict[str, int] = {}
    for s, c in zip(species, coefficients, strict=True):
        for el, n in s.atoms.items():
            total[el] = total.get(el, 0) + n * c
    return total


def is_balanced(r: Reaction) -> bool:
    return _counts(r.left, [s.coefficient for s in r.left]) == _counts(
        r.right, [s.coefficient for s in r.right]
    )


def balance(r: Reaction) -> list[int] | None:
    """Smallest positive whole coefficients, or None if there is no single
    way to balance it (missing species, or several independent reactions)."""
    species = r.left + r.right
    elements = sorted({el for s in species for el in s.atoms})
    matrix = sp.Matrix(
        [
            [s.atoms.get(el, 0) * (1 if k < len(r.left) else -1) for k, s in enumerate(species)]
            for el in elements
        ]
    )
    null = matrix.nullspace()
    if len(null) != 1:
        return None
    v = null[0]
    denominators = [sp.fraction(x)[1] for x in v]
    scale = lcm(*[int(d) for d in denominators])
    ints = [int(x * scale) for x in v]
    if all(x < 0 for x in ints):
        ints = [-x for x in ints]
    if any(x <= 0 for x in ints):
        return None
    g = 0
    for x in ints:
        g = sp.gcd(g, x)
    return [int(x // g) for x in ints]


def analyze_chem(latex_rows: list[str]) -> ChemInsight | None:
    """None unless at least one row is chemistry; non-chemistry rows are
    left out (a formula area is either chemistry or mathematics)."""
    rows = [r for r in (read_reaction(x) for x in latex_rows) if r is not None]
    if not rows:
        return None
    species: list[str] = []
    for r in rows:
        for s in r.left + r.right:
            if s.formula not in species:
                species.append(s.formula)
    reactions = [r for r in rows if r.right]
    balanced = None if not reactions else all(is_balanced(r) for r in reactions)
    fixed = None
    if balanced is False:
        fixed = []
        for r in reactions:
            cs = None if is_balanced(r) else balance(r)
            fixed.append(reaction_tex(r, cs))
    return ChemInsight(rows, [reaction_tex(r) for r in rows], species, balanced, fixed)
