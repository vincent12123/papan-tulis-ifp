from __future__ import annotations

import logging
from pathlib import Path

import pytest

from app.cli import set_pin
from app.config import ConfigError, load_providers
from app.db import Database
from app.security import PIN_KEY, hash_pin, pin_problem, verify_pin

from .conftest import PIN, auth

# --- PIN and access (NF-01, NF-01b, AC-91, AC-92, AC-96..AC-98) --------------


def test_health_needs_no_pin(client):
    assert client.get("/sehat").json() == {"status": "ok"}


@pytest.mark.parametrize("path", ["/koneksi", "/ai/penyedia"])
def test_nf01_every_route_needs_the_pin(client, path):
    r = client.get(path)
    assert r.status_code == 401
    assert r.json()["kode"] == "pin_salah"
    assert client.get(path, headers=auth("000000")).status_code == 401
    assert client.get(path, headers=auth()).status_code == 200


def test_ac92_correct_pin_connects(client):
    assert client.get("/koneksi", headers=auth()).json()["status"] == "ok"


def test_ac96_five_wrong_pins_lock_for_five_minutes(client, clock):
    for _ in range(4):
        assert client.get("/koneksi", headers=auth("111111")).status_code == 401
    r = client.get("/koneksi", headers=auth("111111"))
    assert r.status_code == 429
    assert r.json()["pesan"] == "PIN salah 5 kali. Coba lagi dalam 5 menit."
    # Even the right PIN is refused while locked.
    assert client.get("/koneksi", headers=auth()).status_code == 429
    clock.now += 301
    assert client.get("/koneksi", headers=auth()).status_code == 200


def test_correct_pin_resets_the_failure_count(client):
    for _ in range(4):
        client.get("/koneksi", headers=auth("111111"))
    assert client.get("/koneksi", headers=auth()).status_code == 200
    for _ in range(4):
        assert client.get("/koneksi", headers=auth("111111")).status_code == 401


def test_pin_not_set_on_server(tmp_path, fake_ai, clock):
    import httpx
    from fastapi.testclient import TestClient

    from app.config import Settings
    from app.main import create_app

    from .conftest import default_providers

    s = Settings(data_dir=tmp_path / "kosong", providers_file=tmp_path / "x.toml")
    app = create_app(
        s,
        providers=default_providers(),
        http_client=httpx.AsyncClient(transport=httpx.MockTransport(fake_ai.handler)),
        clock=clock,
    )
    with TestClient(app) as c:
        r = c.get("/koneksi", headers=auth())
    assert r.status_code == 503
    assert r.json()["kode"] == "pin_belum_diatur"


def test_pin_hash_is_scrypt_and_verifies():
    stored = hash_pin("482915")
    assert stored.startswith("scrypt$")
    assert "482915" not in stored
    assert verify_pin("482915", stored)
    assert not verify_pin("482916", stored)
    assert not verify_pin("482915", "rusak")


@pytest.mark.parametrize(
    ("pin", "message"),
    [
        ("12345", "PIN baru minimal 6 angka."),
        ("12ab56", "PIN baru minimal 6 angka."),
        ("123456", "PIN baru terlalu mudah ditebak. Hindari angka berurutan atau berulang."),
        ("654321", "PIN baru terlalu mudah ditebak. Hindari angka berurutan atau berulang."),
        ("111111", "PIN baru terlalu mudah ditebak. Hindari angka berurutan atau berulang."),
        ("482915", None),
    ],
)
def test_ac97_new_pin_rules(pin, message):
    assert pin_problem(pin) == message


def test_ac97_change_pin_validation(client):
    r = client.post("/admin/pin", json={"pin_lama": PIN, "pin_baru": "123456"})
    assert r.status_code == 422
    assert "mudah ditebak" in r.json()["pesan"]
    r = client.post("/admin/pin", json={"pin_lama": PIN, "pin_baru": PIN})
    assert r.json()["pesan"] == "PIN baru tidak boleh sama dengan PIN lama."
    r = client.post("/admin/pin", json={"pin_lama": "999999", "pin_baru": "730518"})
    assert r.status_code == 401
    assert r.json()["pesan"] == "PIN lama salah. PIN admin tidak berubah."


def test_ac98_changed_pin_locks_out_the_old_one(client, settings):
    r = client.post("/admin/pin", json={"pin_lama": PIN, "pin_baru": "730518"})
    assert r.status_code == 200
    assert client.get("/koneksi", headers=auth(PIN)).status_code == 401
    assert client.get("/koneksi", headers=auth("730518")).status_code == 200
    db = Database(settings.db_path)
    try:
        stored = db.get_setting(PIN_KEY)
        assert stored.startswith("scrypt$") and "730518" not in stored
        log = db._conn.execute("SELECT * FROM log_pin").fetchall()
        assert len(log) == 1 and "730518" not in str(log)
    finally:
        db.close()


def test_wrong_old_pin_counts_toward_the_lockout(client):
    for _ in range(4):
        client.post("/admin/pin", json={"pin_lama": "999999", "pin_baru": "730518"})
    r = client.post("/admin/pin", json={"pin_lama": "999999", "pin_baru": "730518"})
    assert r.status_code == 429


