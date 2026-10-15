"""Typeset formulas as transparent PNGs (SPEC 1.9, REQ-22 "Rapikan rumus").

matplotlib's mathtext draws the LaTeX that SymPy produced, in Computer Modern
like a printed textbook, in the ink color of the handwriting it replaces.
Several lines are stacked left-aligned in one picture.
"""

from __future__ import annotations

import io
import re
import threading

import matplotlib

matplotlib.use("Agg")
from matplotlib.figure import Figure
from PIL import Image

matplotlib.rcParams["mathtext.fontset"] = "cm"

FONT_SIZE = 40
DPI = 150
LINE_GAP = 0.35  # of a line's height
_COLOR = re.compile(r"^#[0-9A-Fa-f]{6}$")
_lock = threading.Lock()  # pyplot-free, but mathtext's caches are shared


def _line(latex: str, color: str) -> Image.Image:
    fig = Figure()
    fig.patch.set_alpha(0)
    fig.text(0, 0, f"${latex}$", fontsize=FONT_SIZE, color=color)
    buf = io.BytesIO()
    fig.savefig(buf, format="png", dpi=DPI, transparent=True, bbox_inches="tight", pad_inches=0.04)
    buf.seek(0)
    return Image.open(buf).convert("RGBA")


def _first_drawable(choices: tuple[str, ...], color: str) -> Image.Image:
    for i, latex in enumerate(choices):
        try:
            return _line(latex, color)
        except ValueError:  # mathtext ParseFatalException is a ValueError
            if i == len(choices) - 1:
                raise
    raise ValueError("tidak ada rumus")


def render(lines: list[str | tuple[str, ...]], color: str = "#1E293B") -> tuple[bytes, int, int]:
    """PNG bytes, width, height. Each line may give alternatives, tried in
    order (as written first, SymPy's form second). Raises ValueError when
    none can be drawn."""
    if not _COLOR.match(color):
        color = "#1E293B"
    with _lock:
        images = [_first_drawable((t,) if isinstance(t, str) else t, color) for t in lines]
    gap = int(max(i.height for i in images) * LINE_GAP)
    width = max(i.width for i in images)
    height = sum(i.height for i in images) + gap * (len(images) - 1)
    sheet = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    y = 0
    for img in images:
        sheet.paste(img, (0, y), img)
        y += img.height + gap
    out = io.BytesIO()
    sheet.save(out, "PNG", optimize=True)
    return out.getvalue(), width, height
