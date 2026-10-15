"""Server settings and the operator's AI provider file (SPEC §4.5a)."""

from __future__ import annotations

import os
import tomllib
from dataclasses import dataclass, field
from pathlib import Path

ADAPTER_TYPES = {"ollama", "openai", "anthropic", "gemini", "openai_kompatibel"}

DEFAULT_URLS = {
    "ollama": "https://ollama.com",
    "openai": "https://api.openai.com/v1",
    "anthropic": "https://api.anthropic.com",
    "gemini": "https://generativelanguage.googleapis.com/v1beta",
}


class ConfigError(Exception):
    """The provider file is invalid; the message says what to fix."""


@dataclass(frozen=True)
class Model:
    name: str
    supports_images: bool = False


@dataclass(frozen=True)
class Provider:
    id: str
    display_name: str
    adapter: str
    base_url: str
    api_key: str | None
    models: tuple[Model, ...]
    default_model: str
    active: bool

    def has_model(self, name: str) -> bool:
        return any(m.name == name for m in self.models)


@dataclass(frozen=True)
class ProviderConfig:
    default: str
    providers: tuple[Provider, ...]

    def active(self) -> list[Provider]:
        return [p for p in self.providers if p.active]

    def get(self, provider_id: str) -> Provider | None:
        return next((p for p in self.providers if p.id == provider_id), None)

    def fallback(self) -> Provider | None:
        """Ollama cloud, the backup provider (SPEC 5.7)."""
        p = self.get(self.default)
        return p if p and p.active else None


def load_providers(path: Path, env: dict[str, str] | None = None) -> ProviderConfig:
    """Reads `penyedia.toml`. API keys come from environment variables named
    in the file, never from the file itself (REQ-16, NFR-01)."""
    env = dict(os.environ) if env is None else env
    try:
        data = tomllib.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as e:
        raise ConfigError(f"Berkas penyedia tidak ditemukan: {path}") from e
    except tomllib.TOMLDecodeError as e:
        raise ConfigError(f"Berkas penyedia tidak valid: {e}") from e

    providers: list[Provider] = []
    seen: set[str] = set()
    for raw in data.get("penyedia", []):
        pid = raw.get("id")
        if not pid or pid in seen:
            raise ConfigError(f"Penyedia tanpa id atau id ganda: {pid!r}")
        seen.add(pid)
        adapter = raw.get("jenis_adaptor")
        if adapter not in ADAPTER_TYPES:
            raise ConfigError(f"{pid}: jenis_adaptor tidak dikenal: {adapter!r}")
        base_url = raw.get("alamat_api") or DEFAULT_URLS.get(adapter)
        if not base_url:
            raise ConfigError(f"{pid}: alamat_api wajib untuk openai_kompatibel")
        models = tuple(
            Model(m["nama"], bool(m.get("dukung_gambar", False))) for m in raw.get("model", [])
        )
        if not models:
            raise ConfigError(f"{pid}: minimal satu model")
        default_model = raw.get("model_bawaan") or models[0].name
        if not any(m.name == default_model for m in models):
            raise ConfigError(f"{pid}: model_bawaan tidak ada di daftar model")
        key_env = raw.get("kunci_api_env")
        providers.append(
            Provider(
                id=pid,
                display_name=raw.get("nama_tampil", pid),
                adapter=adapter,
                base_url=base_url.rstrip("/"),
                api_key=env.get(key_env) if key_env else None,
                models=models,
                default_model=default_model,
                active=bool(raw.get("aktif", True)),
            )
        )

    default = data.get("bawaan", "ollama")
    config = ProviderConfig(default=default, providers=tuple(providers))
    if config.get(default) is None:
        raise ConfigError(f"Penyedia bawaan {default!r} tidak ada di berkas")
    return config


@dataclass
class Settings:
    data_dir: Path = field(default_factory=lambda: Path("data"))
    providers_file: Path = field(default_factory=lambda: Path("penyedia.toml"))
    trust_proxy: bool = False
    max_pin_failures: int = 5
    lock_seconds: int = 300
    ai_requests_per_minute: int = 20
    primary_timeout: float = 30.0
    total_timeout: float = 60.0
    # Pix2Text MFR model files for "Jadikan grafik" (SPEC 1.8).
    formula_model_dir: Path = field(default_factory=lambda: Path("models/pix2text-mfr-1.5"))
    # Video eksperimen and katalog.toml (REQ-24).
    video_dir: Path = field(default_factory=lambda: Path("video"))
    # PP-OCRv4 Chinese recognizer for "Pinyin & arti" (REQ-30).
    hanzi_model: Path = field(
        default_factory=lambda: Path("models/ppocr-v4-rec/ch_PP-OCRv4_rec_infer.onnx")
    )
    # CC-CEDICT (gzip or text) for Pinyin & arti (REQ-30).
    cedict_file: Path = field(default_factory=lambda: Path("kamus/cedict.txt.gz"))
    # Whisper speech-to-text for Rekam kelas (REQ-25).
    whisper_dir: Path = field(default_factory=lambda: Path("models/whisper"))
    whisper_model: str = "small"

    @classmethod
    def from_env(cls) -> Settings:
        return cls(
            data_dir=Path(os.environ.get("PAPAN_DATA", "data")),
            providers_file=Path(os.environ.get("PAPAN_PENYEDIA", "penyedia.toml")),
            trust_proxy=os.environ.get("PAPAN_PERCAYA_PROXY", "0") == "1",
            formula_model_dir=Path(os.environ.get("PAPAN_MODEL_RUMUS", "models/pix2text-mfr-1.5")),
            video_dir=Path(os.environ.get("PAPAN_VIDEO", "video")),
            hanzi_model=Path(
                os.environ.get(
                    "PAPAN_MODEL_HANZI", "models/ppocr-v4-rec/ch_PP-OCRv4_rec_infer.onnx"
                )
            ),
            cedict_file=Path(os.environ.get("PAPAN_KAMUS", "kamus/cedict.txt.gz")),
            whisper_dir=Path(os.environ.get("PAPAN_MODEL_SUARA", "models/whisper")),
            whisper_model=os.environ.get("PAPAN_WHISPER", "small"),
        )

    @property
    def db_path(self) -> Path:
        return self.data_dir / "papan.sqlite3"
