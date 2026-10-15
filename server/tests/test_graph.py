"""Images to vision models (P-03) and "Jadikan grafik" (REQ-20, SPEC 1.8)."""

from __future__ import annotations

import base64
import json

import pytest

from app.ai import GraphUnreadable, parse_graph

from .conftest import auth

# Smallest valid PNG header + body is enough: providers are faked.
PNG = base64.b64encode(b"\x89PNG\r\n\x1a\n" + b"\x00" * 32).decode()

GRAPH_ANSWER = json.dumps(
    {
        "fungsi": ["y = x^2 - 3", "y = A*sin(x) + B"],
        "parameter": [
            {"nama": "A", "min": -5, "maks": 5, "nilai": 1},
            {"nama": "B", "min": -5, "maks": 5, "nilai": 0},
        ],
        "sumbu": {"x_min": -6.28, "x_maks": 6.28, "y_min": -5, "y_maks": 5},
    }
)


def run(client, **body):
    return client.post("/ai/jalankan", headers=auth(), json=body)


# --- images reach each provider in its own format --------------------------


@pytest.mark.parametrize("pid", ["ollama", "openai", "claude", "gemini", "lainnya"])
def test_image_is_sent_in_each_provider_format(client, fake_ai, pid):
    r = run(client, jenis="pecah_soal", gambar=PNG, penyedia=pid)
    assert r.status_code == 200
    body = fake_ai.bodies()[-1]
    assert body["model"] if "model" in body else True
    text = json.dumps(body)
    assert PNG in text
    if pid == "ollama":
        assert body["messages"][1]["images"] == [PNG]
    elif pid in ("openai", "lainnya"):
        part = body["messages"][1]["content"][1]
        assert part["image_url"]["url"] == f"data:image/png;base64,{PNG}"
    elif pid == "claude":
        assert body["messages"][0]["content"][0]["source"]["data"] == PNG
    else:
        assert body["contents"][0]["parts"][0]["inline_data"]["data"] == PNG


def test_ac88_image_goes_to_a_model_that_reads_images(client, fake_ai):
    # Panel picked m1 (text only); m2 reads images.
    run(client, jenis="ringkas", gambar=PNG, penyedia="openai", model="m1")
    assert fake_ai.bodies()[-1]["model"] == "m2"


def test_ac88_fallback_also_uses_an_image_model(client, fake_ai):
    fake_ai.fail["claude"] = 429
    r = run(client, jenis="ringkas", gambar=PNG, penyedia="claude")
    data = r.json()
    assert data["penyedia"] == "ollama" and data["model"] == "m2"
    assert data["alasan_cadangan"] == "kuota_habis"


def test_text_only_requests_keep_the_chosen_model(client, fake_ai):
    run(client, jenis="ringkas", isi="isi", penyedia="openai", model="m1")
    assert fake_ai.bodies()[-1]["model"] == "m1"


@pytest.mark.parametrize(
    ("body", "code"),
    [
        ({"jenis": "ringkas"}, "isi_kosong"),
        ({"jenis": "grafik", "isi": "y = x"}, "isi_kosong"),
        ({"jenis": "ringkas", "gambar": "bukan base64!!"}, "gambar_rusak"),
        (
            {"jenis": "ringkas", "gambar": base64.b64encode(b"GIF89a....").decode()},
            "gambar_rusak",
        ),
    ],
)
def test_bad_requests_are_refused_before_calling_ai(client, fake_ai, body, code):
    r = run(client, **body)
    assert r.status_code == 422
    assert r.json()["kode"] == code
    assert fake_ai.requests == []


# --- Jadikan grafik: formula recognizer + SymPy, no AI (SPEC 1.8) ---------


