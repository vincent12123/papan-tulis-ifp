"""Kuis dari isi papan (SPEC 1.11, REQ-27)."""

from __future__ import annotations

import base64
import json

from app.ai import parse_quiz

from .conftest import auth

PNG = base64.b64encode(b"\x89PNG\r\n\x1a\n" + b"\x00" * 32).decode()

ANSWER = json.dumps(
    {
        "kuis": [
            {"kiri": "y = x^2 - 3", "kanan": "Parabola terbuka ke atas"},
            {"kiri": "**T = 2π√(L/g)**", "kanan": "Periode bandul"},
            {"kiri": "H2O", "kanan": "Air"},
        ]
    }
)


def test_ac140_ai_quiz_pairs_come_back_clean(client, fake_ai):
    fake_ai.answer = "Berikut kuisnya:\n" + ANSWER
    r = client.post("/ai/jalankan", headers=auth(), json={"jenis": "kuis", "gambar": PNG})
    assert r.status_code == 200
    data = r.json()
    assert data["hasil"] is None
    assert data["kuis"] == [
        {"kiri": "y = x^2 - 3", "kanan": "Parabola terbuka ke atas"},
        {"kiri": "T = 2π√(L/g)", "kanan": "Periode bandul"},
        {"kiri": "H2O", "kanan": "Air"},
    ]


def test_too_few_pairs_is_a_clear_refusal(client, fake_ai):
    fake_ai.answer = '{"kuis": [{"kiri": "a", "kanan": "b"}]}'
    r = client.post("/ai/jalankan", headers=auth(), json={"jenis": "kuis", "gambar": PNG})
    assert r.status_code == 422 and r.json()["kode"] == "tanpa_kuis"


def test_parse_quiz_drops_junk_duplicates_and_caps():
    text = json.dumps(
        {
            "kuis": [
                {"kiri": "A", "kanan": "1"},
                {"kiri": "A", "kanan": "2"},  # duplicate left
                {"kiri": "B", "kanan": "1"},  # duplicate right
                {"kiri": 3, "kanan": "x"},
                "bukan pasangan",
                {"kiri": "x" * 200, "kanan": "panjang"},
                *[{"kiri": f"S{i}", "kanan": f"J{i}"} for i in range(10)],
            ]
        }
    )
    pairs = parse_quiz(text)
    assert pairs[0] == {"kiri": "A", "kanan": "1"}
    assert len(pairs[1]["kiri"]) == 60
    assert len(pairs) == 6
    assert parse_quiz("tidak ada json") == []
    assert parse_quiz('{"kuis": "x"}') == []