def test_operator_can_reset_the_pin(settings, client):
    assert set_pin(settings, "123456") is not None  # too easy
    assert set_pin(settings, "604728") is None
    assert client.get("/koneksi", headers=auth("604728")).status_code == 200


def test_proxy_address_is_used_only_when_trusted(settings, fake_ai, clock):
    import httpx
    from fastapi.testclient import TestClient

    from app.main import create_app

    from .conftest import default_providers

    settings.trust_proxy = True
    app = create_app(
        settings,
        providers=default_providers(),
        http_client=httpx.AsyncClient(transport=httpx.MockTransport(fake_ai.handler)),
        clock=clock,
    )
    with TestClient(app) as c:
        for _ in range(5):
            c.get("/koneksi", headers={**auth("111111"), "CF-Connecting-IP": "1.1.1.1"})
        # Another panel behind the same tunnel is not locked out.
        r = c.get("/koneksi", headers={**auth(), "CF-Connecting-IP": "2.2.2.2"})
        assert r.status_code == 200


# --- providers (AC-99, REQ-19) ---------------------------------------------


def test_provider_list_shows_only_active_ones(client):
    data = client.get("/ai/penyedia", headers=auth()).json()
    assert data["bawaan"] == "ollama"
    ids = [p["id"] for p in data["penyedia"]]
    assert "mati" not in ids and ids[0] == "ollama"
    assert data["penyedia"][0]["model"][1] == {"nama": "m2", "dukung_gambar": True}
    assert "rahasia" not in str(data), "API keys never leave the server"


def test_load_providers_reads_keys_from_env_only(tmp_path: Path):
    f = tmp_path / "penyedia.toml"
    f.write_text(
        'bawaan = "ollama"\n'
        "[[penyedia]]\n"
        'id = "ollama"\njenis_adaptor = "ollama"\nkunci_api_env = "K_OLLAMA"\n'
        'model_bawaan = "a"\n'
        '[[penyedia.model]]\nnama = "a"\n',
        encoding="utf-8",
    )
    cfg = load_providers(f, env={"K_OLLAMA": "abc"})
    assert cfg.get("ollama").api_key == "abc"
    assert cfg.get("ollama").base_url == "https://ollama.com"


@pytest.mark.parametrize(
    "body",
    [
        '[[penyedia]]\nid = "x"\njenis_adaptor = "palsu"\n[[penyedia.model]]\nnama = "a"\n',
        '[[penyedia]]\nid = "x"\njenis_adaptor = "openai_kompatibel"\n'
        '[[penyedia.model]]\nnama = "a"\n',
        '[[penyedia]]\nid = "ollama"\njenis_adaptor = "ollama"\n',
    ],
)
def test_invalid_provider_files_are_rejected(tmp_path: Path, body):
    f = tmp_path / "penyedia.toml"
    f.write_text(body, encoding="utf-8")
    with pytest.raises(ConfigError):
        load_providers(f, env={})


def test_example_provider_file_is_valid():
    cfg = load_providers(Path(__file__).parent.parent / "penyedia.contoh.toml", env={})
    assert [p.id for p in cfg.active()] == ["ollama"]
    assert {p.adapter for p in cfg.providers} == {
        "ollama",
        "openai",
        "anthropic",
        "gemini",
        "openai_kompatibel",
    }


# --- AI calls (AC-77..AC-82) -------------------------------------------------


@pytest.mark.parametrize("pid", ["ollama", "openai", "claude", "gemini", "lainnya"])
def test_ac81_each_adapter_speaks_its_provider_format(client, fake_ai, pid):
    r = client.post(
        "/ai/jalankan",
        headers=auth(),
        json={"jenis": "pecah_soal", "isi": "2x + 3 = 7", "penyedia": pid, "model": "m2"},
    )
    assert r.status_code == 200
    data = r.json()
    assert data["hasil"] == f"jawaban dari {pid}"
    assert data["penyedia"] == pid and data["model"] == "m2"
    assert data["cadangan_dari"] is None
    req = fake_ai.requests[-1]
    body = fake_ai.bodies()[-1]
    assert "2x + 3 = 7" in str(body)
    if pid == "claude":
        assert req.headers["x-api-key"] == "rahasia-claude"
    elif pid == "gemini":
        assert req.headers["x-goog-api-key"] == "rahasia-gemini"
        assert "key=" not in str(req.url)
    else:
        assert req.headers["authorization"] == f"Bearer rahasia-{pid}"


@pytest.mark.parametrize(
    ("failure", "reason"),
    [
        (429, "kuota_habis"),
        (401, "kunci_ditolak"),
        (404, "model_tidak_ada"),
        ("down", "tidak_terjangkau"),
        ("timeout", "batas_waktu"),
    ],
)
def test_ac78_failed_provider_falls_back_to_ollama(client, fake_ai, settings, failure, reason):
    fake_ai.fail["claude"] = failure
    r = client.post(
        "/ai/jalankan",
        headers=auth(),
        json={"jenis": "ringkas", "isi": "isi papan", "penyedia": "claude"},
    )
    assert r.status_code == 200
    data = r.json()
    assert data["penyedia"] == "ollama"
    assert data["hasil"] == "jawaban dari ollama"
    assert data["cadangan_dari"] == "claude"
    assert data["cadangan_dari_nama"] == "Claude"
    assert data["alasan_cadangan"] == reason
    db = Database(settings.db_path)
    try:
        row = db.ai_log()[-1]
    finally:
        db.close()
    assert row["cadangan_dari"] == "claude" and row["alasan_cadangan"] == reason
    assert row["status"] == "berhasil" and row["penyedia"] == "ollama"


