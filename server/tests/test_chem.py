"""Kimia + video eksperimen (SPEC 1.9, REQ-24)."""

from __future__ import annotations

import base64

import pytest

from app.formula_chem import analyze_chem, balance, read_reaction
from app.video_library import find_videos, load_catalog

from .conftest import auth

PNG = base64.b64encode(b"\x89PNG\r\n\x1a\n" + b"\x00" * 32).decode()


# --- reading what the recognizer writes ----------------------------------------


@pytest.mark.parametrize(
    ("latex", "species"),
    [
        (
            r"2 N a \, + \, \mathcal { C } \! \! \mid _ { 2 } \, \to \, 2 N a \mathcal { C } \! \! \mid",
            ["Na", "Cl2", "NaCl"],
        ),
        (r"\mathrm { C } _ { 6 } \mathrm { H } _ { 5 } \mathrm { O H }", ["C6H5OH"]),
        (
            r"\mathrm { H } _ { 2 } ^ { } \star \mathrm { O } _ { 2 } ^ { } \to \mathrm { H } _ { 2 } ^ { } \mathrm { O }",
            ["H2", "O2", "H2O"],
        ),
        (
            r"{ \sf N a O H + H C I } \to { \sf N a C I + H _ { 2 } O }",
            ["NaOH", "HCl", "NaCl", "H2O"],
        ),
        (
            r"\mathsf { F e } \mathsf { + O } _ { \mathsf { 2 } } \to \mathsf { F e } _ { \mathsf { 2 } } \mathsf { O } _ { \mathsf { 3 } }",
            ["Fe", "O2", "Fe2O3"],
        ),
        (r"\mathrm{Ca} ( \mathrm{OH} ) _ { 2 }", ["Ca(OH)2"]),
        (
            r"2 \mathrm{Na} + \mathrm{Cl}_{2} \xrightarrow{\Delta} 2 \mathrm{NaCl}",
            ["Na", "Cl2", "NaCl"],
        ),
    ],
)
def test_recognized_chemistry_is_read(latex, species):
    assert analyze_chem([latex]).species == species


@pytest.mark.parametrize(
    "latex",
    [
        r"y = x ^ { 2 } - 3",
        r"x ^ { 2 } = 4",
        r"A + B",  # A is no element
        r"B + C",  # single letters without an arrow: too likely mathematics
        r"\frac { 1 } { 2 }",
        r"Xy \to Q",
        r"",
        r"\to",
    ],
)
def test_mathematics_is_not_chemistry(latex):
    assert analyze_chem([latex]) is None


def test_atoms_are_counted_with_brackets():
    r = read_reaction(
        r"\mathrm{Ca} ( \mathrm{OH} ) _ { 2 } + 2 \mathrm{HCl} \to \mathrm{CaCl}_{2} + 2 \mathrm{H}_{2} \mathrm{O}"
    )
    assert r.left[0].atoms == {"Ca": 1, "O": 2, "H": 2}
    assert analyze_chem(
        [
            r"\mathrm{Ca}(\mathrm{OH})_{2} + 2\mathrm{HCl} \to \mathrm{CaCl}_{2} + 2\mathrm{H}_{2}\mathrm{O}"
        ]
    ).balanced


# --- balancing --------------------------------------------------------------


@pytest.mark.parametrize(
    ("latex", "fixed"),
    [
        (
            r"H_{2} + O_{2} \to H_{2}O",
            r"2\,\mathrm{H}_{2} + \mathrm{O}_{2} \rightarrow 2\,\mathrm{H}_{2}\mathrm{O}",
        ),
        (
            r"Fe + O_{2} \to Fe_{2}O_{3}",
            r"4\,\mathrm{Fe} + 3\,\mathrm{O}_{2} \rightarrow 2\,\mathrm{Fe}_{2}\mathrm{O}_{3}",
        ),
        (
            r"C_{3}H_{8} + O_{2} \to CO_{2} + H_{2}O",
            r"\mathrm{C}_{3}\mathrm{H}_{8} + 5\,\mathrm{O}_{2} \rightarrow 3\,\mathrm{C}\mathrm{O}_{2} + 4\,\mathrm{H}_{2}\mathrm{O}",
        ),
    ],
)
def test_unbalanced_reactions_are_balanced(latex, fixed):
    insight = analyze_chem([latex])
    assert insight.balanced is False
    assert insight.balanced_latex == [fixed]


def test_balanced_reactions_are_left_alone():
    insight = analyze_chem([r"2 Na + Cl_{2} \to 2 NaCl"])
    assert insight.balanced is True and insight.balanced_latex is None
    assert analyze_chem([r"NaCl"]).balanced is None, "nothing to balance"


