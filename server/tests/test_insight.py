"""Menu pintar: recognize, tidy, solve (SPEC 1.9, REQ-22)."""

from __future__ import annotations

import base64
import io

import pytest
from PIL import Image

from app.formula_insight import analyze
from app.formula_render import render

from .conftest import auth

PNG = base64.b64encode(b"\x89PNG\r\n\x1a\n" + b"\x00" * 32).decode()


def kenali(client, **body):
    return client.post("/rumus/kenali", headers=auth(), json={"gambar": PNG, **body})


# --- what kind of area ------------------------------------------------------


def test_functions_offer_a_graph():
    insight = analyze([r"y = x ^ { 2 } - 3", r"y = A \sin x + B"])
    assert insight.kind == "fungsi"
    assert insight.graph["fungsi"] == ["y = x^2 - 3", "y = A*sin(x) + B"]
    assert insight.solution is None


@pytest.mark.parametrize(
    ("lines", "solution"),
    [
        ([r"x ^ { 2 } = 4"], ["x = -2", "x = 2"]),
        ([r"x ^ { 2 } - 5 x + 6 = 0"], ["x = 2", "x = 3"]),
        ([r"2 x + 3 = 7"], ["x = 2"]),
        ([r"2 x + y = 5", r"x - y = 1"], [r"x = 2,\; y = 1"]),
        ([r"x ^ { 2 } + 1 = 0"], []),  # no real solution
        ([r"\frac { 1 } { x } = 2"], [r"x = \frac{1}{2}"]),
    ],
)
def test_equations_are_solved_exactly(lines, solution):
    insight = analyze(lines)
    assert insight.kind == "persamaan"
    assert insight.solution == solution


@pytest.mark.parametrize(
    "lines",
    [
        [r"x + y = 5"],  # infinitely many solutions
        [r"\sin x = 0.5"],  # not polynomial: never let SymPy run long
        [r"x ^ { 7 } - x = 1"],  # degree above 4
        [r"a x + b = 0"],  # two unknowns, one equation
    ],
)
def test_solve_is_not_offered_when_it_cannot_be_exact_and_quick(lines):
    insight = analyze(lines)
    assert insight.kind == "persamaan"
    assert insight.solution is None


def test_tidy_keeps_the_formula_as_written():
    insight = analyze([r"\frac { 1 } { 2 } + \frac { 1 } { 3 }"])
    assert insight.kind == "ekspresi"
    # Not computed to 5/6; full-size fractions for reading from afar.
    assert insight.rows[0].latex == r"\dfrac {1} {2} + \dfrac {1} {3}"
    assert insight.rows[0].tidy == r"\frac{5}{6}", "SymPy form only as fallback"


def test_written_form_is_ready_for_mathtext():
    rows = analyze([r"y = x ^ { 2 } - 3", r"y = A \sin x + B"]).rows
    # Spaces around ^ made mathtext drop the superscript ("x 2").
    assert rows[0].latex == "y = x^{2} - 3"
    # "A sin x" must not read as "Asin x".
    assert rows[1].latex == r"y = A\,\sin x + B"


def test_written_log_drops_the_internal_base_marker():
    row = analyze([r"y = \operatorname { l o g } x"]).rows[0]
    assert row.latex == r"y = \log x"


def test_ac85_junk_is_not_a_formula():
    assert analyze([r"\Box", r"\mathbb { \neg }", r"y = 2 x + I"]) is None
    assert analyze([]) is None


def test_touching_lines_are_split():
    insight = analyze([r"\begin{matrix} x + y = 3 \\ x - y = 1 \end{matrix}"])
    assert insight.solution == [r"x = 2,\; y = 1"]


# --- typeset picture --------------------------------------------------------


def test_render_stacks_lines_in_the_ink_color():
    png, w, h = render(["x^{2} = 4", "x = 2"], "#DC2626")
    img = Image.open(io.BytesIO(png))
    assert img.mode == "RGBA" and (img.width, img.height) == (w, h)
    assert img.getpixel((0, 0))[3] == 0, "transparent background"
    inked = [p for p in img.getdata() if p[3] > 200]
    assert inked and all(p[0] > 150 and p[1] < 100 for p in inked[:50])


def test_render_falls_back_to_the_second_form():
    _, w, _ = render([(r"\undefinedcommand x", "x")])
    assert w > 0
    with pytest.raises(ValueError):
        render([r"\undefinedcommand x"])


def test_bad_color_falls_back_to_dark_ink():
    png, _, _ = render(["x"], "red; rm -rf")
    assert png.startswith(b"\x89PNG")


# --- endpoint ---------------------------------------------------------------


def test_ac90_endpoint_needs_the_pin(client):
    r = client.post("/rumus/kenali", json={"gambar": PNG})
    assert r.status_code == 401


def test_function_area_returns_graph_and_tidy_picture(client, fake_ai, fake_reader):
    r = kenali(client, warna="#2563EB")
    assert r.status_code == 200
    data = r.json()
    assert data["jenis"] == "fungsi"
    assert data["grafik"]["fungsi"] == ["y = x^2 - 3", "y = A*sin(x) + B"]
    assert data["penyelesaian"] is None
    tidy = base64.b64decode(data["rapi"]["gambar"])
    assert tidy.startswith(b"\x89PNG") and data["rapi"]["lebar"] > data["rapi"]["tinggi"]
    assert fake_ai.requests == [], "no language model"


def test_equation_area_returns_solution_picture(client, fake_reader):
    fake_reader.lines = [r"x ^ { 2 } = 4"]
    data = kenali(client).json()
    assert data["jenis"] == "persamaan" and data["grafik"] is None
    assert data["penyelesaian"]["baris"] == ["x = -2", "x = 2"]
    assert base64.b64decode(data["penyelesaian"]["gambar"]).startswith(b"\x89PNG")


def test_no_real_solution_still_gets_a_picture(client, fake_reader):
    fake_reader.lines = [r"x ^ { 2 } + 1 = 0"]
    solution = kenali(client).json()["penyelesaian"]
    assert solution["baris"] == [] and solution["gambar"]


def test_nothing_recognized_is_a_clear_refusal(client, fake_reader):
    fake_reader.lines = [r"\Box"]
    r = kenali(client)
    assert r.status_code == 422 and r.json()["kode"] == "tanpa_rumus"


@pytest.mark.parametrize(
    ("body", "code"),
    [
        ({"gambar": "bukan base64!!"}, "gambar_rusak"),
        ({"gambar": base64.b64encode(b"GIF89a").decode()}, "gambar_rusak"),
    ],
)
def test_bad_images_are_refused_before_reading(client, fake_reader, body, code):
    r = client.post("/rumus/kenali", headers=auth(), json=body)
    assert r.status_code == 422 and r.json()["kode"] == code
    assert fake_reader.images == []


def test_reader_failure_is_unavailable(client, fake_reader):
    from app.formula_reader import ReaderUnavailable

    fake_reader.error = ReaderUnavailable("model hilang")
    r = kenali(client)
    assert r.status_code == 503 and r.json()["kode"] == "ai_tidak_tersedia"


def test_log_has_no_formula_or_image(client, settings):
    from app.db import Database

    kenali(client)
    db = Database(settings.db_path)
    try:
        row = db.ai_log()[-1]
    finally:
        db.close()
    assert row["jenis"] == "kenali" and row["status"] == "berhasil"
    assert "sin" not in str(row) and PNG not in str(row)
