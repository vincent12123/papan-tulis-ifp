"""SymPy checks of recognized LaTeX and line splitting (SPEC 1.8, REQ-20)."""

from __future__ import annotations

import io
from pathlib import Path

import pytest
from PIL import Image, ImageDraw

from app.formula_math import build_graph, clean_latex, to_expression, to_formula
from app.formula_reader import OnnxFormulaReader, ReaderUnavailable, split_lines


def formula(latex: str) -> str | None:
    expr = to_expression(latex)
    return None if expr is None else to_formula(expr)


@pytest.mark.parametrize(
    ("latex", "expected"),
    [
        (r"y = x ^ { 2 } - 3", "y = x^2 - 3"),
        (r"y = A \sin x + B", "y = A*sin(x) + B"),
        (r"f ( x ) = 2 x + 1", "y = 2*x + 1"),
        (r"y = ( x + 1 ) / ( x - 2 )", "y = (x + 1)/(x - 2)"),
        (r"y = \frac { 1 } { x }", "y = 1/x"),
        (r"y = \sqrt { x }", "y = sqrt(x)"),
        (r"y = \operatorname { l o g } x", "y = log(x)"),
        (r"y = \ln x", "y = ln(x)"),
        (r"y = 3 ~ \operatorname { c o s } ~ 2 x", "y = 3*cos(2*x)"),
        (r"y = \l o g \varkappa", "y = log(x)"),
        (r"y = e ^ { x }", "y = exp(x)"),
        (r"y = | x |", "y = abs(x)"),
        (r"y = 2 \pi x", "y = 2*\u03c0*x"),
        (r"y = 0.5 x", "y = 0.5*x"),
        (r"x ^ { 2 } - 3 = y", "y = x^2 - 3"),
        (r"x ^ { 2 } + 1", "y = x^2 + 1"),
        (r"\mathbf { y } = \mathbf { x }", "y = x"),
    ],
)
def test_recognized_latex_becomes_a_panel_formula(latex, expected):
    assert formula(latex) == expected


@pytest.mark.parametrize(
    "latex",
    [
        r"y = x ^ { 2 } \lt 3",  # misread minus
        r"f ( x ) = \mathbb { \neg } x",  # junk symbols
        r"y = 2 x + I",  # 1 misread as I: imaginary unit
        r"x ^ { 2 } = 4",  # an equation, not a function of x
        r"y = \Box x",
        r"y = g ( x )",  # unknown function
        r"y = \int x d x",
        r"y = y + 1",
        r"y = 1 = 2",
        r"",
        r"\frac { d } { d x } x ^ { 2 }",
    ],
)
def test_ac85_anything_not_on_the_whitelist_is_dropped(latex):
    assert formula(latex) is None


def test_clean_latex_undoes_recognizer_quirks():
    assert clean_latex(r"y = ( x \! + \! 1 )") == "y = ( x + 1 )"
    assert clean_latex(r"y = \operatorname { s i n } x") == r"y = \sin x"
    assert clean_latex(r"y = \log x") == r"y = \log_{10} x"


def test_graph_has_params_axes_and_skips_bad_lines():
    graph = build_graph([r"y = x ^ { 2 } - 3", r"\Box", r"y = A \sin x + B"])
    assert graph["fungsi"] == ["y = x^2 - 3", "y = A*sin(x) + B"]
    assert graph["parameter"] == [
        {"nama": "A", "min": -5.0, "maks": 5.0, "nilai": 1.0},
        {"nama": "B", "min": -5.0, "maks": 5.0, "nilai": 1.0},
    ]
    axes = graph["sumbu"]
    assert (axes["x_min"], axes["x_maks"]) == (-6.28, 6.28), "trig gets ±2π"
    assert axes["y_min"] < -3 < 0 < axes["y_maks"]


@pytest.mark.parametrize(
    "block",
    [
        r"\begin{matrix} y = x ^ { 2 } - 3 \\ y = A \sin x + B \end{matrix}",
        r"\begin{array} { l } { y = x ^ { 2 } - 3 } \\ { y = A \sin x + B } \end{array}",
        r"\begin{aligned} y & = x ^ { 2 } - 3 \\ y & = A \sin x + B \end{aligned}",
    ],
)
def test_touching_lines_read_as_one_block_still_give_both_formulas(block):
    # Lines written close together reach the model as one image (REQ-20).
    graph = build_graph([block])
    assert graph["fungsi"] == ["y = x^2 - 3", "y = A*sin(x) + B"]
    assert [p["nama"] for p in graph["parameter"]] == ["A", "B"]


def test_graph_limits_and_empty_cases():
    assert build_graph([])["fungsi"] == []
    assert len(build_graph([f"y = {i} x" for i in range(1, 9)])["fungsi"]) == 4
    # Seven parameters is more than the panel shows: refuse rather than cut.
    assert build_graph([r"y = a x + b + c + d + f + g + h"])["fungsi"] == []
    # Nowhere drawable on the axis (sqrt of a negative number everywhere).
    assert build_graph([r"y = \sqrt { - x ^ { 2 } - 1 }"])["fungsi"] == []


def _png(img: Image.Image) -> bytes:
    buf = io.BytesIO()
    img.save(buf, "PNG")
    return buf.getvalue()


def test_lines_are_split_and_made_dark_on_white():
    board = Image.new("RGB", (400, 200), (20, 60, 40))  # dark board
    d = ImageDraw.Draw(board)
    d.rectangle((40, 30, 300, 60), fill="white")
    d.rectangle((40, 120, 200, 160), fill="white")
    d.point((390, 190), fill="white")  # a speck is not a line
    lines = split_lines(_png(board))
    assert len(lines) == 2
    first = lines[0].convert("L")
    assert first.getpixel((0, 0)) == 255, "background becomes white"
    assert first.getpixel((first.width // 2, first.height // 2)) == 0, "ink becomes black"


def test_empty_area_has_no_lines():
    assert split_lines(_png(Image.new("RGB", (300, 100), "white"))) == []


def test_missing_model_files_raise_unavailable(tmp_path):
    reader = OnnxFormulaReader(tmp_path / "tidak-ada")
    img = Image.new("RGB", (200, 80), "white")
    ImageDraw.Draw(img).rectangle((20, 20, 150, 50), fill="black")
    with pytest.raises(ReaderUnavailable):
        reader.read(_png(img))


MODEL = Path(__file__).resolve().parent.parent / "models" / "pix2text-mfr-1.5"


@pytest.mark.skipif(not (MODEL / "encoder_model.onnx").exists(), reason="model belum diunduh")
def test_real_model_reads_a_written_formula():
    from PIL import ImageFont

    img = Image.new("RGB", (700, 110), "white")
    font = ImageFont.truetype(
        "DejaVuSans.ttf" if Path("/usr/share/fonts").exists() else "arial.ttf", 56
    )
    ImageDraw.Draw(img).text((30, 15), "y = 2x + 1", font=font, fill="black")
    lines = OnnxFormulaReader(MODEL).read(_png(img))
    assert build_graph(lines)["fungsi"] == ["y = 2*x + 1"]