def test_impossible_balance_is_not_invented():
    # Nitrogen appears only on the left: no coefficients can fix it.
    assert balance(read_reaction(r"N_{2} + H_{2} \to H_{2}O")) is None


# --- video catalog ----------------------------------------------------------


def _catalog(folder, text, files=("natrium.mp4",)):
    folder.mkdir(exist_ok=True)
    for f in files:
        (folder / f).write_bytes(b"\x00\x00\x00\x18ftypmp42")
    (folder / "katalog.toml").write_text(text, encoding="utf-8")


CATALOG = """
[[video]]
id = "natrium-klorin"
judul = "Reaksi natrium dengan gas klorin"
berkas = "natrium.mp4"
kata_kunci = ["Na", "Cl2", "NaCl"]

[[video]]
id = "hilang"
judul = "Berkasnya tidak ada"
berkas = "tidak-ada.mp4"
kata_kunci = ["Na"]

[[video]]
id = "keluar"
judul = "Di luar folder"
berkas = "../rahasia.mp4"
kata_kunci = ["Na"]

[[video]]
id = "Bukan Slug!"
judul = "Id tidak sah"
berkas = "natrium.mp4"
kata_kunci = ["Na"]
"""


def test_catalog_skips_broken_or_unsafe_entries(tmp_path):
    _catalog(tmp_path / "video", CATALOG)
    videos = load_catalog(tmp_path / "video")
    assert [v.id for v in videos] == ["natrium-klorin"]
    assert find_videos(videos, ["NaCl"])[0].title.startswith("Reaksi natrium")
    assert find_videos(videos, ["H2O"]) == []


def test_missing_or_broken_catalog_means_no_videos(tmp_path):
    assert load_catalog(tmp_path / "tidak-ada") == []
    _catalog(tmp_path / "v", "ini bukan toml [[[")
    assert load_catalog(tmp_path / "v") == []


@pytest.fixture
def chem_client(client, settings, tmp_path, fake_reader):
    settings.video_dir = tmp_path / "video"
    _catalog(settings.video_dir, CATALOG)
    fake_reader.lines = [r"\mathrm{H}_{2} + \mathrm{O}_{2} \to \mathrm{H}_{2}\mathrm{O}"]
    return client


def test_ac120_chemistry_area_offers_tidy_balance_and_nothing_else(chem_client):
    r = chem_client.post("/rumus/kenali", headers=auth(), json={"gambar": PNG})
    data = r.json()
    assert r.status_code == 200 and data["jenis"] == "kimia"
    assert data["zat"] == ["H2", "O2", "H2O"]
    assert data["setara"] is False
    assert data["penyelesaian"]["baris"] == [
        r"2\,\mathrm{H}_{2} + \mathrm{O}_{2} \rightarrow 2\,\mathrm{H}_{2}\mathrm{O}"
    ]
    assert data["grafik"] is None and data["video"] == []
    assert base64.b64decode(data["rapi"]["gambar"]).startswith(b"\x89PNG")


def test_ac121_matching_videos_are_listed_and_streamed(chem_client, fake_reader):
    fake_reader.lines = [r"2 Na + Cl_{2} \to 2 NaCl"]
    data = chem_client.post("/rumus/kenali", headers=auth(), json={"gambar": PNG}).json()
    assert data["setara"] is True and data["penyelesaian"] is None
    assert data["video"] == [{"id": "natrium-klorin", "judul": "Reaksi natrium dengan gas klorin"}]

    r = chem_client.get("/video/natrium-klorin", headers=auth())
    assert r.status_code == 200 and r.headers["content-type"] == "video/mp4"
    part = chem_client.get("/video/natrium-klorin", headers={**auth(), "Range": "bytes=0-3"})
    assert part.status_code == 206 and len(part.content) == 4


def test_videos_need_the_pin_and_a_catalog_id(chem_client):
    assert chem_client.get("/video/natrium-klorin").status_code == 401
    r = chem_client.get("/video/keluar", headers=auth())
    assert r.status_code == 404 and r.json()["kode"] == "video_tidak_ada"
    assert chem_client.get("/video/..%2F..%2Fpapan.sqlite3", headers=auth()).status_code == 404


def test_math_answers_keep_the_same_shape(client):
    data = client.post("/rumus/kenali", headers=auth(), json={"gambar": PNG}).json()
    assert data["jenis"] == "fungsi" and data["zat"] == [] and data["video"] == []
