"""AI adapters per provider type and the automatic Ollama cloud fallback
(SPEC 5.7, REQ-19, REQ-20)."""

from __future__ import annotations

import json
import math
import re
import time
from dataclasses import dataclass

import httpx

from .config import Provider, ProviderConfig

KINDS = ("pecah_soal", "soal_serupa", "ringkas", "grafik", "kuis", "tes")

_SYSTEM = (
    "Kamu membantu guru di kelas di Indonesia. Jawab dalam Bahasa Indonesia yang "
    "jelas dan ringkas, cocok ditulis di papan tulis. Jangan menambahkan salam."
)

_INSTRUCTIONS = {
    "pecah_soal": "Pecah soal berikut menjadi langkah penyelesaian bernomor. "
    "Tulis satu langkah per baris, lalu jawaban akhir.",
    "soal_serupa": "Buat 3 soal latihan serupa (tingkat kesulitan sama, angka/konteks "
    "berbeda) dari soal berikut. Beri nomor, tanpa kunci jawaban.",
    "ringkas": "Ringkas isi papan berikut menjadi catatan pendek berpoin untuk siswa.",
    "grafik": (
        "Baca rumus fungsi y = f(x) yang ditulis tangan. Balas HANYA dengan JSON "
        "tanpa penjelasan, dengan bentuk persis:\n"
        '{"fungsi": ["y = x^2 - 3", "y = A*sin(x) + B"], '
        '"parameter": [{"nama": "A", "min": -5, "maks": 5, "nilai": 1}], '
        '"sumbu": {"x_min": -6.28, "x_maks": 6.28, "y_min": -5, "y_maks": 5}}\n'
        "Aturan: tulis rumus persis seperti di papan; pakai ^ untuk pangkat, * untuk kali, "
        "dan fungsi sin cos tan sqrt abs log ln exp. Setiap huruf selain x dan e adalah "
        "parameter: beri rentang min..maks yang wajar dan nilai awal (1 bila tidak tertulis). "
        "Pilih sumbu agar bentuk penting kurva terlihat. Bila tidak ada rumus fungsi, "
        'balas {"fungsi": []}.'
    ),
    "kuis": (
        "Buat kuis mencocokkan untuk siswa dari materi di papan ini: 4 sampai 6 "
        "pasangan konsep (kiri) dan arti/hasilnya (kanan). Balas HANYA dengan JSON "
        "tanpa penjelasan, dengan bentuk persis:\n"
        '{"kuis": [{"kiri": "y = x^2 - 3", "kanan": "Parabola terbuka ke atas"}]}\n'
        "Aturan: setiap teks paling banyak 50 karakter, teks biasa tanpa Markdown "
        "atau LaTeX, setiap jawaban hanya cocok dengan satu soal. Bila papan tidak "
        'berisi materi pelajaran, balas {"kuis": []}.'
    ),
    "tes": "Balas hanya dengan kata: siap",
}

_ON_IMAGE = "Soal/isi papan ada pada gambar tulisan tangan yang dilampirkan."


def build_prompt(kind: str, content: str = "", *, has_image: bool = False) -> str:
    """Same prompt for every provider so answers are comparable."""
    if kind == "tes":
        return _INSTRUCTIONS["tes"]
    parts = [_INSTRUCTIONS[kind]]
    if has_image:
        parts.append(_ON_IMAGE)
    if content.strip():
        parts.append(f"---\n{content.strip()}\n---")
    return "\n\n".join(parts)


class ProviderError(Exception):
    """A provider call failed. [reason] matches SPEC §4.5 alasan_cadangan."""

    def __init__(self, reason: str):
        super().__init__(reason)
        self.reason = reason


REASON_TEXT = {
    "tidak_terjangkau": "server penyedia tidak terjangkau",
    "kuota_habis": "kuota habis",
    "kunci_ditolak": "kunci API di server ditolak",
    "model_tidak_ada": "model tidak ditemukan",
    "batas_waktu": "tidak menjawab tepat waktu",
    "tidak_aktif": "penyedia tidak aktif",
    "tanpa_model_gambar": "tidak ada model yang bisa membaca gambar",
    "gagal": "jawaban tidak bisa dibaca",
}


