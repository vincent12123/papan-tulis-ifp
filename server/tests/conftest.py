from __future__ import annotations

import json
from pathlib import Path

import httpx
import pytest
from fastapi.testclient import TestClient

from app.config import Model, Provider, ProviderConfig, Settings
from app.db import Database
from app.main import create_app
from app.security import PIN_KEY, hash_pin

PIN = "482915"


def provider(pid: str, adapter: str, *, active: bool = True, key: str = "rahasia-") -> Provider:
    return Provider(
        id=pid,
        display_name=pid.capitalize(),
        adapter=adapter,
        base_url=f"https://{pid}.contoh",
        api_key=key + pid,
        models=(Model("m1"), Model("m2", supports_images=True)),
        default_model="m1",
        active=active,
    )


def default_providers() -> ProviderConfig:
    return ProviderConfig(
        default="ollama",
        providers=(
            provider("ollama", "ollama"),
            provider("openai", "openai"),
            provider("claude", "anthropic"),
            provider("gemini", "gemini"),
            provider("lainnya", "openai_kompatibel"),
            provider("mati", "openai", active=False),
        ),
    )


class FakeAi:
    """Answers provider calls; per host it can fail with a status code or a
    transport error. Records every request."""

    def __init__(self):
        self.fail: dict[str, int | str] = {}
        self.requests: list[httpx.Request] = []
        # When set, every provider answers with this text.
        self.answer: str | None = None

    def handler(self, request: httpx.Request) -> httpx.Response:
        self.requests.append(request)
        host = request.url.host.split(".")[0]
        failure = self.fail.get(host)
        if failure == "timeout":
            raise httpx.ReadTimeout("lambat", request=request)
        if failure == "down":
            raise httpx.ConnectError("mati", request=request)
        if isinstance(failure, int):
            return httpx.Response(failure, json={"error": "x"})
        text = self.answer if self.answer is not None else f"jawaban dari {host}"
        path = request.url.path
        if path.endswith("/api/chat"):
            return httpx.Response(200, json={"message": {"content": text}})
        if path.endswith("/chat/completions"):
            return httpx.Response(200, json={"choices": [{"message": {"content": text}}]})
        if path.endswith("/v1/messages"):
            return httpx.Response(200, json={"content": [{"type": "text", "text": text}]})
        if ":generateContent" in path:
            return httpx.Response(
                200, json={"candidates": [{"content": {"parts": [{"text": text}]}}]}
            )
        return httpx.Response(404)

    def bodies(self) -> list[dict]:
        return [json.loads(r.content) for r in self.requests]


class FakeReader:
    """Stands in for the Pix2Text model: returns fixed LaTeX lines."""

    def __init__(self):
        self.lines: list[str] = [r"y = x ^ { 2 } - 3", r"y = A \sin x + B"]
        self.error: Exception | None = None
        self.images: list[bytes] = []

    def read(self, png: bytes) -> list[str]:
        self.images.append(png)
        if self.error:
            raise self.error
        return self.lines


class FakeTranscriber:
    """Stands in for Whisper: returns fixed text, records the files."""

    def __init__(self):
        self.text = "Hari ini kita belajar fungsi kuadrat y sama dengan x kuadrat dikurangi tiga."
        self.error: Exception | None = None
        self.files: list[tuple[str, bytes]] = []

    def transcribe(self, audio):
        self.files.append((str(audio), audio.read_bytes()))
        if self.error:
            raise self.error
        return self.text


class Clock:
    def __init__(self):
        self.now = 1_000_000.0

    def __call__(self) -> float:
        return self.now


@pytest.fixture
def fake_ai() -> FakeAi:
    return FakeAi()


@pytest.fixture
def fake_reader() -> FakeReader:
    return FakeReader()


@pytest.fixture
def fake_transcriber() -> FakeTranscriber:
    return FakeTranscriber()


@pytest.fixture
def clock() -> Clock:
    return Clock()


@pytest.fixture
def settings(tmp_path: Path) -> Settings:
    s = Settings(data_dir=tmp_path / "data", providers_file=tmp_path / "penyedia.toml")
    db = Database(s.db_path)
    db.set_setting(PIN_KEY, hash_pin(PIN))
    db.close()
    return s


@pytest.fixture
def client(settings, fake_ai, fake_reader, fake_transcriber, clock):
    http = httpx.AsyncClient(transport=httpx.MockTransport(fake_ai.handler))
    app = create_app(
        settings,
        providers=default_providers(),
        http_client=http,
        formula_reader=fake_reader,
        transcriber=fake_transcriber,
        clock=clock,
    )
    with TestClient(app) as c:
        yield c


def auth(pin: str = PIN) -> dict[str, str]:
    return {"X-PIN-Admin": pin}