def test_ac83_graph_comes_from_the_recognizer_not_the_ai(client, fake_ai, fake_reader):
    r = run(client, jenis="grafik", gambar=PNG, penyedia="claude")
    assert r.status_code == 200
    data = r.json()
    assert data["hasil"] is None
    assert data["nama"] == "Pengenal rumus" and data["model"] == "pix2text-mfr-1.5"
    graph = data["grafik"]
    assert graph["fungsi"] == ["y = x^2 - 3", "y = A*sin(x) + B"]
    assert [p["nama"] for p in graph["parameter"]] == ["A", "B"]
    assert graph["sumbu"]["x_min"] == -6.28
    assert fake_ai.requests == [], "no language model is called"
    assert fake_reader.images and fake_reader.images[0].startswith(b"\x89PNG")


def test_no_formula_found_is_a_clear_refusal(client, fake_reader):
    fake_reader.lines = []
    r = run(client, jenis="grafik", gambar=PNG)
    assert r.status_code == 422
    assert r.json()["kode"] == "tanpa_rumus"


def test_ac85_unreadable_recognizer_output_is_a_clear_refusal(client, fake_reader):
    fake_reader.lines = [r"\mathbb { \neg } \Box", r"x ^ { 2 } = 4", r"y = \sqrt { - 1 } + I"]
    assert run(client, jenis="grafik", gambar=PNG).json()["kode"] == "tanpa_rumus"


def test_missing_model_is_reported_as_unavailable(client, fake_reader):
    from app.formula_reader import ReaderUnavailable

    fake_reader.error = ReaderUnavailable("berkas model tidak ada")
    r = run(client, jenis="grafik", gambar=PNG)
    assert r.status_code == 503
    assert r.json()["kode"] == "ai_tidak_tersedia"


def test_broken_image_is_refused(client, fake_reader):
    fake_reader.error = OSError("cannot identify image file")
    assert run(client, jenis="grafik", gambar=PNG).json()["kode"] == "gambar_rusak"


def test_ac85_code_and_junk_are_filtered_out():
    graph = parse_graph(
        json.dumps(
            {
                "fungsi": [
                    "__import__('os').system('rm -rf /')",
                    "y = x^2",
                    "x; rm",
                    42,
                    "y" * 500,
                ],
                "parameter": [
                    {"nama": "A", "min": 5, "maks": -5, "nilai": 99},
                    {"nama": "x", "min": 0, "maks": 1, "nilai": 0},
                    {"nama": "ab", "min": 0, "maks": 1, "nilai": 0},
                    {"nama": "B", "min": "kiri", "maks": 1, "nilai": 0},
                    {"nama": "A", "min": 0, "maks": 1, "nilai": 0},
                ],
                "sumbu": {"x_min": 5, "x_maks": -5, "y_min": float("nan"), "y_maks": 1},
            }
        ).replace("NaN", '"nan"')
    )
    assert graph["fungsi"] == ["y = x^2"]
    assert graph["parameter"] == [{"nama": "A", "min": -5.0, "maks": 5.0, "nilai": 5.0}]
    assert graph["sumbu"] == {"x_min": -10.0, "x_maks": 10.0, "y_min": -10.0, "y_maks": 10.0}


def test_limits_on_number_of_functions_and_params():
    graph = parse_graph(
        json.dumps(
            {
                "fungsi": [f"y = {i}x" for i in range(10)],
                "parameter": [{"nama": n, "min": 0, "maks": 1, "nilai": 0} for n in "ABCDEFGH"],
            }
        )
    )
    assert len(graph["fungsi"]) == 4
    assert len(graph["parameter"]) == 6


def test_unreadable_answers_raise():
    with pytest.raises(GraphUnreadable):
        parse_graph("tidak ada json di sini")
    with pytest.raises(GraphUnreadable):
        parse_graph('{"fungsi": "y = x"}')


def test_graph_log_has_no_formula_or_image(client, settings):
    from app.db import Database

    run(client, jenis="grafik", gambar=PNG)
    db = Database(settings.db_path)
    try:
        row = db.ai_log()[-1]
    finally:
        db.close()
    assert row["jenis"] == "grafik" and row["status"] == "berhasil"
    assert "sin" not in str(row) and PNG not in str(row)