def _classify(response: httpx.Response) -> str:
    code = response.status_code
    if code in (401, 403):
        return "kunci_ditolak"
    if code in (402, 429):
        return "kuota_habis"
    if code == 404:
        return "model_tidak_ada"
    return "gagal"


async def call_provider(
    client: httpx.AsyncClient,
    provider: Provider,
    model: str,
    prompt: str,
    timeout: float,
    image_b64: str | None = None,
) -> str:
    """Sends one prompt (and optionally one PNG) in the provider's own API
    format; returns plain text."""
    a = provider.adapter
    key = provider.api_key or ""
    if a == "ollama":
        url = f"{provider.base_url}/api/chat"
        headers = {"Authorization": f"Bearer {key}"} if key else {}
        user: dict = {"role": "user", "content": prompt}
        if image_b64:
            user["images"] = [image_b64]
        body = {
            "model": model,
            "stream": False,
            "messages": [{"role": "system", "content": _SYSTEM}, user],
        }
    elif a in ("openai", "openai_kompatibel"):
        url = f"{provider.base_url}/chat/completions"
        headers = {"Authorization": f"Bearer {key}"} if key else {}
        content: str | list = prompt
        if image_b64:
            content = [
                {"type": "text", "text": prompt},
                {
                    "type": "image_url",
                    "image_url": {"url": f"data:image/png;base64,{image_b64}"},
                },
            ]
        body = {
            "model": model,
            "messages": [
                {"role": "system", "content": _SYSTEM},
                {"role": "user", "content": content},
            ],
        }
    elif a == "anthropic":
        url = f"{provider.base_url}/v1/messages"
        headers = {"x-api-key": key, "anthropic-version": "2023-06-01"}
        content = [{"type": "text", "text": prompt}]
        if image_b64:
            content.insert(
                0,
                {
                    "type": "image",
                    "source": {"type": "base64", "media_type": "image/png", "data": image_b64},
                },
            )
        body = {
            "model": model,
            "max_tokens": 1500,
            "system": _SYSTEM,
            "messages": [{"role": "user", "content": content}],
        }
    elif a == "gemini":
        # Key in a header, not the URL, so it never lands in access logs.
        url = f"{provider.base_url}/models/{model}:generateContent"
        headers = {"x-goog-api-key": key}
        parts: list = [{"text": prompt}]
        if image_b64:
            parts.insert(0, {"inline_data": {"mime_type": "image/png", "data": image_b64}})
        body = {
            "systemInstruction": {"parts": [{"text": _SYSTEM}]},
            "contents": [{"role": "user", "parts": parts}],
        }
    else:  # pragma: no cover - rejected when the config is loaded
        raise ProviderError("gagal")

    try:
        response = await client.post(url, json=body, headers=headers, timeout=timeout)
    except httpx.TimeoutException as e:
        raise ProviderError("batas_waktu") from e
    except httpx.TransportError as e:
        raise ProviderError("tidak_terjangkau") from e
    if response.status_code >= 400:
        raise ProviderError(_classify(response))
    try:
        data = response.json()
        if a == "ollama":
            text = data["message"]["content"]
        elif a in ("openai", "openai_kompatibel"):
            text = data["choices"][0]["message"]["content"]
        elif a == "anthropic":
            text = "".join(p.get("text", "") for p in data["content"] if p.get("type") == "text")
        else:
            text = "".join(p.get("text", "") for p in data["candidates"][0]["content"]["parts"])
    except (ValueError, KeyError, IndexError, TypeError) as e:
        raise ProviderError("gagal") from e
    if not isinstance(text, str) or not text.strip():
        raise ProviderError("gagal")
    return text.strip()


@dataclass
class AiResult:
    text: str
    provider: Provider
    model: str
    duration_ms: int
    fallback_from: str | None = None
    fallback_reason: str | None = None


