"""Rekam kelas + ringkasan (SPEC 1.9, REQ-25)."""

from __future__ import annotations

import base64
import json
import time
from pathlib import Path

from app.class_summary import plain_text

from .conftest import auth

AUDIO = b"\x00\x00\x00\x20ftypM4A " + b"\x01" * 2000


def upload(client, body=AUDIO, formulas=None, headers=None):
    h = {**auth(), "Content-Type": "audio/mp4", **(headers or {})}
    if formulas is not None:
        h["X-Rumus"] = base64.b64encode(json.dumps(formulas).encode()).decode()
    return client.post("/kelas/ringkas", headers=h, content=body)


def wait(client, job_id, until=("selesai", "gagal")):
    for _ in range(100):
        data = client.get(f"/kelas/ringkas/{job_id}", headers=auth()).json()
        if data["status"] in until:
            return data
        time.sleep(0.02)
    raise AssertionError(f"job stuck at {data}")


def test_ac130_recording_becomes_a_plain_text_summary(client, fake_ai, fake_transcriber):
    fake_ai.answer = "**Judul:** Fungsi kuadrat\n## Poin penting\n- Grafik $y = x^2 - 3$"
    r = upload(client, formulas=["y = x^{2} - 3"])
    assert r.status_code == 200
    job = r.json()
    assert job["status"] in ("antri", "mentranskrip", "meringkas", "selesai")

    data = wait(client, job["id"])
    assert data["status"] == "selesai"
    assert data["ringkasan"] == "Judul: Fungsi kuadrat\nPoin penting\n- Grafik y = x^2 - 3"
    prompt = json.dumps(fake_ai.bodies()[-1])
    assert "fungsi kuadrat" in prompt and "y = x^{2} - 3" in prompt
    # The recording reached Whisper whole, and is gone afterwards (NFR-21).
    path, content = fake_transcriber.files[0]
    assert content == AUDIO
    assert not Path(path).exists()


def test_silence_is_reported(client, fake_transcriber, fake_ai):
    fake_transcriber.text = "  "
    data = wait(client, upload(client).json()["id"])
    assert data == {**data, "status": "gagal", "kode": "tanpa_suara", "ringkasan": None}
    assert fake_ai.requests == [], "no AI call without speech"


def test_ai_down_is_reported_and_the_audio_still_deleted(client, fake_ai, fake_transcriber):
    for pid in ("ollama", "openai", "claude", "gemini", "lainnya"):
        fake_ai.fail[pid] = "down"
    data = wait(client, upload(client).json()["id"])
    assert data["status"] == "gagal" and data["kode"] == "ai_tidak_tersedia"
    assert not Path(fake_transcriber.files[0][0]).exists()


def test_transcriber_crash_is_a_failed_job(client, fake_transcriber):
    fake_transcriber.error = RuntimeError("model rusak")
    data = wait(client, upload(client).json()["id"])
    assert data["status"] == "gagal" and data["kode"] == "gagal"


def test_bad_uploads_are_refused(client, monkeypatch):
    assert upload(client, body=b"").json()["kode"] == "rekaman_kosong"
    r = upload(client, headers={"X-Rumus": "bukan base64!!"})
    assert r.status_code == 422 and r.json()["kode"] == "rumus_rusak"
    bad = base64.b64encode(json.dumps({"a": 1}).encode()).decode()
    assert upload(client, headers={"X-Rumus": bad}).json()["kode"] == "rumus_rusak"
    monkeypatch.setattr("app.main.MAX_AUDIO_BYTES", 100)
    r = upload(client)
    assert r.status_code == 413 and r.json()["kode"] == "rekaman_terlalu_besar"


def test_needs_the_pin_and_a_known_job(client):
    assert client.post("/kelas/ringkas", content=AUDIO).status_code == 401
    assert client.get("/kelas/ringkas/abc").status_code == 401
    r = client.get("/kelas/ringkas/tidak-ada", headers=auth())
    assert r.status_code == 404 and r.json()["kode"] == "ringkasan_tidak_ada"


def test_log_has_no_speech_or_summary(client, settings, fake_ai):
    from app.db import Database

    fake_ai.answer = "Ringkasan rahasia"
    wait(client, upload(client).json()["id"])
    for _ in range(50):
        db = Database(settings.db_path)
        try:
            rows = [r for r in db.ai_log() if r["jenis"] == "ringkas_kelas"]
        finally:
            db.close()
        if rows:
            break
        time.sleep(0.02)
    assert rows and rows[-1]["status"] == "berhasil"
    assert "rahasia" not in str(rows) and "kuadrat" not in str(rows)


def test_plain_text_strips_markdown_and_latex():
    assert plain_text("## Judul\n**Tebal** dan `kode` $x^2$") == "Judul\nTebal dan kode x^2"