def test_ac79_both_failing_means_ai_unavailable(client, fake_ai, settings):
    fake_ai.fail["claude"] = 500
    fake_ai.fail["ollama"] = "down"
    r = client.post(
        "/ai/jalankan",
        headers=auth(),
        json={"jenis": "ringkas", "isi": "isi", "penyedia": "claude"},
    )
    assert r.status_code == 503
    assert r.json()["kode"] == "ai_tidak_tersedia"
    db = Database(settings.db_path)
    try:
        assert db.ai_log()[-1]["status"] == "gagal"
    finally:
        db.close()


def test_ac80_ollama_failing_is_not_retried(client, fake_ai):
    fake_ai.fail["ollama"] = 429
    r = client.post(
        "/ai/jalankan",
        headers=auth(),
        json={"jenis": "ringkas", "isi": "isi", "penyedia": "ollama"},
    )
    assert r.status_code == 503
    assert len(fake_ai.requests) == 1


def test_ac82_inactive_choice_uses_ollama_and_says_so(client, fake_ai):
    r = client.post(
        "/ai/jalankan",
        headers=auth(),
        json={"jenis": "soal_serupa", "isi": "soal", "penyedia": "mati", "model": "m1"},
    )
    data = r.json()
    assert data["penyedia"] == "ollama"
    assert data["cadangan_dari"] == "mati"
    assert data["alasan_cadangan"] == "tidak_aktif"


def test_no_choice_uses_the_default_provider(client):
    data = client.post(
        "/ai/jalankan", headers=auth(), json={"jenis": "ringkas", "isi": "isi"}
    ).json()
    assert data["penyedia"] == "ollama" and data["cadangan_dari"] is None


def test_unknown_model_uses_the_provider_default(client, fake_ai):
    client.post(
        "/ai/jalankan",
        headers=auth(),
        json={"jenis": "ringkas", "isi": "isi", "penyedia": "openai", "model": "tidak-ada"},
    )
    assert fake_ai.bodies()[-1]["model"] == "m1"


def test_ac77_log_has_no_board_content_or_answer(client, settings, caplog):
    caplog.set_level(logging.DEBUG)
    secret = "Nama siswa Budi Santoso menjawab 42"
    client.post("/ai/jalankan", headers=auth(), json={"jenis": "ringkas", "isi": secret})
    db = Database(settings.db_path)
    try:
        row = db.ai_log()[-1]
    finally:
        db.close()
    assert set(row) == {
        "waktu",
        "jenis",
        "status",
        "durasi_ms",
        "penyedia",
        "model",
        "cadangan_dari",
        "alasan_cadangan",
    }
    assert secret not in str(row)
    assert "jawaban dari" not in str(row)
    assert secret not in caplog.text and PIN not in caplog.text


@pytest.mark.parametrize(
    "body",
    [
        {"jenis": "hapus_semua", "isi": "x"},
        {"jenis": "ringkas", "isi": ""},
    ],
)
def test_invalid_ai_requests_are_rejected(client, body):
    assert client.post("/ai/jalankan", headers=auth(), json=body).status_code == 422


def test_nf01b_ai_requests_are_rate_limited(client):
    for _ in range(20):
        client.post("/ai/jalankan", headers=auth(), json={"jenis": "ringkas", "isi": "x"})
    r = client.post("/ai/jalankan", headers=auth(), json={"jenis": "ringkas", "isi": "x"})
    assert r.status_code == 429
    assert r.json()["kode"] == "terlalu_sering"


# --- Tes AI (SCR-06) ----------------------------------------------------------


def test_tes_ai_reports_provider_and_duration(client):
    r = client.post("/ai/tes", headers=auth(), json={"penyedia": "gemini", "model": "m1"})
    assert r.status_code == 200
    assert r.json()["nama"] == "Gemini" and r.json()["durasi_ms"] >= 0


def test_tes_ai_failure_is_not_hidden_by_fallback(client, fake_ai):
    fake_ai.fail["openai"] = 429
    r = client.post("/ai/tes", headers=auth(), json={"penyedia": "openai", "model": "m1"})
    assert r.status_code == 502
    assert r.json()["alasan"] == "kuota_habis"
    assert r.json()["pesan"] == "kuota habis"


def test_tes_ai_rejects_inactive_provider_and_unknown_model(client):
    r = client.post("/ai/tes", headers=auth(), json={"penyedia": "mati", "model": "m1"})
    assert r.status_code == 404
    r = client.post("/ai/tes", headers=auth(), json={"penyedia": "openai", "model": "x"})
    assert r.json()["kode"] == "model_tidak_ada"