class AiUnavailable(Exception):
    """Neither the chosen provider nor Ollama cloud answered."""

    def __init__(self, reason: str, provider: str, model: str):
        super().__init__(reason)
        self.reason = reason
        self.provider = provider
        self.model = model


def _image_model(provider: Provider, preferred: str | None) -> str | None:
    """[preferred] if it reads images, else the provider's first image model."""
    for m in provider.models:
        if m.name == preferred and m.supports_images:
            return m.name
    default = next((m for m in provider.models if m.name == provider.default_model), None)
    if default and default.supports_images:
        return default.name
    return next((m.name for m in provider.models if m.supports_images), None)


def resolve(
    config: ProviderConfig,
    provider_id: str | None,
    model: str | None,
    *,
    needs_image: bool = False,
) -> tuple[Provider, str | None, bool]:
    """The provider/model to try first. Falls back to the default provider
    when the panel's choice is empty or no longer active. The bool says
    whether the panel's choice was replaced. With [needs_image] the model is
    one that reads images (None if the provider has none)."""
    fallback = config.fallback()
    chosen = config.get(provider_id) if provider_id else None
    replaced = False
    if chosen is None or not chosen.active:
        if fallback is None:
            raise AiUnavailable("tidak_aktif", provider_id or "", model or "")
        chosen, model, replaced = fallback, None, provider_id is not None
    if needs_image:
        return chosen, _image_model(chosen, model), replaced
    use_model = model if model and chosen.has_model(model) else chosen.default_model
    return chosen, use_model, replaced


async def run_with_fallback(
    client: httpx.AsyncClient,
    config: ProviderConfig,
    *,
    provider_id: str | None,
    model: str | None,
    prompt: str,
    primary_timeout: float,
    total_timeout: float,
    image_b64: str | None = None,
) -> AiResult:
    """Tries the chosen provider (≤ primary_timeout); on any failure retries
    the same prompt on Ollama cloud with the remaining time. Requests with an
    image always go to a model that reads images (P-03)."""
    start = time.monotonic()
    needs_image = image_b64 is not None
    provider, use_model, replaced = resolve(config, provider_id, model, needs_image=needs_image)
    fallback = config.fallback()
    first_timeout = total_timeout if fallback is None or provider is fallback else primary_timeout
    try:
        if use_model is None:
            raise ProviderError("tanpa_model_gambar")
        text = await call_provider(client, provider, use_model, prompt, first_timeout, image_b64)
        result = AiResult(text, provider, use_model, _ms(start))
        if replaced:
            result.fallback_from = provider_id
            result.fallback_reason = "tidak_aktif"
        return result
    except ProviderError as first:
        if fallback is None or provider is fallback:
            raise AiUnavailable(first.reason, provider.id, use_model or "") from first
        backup_model = _image_model(fallback, None) if needs_image else fallback.default_model
        if backup_model is None:
            raise AiUnavailable("tanpa_model_gambar", provider.id, use_model or "") from first
        remaining = max(1.0, total_timeout - (time.monotonic() - start))
        try:
            text = await call_provider(client, fallback, backup_model, prompt, remaining, image_b64)
        except ProviderError as second:
            raise AiUnavailable(second.reason, provider.id, use_model or "") from second
        return AiResult(
            text,
            fallback,
            backup_model,
            _ms(start),
            fallback_from=provider.id,
            fallback_reason=first.reason,
        )


def _ms(start: float) -> int:
    return int((time.monotonic() - start) * 1000)


# --- graph answers (REQ-20) ---------------------------------------------------

MAX_FUNCTIONS = 4
MAX_PARAMS = 6
MAX_FORMULA = 200
# Math characters only; the escapes are superscript 2/3, root, pi, times,
# divide, middle dot, and the Unicode minus sign.
_ALLOWED_FORMULA = re.compile(
    r"^[0-9A-Za-z\s+\-*/^().,=|\u00b2\u00b3\u221a\u03c0\u00d7\u00f7\u00b7\u2212]+$"
)
_PARAM_NAME = re.compile(r"^[A-Za-z]$")


class GraphUnreadable(Exception):
    """The AI answer is not a usable graph description."""


def _finite(value: object, name: str) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise GraphUnreadable(f"{name} bukan angka")
    v = float(value)
    if not math.isfinite(v) or abs(v) > 1e6:
        raise GraphUnreadable(f"{name} di luar batas")
    return v


def parse_graph(text: str) -> dict:
    """Extracts and checks the JSON graph description from an AI answer.

    Only plain data comes back: formula strings limited to math characters,
    parameter ranges, and axis ranges. The panel parses the formulas with its
    own math parser; nothing from the AI is ever executed (AC-85)."""
    match = re.search(r"\{.*\}", text, re.DOTALL)
    if not match:
        raise GraphUnreadable("tidak ada JSON")
    try:
        data = json.loads(match.group(0))
    except json.JSONDecodeError as e:
        raise GraphUnreadable("JSON rusak") from e
    if not isinstance(data, dict) or not isinstance(data.get("fungsi"), list):
        raise GraphUnreadable("tidak ada daftar fungsi")

    functions = []
    for f in data["fungsi"][:MAX_FUNCTIONS]:
        if (
            isinstance(f, str)
            and 0 < len(f.strip()) <= MAX_FORMULA
            and _ALLOWED_FORMULA.match(f.strip())
        ):
            functions.append(f.strip())

    params = []
    seen: set[str] = set()
    for p in data.get("parameter") or []:
        if len(params) >= MAX_PARAMS or not isinstance(p, dict):
            continue
        name = p.get("nama")
        if not isinstance(name, str) or not _PARAM_NAME.match(name) or name in "xXe":
            continue
        if name in seen:
            continue
        try:
            lo = _finite(p.get("min", -5), "min")
            hi = _finite(p.get("maks", 5), "maks")
            value = _finite(p.get("nilai", 1), "nilai")
        except GraphUnreadable:
            continue
        if lo >= hi:
            lo, hi = -5.0, 5.0
        seen.add(name)
        params.append({"nama": name, "min": lo, "maks": hi, "nilai": min(max(value, lo), hi)})

    axes = data.get("sumbu") if isinstance(data.get("sumbu"), dict) else {}
    try:
        x_min = _finite(axes.get("x_min", -10), "x_min")
        x_max = _finite(axes.get("x_maks", 10), "x_maks")
        y_min = _finite(axes.get("y_min", -10), "y_min")
        y_max = _finite(axes.get("y_maks", 10), "y_maks")
    except GraphUnreadable:
        x_min, x_max, y_min, y_max = -10.0, 10.0, -10.0, 10.0
    if x_min >= x_max:
        x_min, x_max = -10.0, 10.0
    if y_min >= y_max:
        y_min, y_max = -10.0, 10.0

    return {
        "fungsi": functions,
        "parameter": params,
        "sumbu": {"x_min": x_min, "x_maks": x_max, "y_min": y_min, "y_maks": y_max},
    }


MAX_QUIZ = 6
MAX_QUIZ_TEXT = 60


def parse_quiz(text: str) -> list[dict[str, str]]:
    """Matching pairs from an AI answer; junk and duplicates dropped."""
    match = re.search(r"\{.*\}", text, re.DOTALL)
    if not match:
        return []
    try:
        data = json.loads(match.group(0))
    except json.JSONDecodeError:
        return []
    items = data.get("kuis") if isinstance(data, dict) else None
    if not isinstance(items, list):
        return []
    pairs, seen = [], set()
    for p in items:
        if not isinstance(p, dict):
            continue
        left, right = p.get("kiri"), p.get("kanan")
        if not isinstance(left, str) or not isinstance(right, str):
            continue
        left = re.sub(r"[*_`$#]", "", left).strip()[:MAX_QUIZ_TEXT]
        right = re.sub(r"[*_`$#]", "", right).strip()[:MAX_QUIZ_TEXT]
        if not left or not right or left in seen or right in seen:
            continue
        seen.update((left, right))
        pairs.append({"kiri": left, "kanan": right})
        if len(pairs) == MAX_QUIZ:
            break
    return pairs
