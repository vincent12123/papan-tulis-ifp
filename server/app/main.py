"""FastAPI app. Every route except /sehat needs the admin PIN in the
`X-PIN-Admin` header (SPEC §8, P-11)."""

import asyncio
import base64
import binascii
import json
import secrets
import time
from collections import defaultdict, deque
from contextlib import asynccontextmanager
from typing import Annotated, Literal

import httpx
from fastapi import Depends, FastAPI, Header, Request
from fastapi.responses import FileResponse, JSONResponse
from pydantic import BaseModel, Field
from starlette.concurrency import run_in_threadpool

from . import __version__
from .ai import (
    REASON_TEXT,
    AiUnavailable,
    ProviderError,
    build_prompt,
    call_provider,
    parse_quiz,
    run_with_fallback,
)
from .class_summary import (
    MAX_AUDIO_BYTES,
    MAX_FORMULAS,
    SummaryJobs,
    Transcriber,
    WhisperTranscriber,
    plain_text,
    run_job,
)
from .config import ProviderConfig, Settings, load_providers
from .db import Database
from .formula_chem import analyze_chem
from .formula_insight import analyze
from .formula_math import build_graph, split_rows
from .formula_reader import MODEL_NAME, FormulaReader, OnnxFormulaReader, ReaderUnavailable
from .formula_render import render
from .security import PIN_KEY, hash_pin, pin_problem, verify_pin
from .video_library import find_videos, load_catalog

READER_ID = "pengenal_rumus"
READER_NAME = "Pengenal rumus"


class ApiError(Exception):
    def __init__(self, status: int, code: str, message: str, **extra):
        self.status, self.code, self.message, self.extra = status, code, message, extra


def create_app(
    settings: Settings | None = None,
    *,
    providers: ProviderConfig | None = None,
    http_client: httpx.AsyncClient | None = None,
    formula_reader: FormulaReader | None = None,
    transcriber: Transcriber | None = None,
    clock=time.time,
) -> FastAPI:
    settings = settings or Settings.from_env()

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        app.state.db = Database(settings.db_path)
        app.state.providers = providers or load_providers(settings.providers_file)
        app.state.http = http_client or httpx.AsyncClient()
        app.state.reader = formula_reader or OnnxFormulaReader(settings.formula_model_dir)
        app.state.transcriber = transcriber or WhisperTranscriber(
            settings.whisper_dir, settings.whisper_model
        )
        app.state.summaries = SummaryJobs(clock)
        app.state.tasks = set()
        app.state.speech = asyncio.Semaphore(1)
        yield
        if http_client is None:
            await app.state.http.aclose()
        app.state.db.close()

    app = FastAPI(title="Server Papan Tulis", version=__version__, lifespan=lifespan)
    ai_calls: dict[str, deque[float]] = defaultdict(deque)

    @app.exception_handler(ApiError)
    async def _api_error(_: Request, e: ApiError):
        return JSONResponse(
            status_code=e.status,
            content={"kode": e.code, "pesan": e.message, **e.extra},
        )

    def client_address(request: Request) -> str:
        if settings.trust_proxy:
            for header in ("cf-connecting-ip", "x-real-ip"):
                if value := request.headers.get(header):
                    return value.strip()
            if fwd := request.headers.get("x-forwarded-for"):
                return fwd.split(",")[0].strip()
        return request.client.host if request.client else "tidak-diketahui"

    def check_pin(request: Request, pin: str | None) -> str:
        """Verifies [pin] with lockout per address. Returns the address."""
        db: Database = request.app.state.db
        address = client_address(request)
        now = clock()
        until = db.locked_until(address)
        if until > now:
            raise ApiError(
                429,
                "terkunci",
                "PIN salah 5 kali. Coba lagi dalam 5 menit.",
                sisa_detik=int(until - now) + 1,
            )
        stored = db.get_setting(PIN_KEY)
        if stored is None:
            raise ApiError(503, "pin_belum_diatur", "PIN admin belum diatur di server.")
        if not pin or not verify_pin(pin, stored):
            db.record_failure(address, settings.max_pin_failures, settings.lock_seconds, now)
            if db.locked_until(address) > now:
                raise ApiError(
                    429,
                    "terkunci",
                    "PIN salah 5 kali. Coba lagi dalam 5 menit.",
                    sisa_detik=settings.lock_seconds,
                )
            raise ApiError(401, "pin_salah", "PIN admin salah.")
        db.clear_failures(address)
        return address

    def require_pin(request: Request, x_pin_admin: Annotated[str | None, Header()] = None) -> str:
        return check_pin(request, x_pin_admin)

    Authed = Annotated[str, Depends(require_pin)]

    def limit_ai(address: str) -> None:
        now = clock()
        calls = ai_calls[address]
        while calls and now - calls[0] > 60:
            calls.popleft()
        if len(calls) >= settings.ai_requests_per_minute:
            raise ApiError(429, "terlalu_sering", "Permintaan AI terlalu sering. Tunggu sebentar.")
        calls.append(now)

    # --- routes ---------------------------------------------------------------

    @app.get("/sehat")
    async def health():
        return {"status": "ok"}

    @app.get("/koneksi")
    async def connection(_: Authed):
        """Tes koneksi (SCR-06): the PIN is accepted."""
        return {"status": "ok", "versi": __version__}

    @app.get("/ai/penyedia")
    async def list_providers(request: Request, _: Authed):
        cfg: ProviderConfig = request.app.state.providers
        return {
            "bawaan": cfg.default,
            "penyedia": [
                {
                    "id": p.id,
                    "nama": p.display_name,
                    "model_bawaan": p.default_model,
                    "model": [
                        {"nama": m.name, "dukung_gambar": m.supports_images} for m in p.models
                    ],
                }
                for p in cfg.active()
            ],
        }

    class TestRequest(BaseModel):
        penyedia: str
        model: str

    @app.post("/ai/tes")
    async def test_provider(body: TestRequest, request: Request, address: Authed):
        """Tes AI (SCR-06): no fallback, so the admin sees the real result."""
        limit_ai(address)
        cfg: ProviderConfig = request.app.state.providers
        provider = cfg.get(body.penyedia)
        if provider is None or not provider.active:
            raise ApiError(404, "penyedia_tidak_aktif", "Penyedia tidak aktif di server.")
        if not provider.has_model(body.model):
            raise ApiError(404, "model_tidak_ada", "Model tidak ada di daftar penyedia.")
        start = time.monotonic()
        try:
            await call_provider(
                request.app.state.http,
                provider,
                body.model,
                build_prompt("tes", ""),
                settings.primary_timeout,
            )
        except ProviderError as e:
            raise ApiError(
                502,
                "penyedia_gagal",
                REASON_TEXT.get(e.reason, e.reason),
                alasan=e.reason,
            ) from e
        return {
            "penyedia": provider.id,
            "nama": provider.display_name,
            "model": body.model,
            "durasi_ms": int((time.monotonic() - start) * 1000),
        }

    class RunRequest(BaseModel):
        jenis: Literal["pecah_soal", "soal_serupa", "ringkas", "grafik", "kuis"]
        isi: str = Field(default="", max_length=20000)
        # PNG of the selected area, base64 (P-03). ~3 MB of image at most.
        gambar: str | None = Field(default=None, max_length=4_000_000)
        penyedia: str | None = None
        model: str | None = None

    async def make_graph(reader: FormulaReader, db: Database, png: bytes) -> dict:
        """Jadikan grafik without a language model (SPEC 1.8): the formula
        recognizer reads the lines, SymPy checks them. Same answer shape as
        the AI actions so the panel needs no change."""
        start = time.monotonic()

        def log(status: str) -> int:
            ms = int((time.monotonic() - start) * 1000)
            db.log_ai(
                kind="grafik", status=status, duration_ms=ms, provider=READER_ID, model=MODEL_NAME
            )
            return ms

        try:
            graph = await asyncio.wait_for(
                run_in_threadpool(lambda: build_graph(reader.read(png))),
                settings.total_timeout,
            )
        except ReaderUnavailable as e:
            log("gagal")
            raise ApiError(
                503, "ai_tidak_tersedia", "Pengenal rumus sedang tidak tersedia.", alasan="gagal"
            ) from e
        except TimeoutError as e:
            log("batas_waktu")
            raise ApiError(
                503, "ai_tidak_tersedia", "Pengenal rumus terlalu lama.", alasan="batas_waktu"
            ) from e
        except (OSError, ValueError) as e:  # PIL cannot decode, absurd size
            log("gagal")
            raise ApiError(422, "gambar_rusak", "Gambar area tidak bisa dibaca.") from e
        if not graph["fungsi"]:
            log("gagal")
            raise ApiError(
                422, "tanpa_rumus", "Tidak ditemukan rumus fungsi yang bisa digambar di area ini."
            )
        return {
            "hasil": None,
            "grafik": graph,
            "penyedia": READER_ID,
            "nama": READER_NAME,
            "model": MODEL_NAME,
            "durasi_ms": log("berhasil"),
            "cadangan_dari": None,
            "cadangan_dari_nama": None,
            "alasan_cadangan": None,
        }

    class InsightRequest(BaseModel):
        # PNG of the circled area, base64. ~3 MB of image at most.
        gambar: str = Field(max_length=4_000_000)
        # Ink color of the handwriting, for the typeset formula.
        warna: str = Field(default="#1E293B", max_length=7)

    @app.post("/rumus/kenali")
    async def recognize(body: InsightRequest, request: Request, address: Authed):
        """Menu pintar (REQ-22): recognize the circled area once and prepare
        every action it offers (graph data, typeset formula, solution), so
        the panel's buttons work instantly. No language model; nothing of the
        board is stored or logged (NFR-21)."""
        png = decode_png(body.gambar)
        limit_ai(address)
        db: Database = request.app.state.db
        reader: FormulaReader = request.app.state.reader
        start = time.monotonic()

        def log(status: str) -> int:
            ms = int((time.monotonic() - start) * 1000)
            db.log_ai(
                kind="kenali", status=status, duration_ms=ms, provider=READER_ID, model=MODEL_NAME
            )
            return ms

        def picture(lines: list, empty: str | None = None) -> dict:
            image, w, h = render(lines or [empty], body.warna)
            return {"gambar": base64.b64encode(image).decode(), "lebar": w, "tinggi": h}

        def work() -> dict | None:
            lines = reader.read(png)
            rows = [part for line in lines for part in split_rows(line)]
            chem = analyze_chem(rows)
            if chem is not None:
                # Kimia (REQ-24): "penyelesaian" carries the balanced equation
                # so the panel's Selesaikan slot becomes Setarakan.
                videos = find_videos(load_catalog(settings.video_dir), chem.species)
                return {
                    "jenis": "kimia",
                    "rumus": chem.latex,
                    "zat": chem.species,
                    "setara": chem.balanced,
                    "grafik": None,
                    "rapi": picture(chem.latex),
                    "penyelesaian": None
                    if not chem.balanced_latex
                    else {"baris": chem.balanced_latex, **picture(chem.balanced_latex)},
                    "video": [{"id": v.id, "judul": v.title} for v in videos],
                }
            insight = analyze(lines)
            if insight is None:
                return None
            tidy, w, h = render([(r.latex, r.tidy) for r in insight.rows], body.warna)
            solution = None
            if insight.solution is not None:
                lines = insight.solution or [r"\mathrm{tidak\ ada\ penyelesaian\ real}"]
                image, sw, sh = render(lines, body.warna)
                solution = {
                    "baris": insight.solution,
                    "gambar": base64.b64encode(image).decode(),
                    "lebar": sw,
                    "tinggi": sh,
                }
            return {
                "jenis": insight.kind,
                "rumus": [r.tidy for r in insight.rows],
                "grafik": insight.graph,
                "rapi": {"gambar": base64.b64encode(tidy).decode(), "lebar": w, "tinggi": h},
                "penyelesaian": solution,
                "zat": [],
                "video": [],
            }

        try:
            result = await asyncio.wait_for(run_in_threadpool(work), settings.total_timeout)
        except ReaderUnavailable as e:
            log("gagal")
            raise ApiError(
                503, "ai_tidak_tersedia", "Pengenal rumus sedang tidak tersedia.", alasan="gagal"
            ) from e
        except TimeoutError as e:
            log("batas_waktu")
            raise ApiError(
                503, "ai_tidak_tersedia", "Pengenal rumus terlalu lama.", alasan="batas_waktu"
            ) from e
        except (OSError, ValueError) as e:
            log("gagal")
            raise ApiError(422, "gambar_rusak", "Gambar area tidak bisa dibaca.") from e
        if result is None:
            log("gagal")
            raise ApiError(422, "tanpa_rumus", "Tidak ada rumus yang dikenali di area ini.")
        result["durasi_ms"] = log("berhasil")
        return result

    def decode_png(data: str) -> bytes:
        try:
            raw = base64.b64decode(data, validate=True)
        except binascii.Error as e:
            raise ApiError(422, "gambar_rusak", "Gambar area tidak bisa dibaca.") from e
        if not raw.startswith(b"\x89PNG\r\n\x1a\n"):
            raise ApiError(422, "gambar_rusak", "Gambar area harus PNG.")
        return raw

    @app.post("/kelas/ringkas")
    async def summarize_lesson(
        request: Request,
        address: Authed,
        x_rumus: Annotated[str | None, Header()] = None,
    ):
        """Rekam kelas (REQ-25): the body is the recording (AAC/M4A); the
        optional X-Rumus header holds base64 JSON of the formulas recognized
        on the board. Answers at once with a job id to poll."""
        formulas: list[str] = []
        if x_rumus:
            try:
                parsed = json.loads(base64.b64decode(x_rumus, validate=True))
            except (binascii.Error, ValueError) as e:
                raise ApiError(422, "rumus_rusak", "Daftar rumus tidak bisa dibaca.") from e
            if not isinstance(parsed, list) or not all(isinstance(f, str) for f in parsed):
                raise ApiError(422, "rumus_rusak", "Daftar rumus tidak bisa dibaca.")
            formulas = [f[:200] for f in parsed[:MAX_FORMULAS]]
        limit_ai(address)
        folder = settings.data_dir / "rekaman"
        folder.mkdir(parents=True, exist_ok=True)
        audio = folder / f"{secrets.token_hex(8)}.m4a"
        size = 0
        try:
            with audio.open("wb") as out:
                async for chunk in request.stream():
                    size += len(chunk)
                    if size > MAX_AUDIO_BYTES:
                        raise ApiError(413, "rekaman_terlalu_besar", "Rekaman terlalu panjang.")
                    out.write(chunk)
        except ApiError:
            audio.unlink(missing_ok=True)
            raise
        if size == 0:
            audio.unlink(missing_ok=True)
            raise ApiError(422, "rekaman_kosong", "Rekaman kosong.")

        state = request.app.state
        job = state.summaries.new()
        db: Database = state.db

        async def transcribe(path):
            async with state.speech:
                return await run_in_threadpool(state.transcriber.transcribe, path)

        async def summarize(prompt: str) -> str:
            result = await run_with_fallback(
                state.http,
                state.providers,
                provider_id=None,
                model=None,
                prompt=prompt[:60000],
                primary_timeout=60,
                total_timeout=120,
            )
            return result.text

        async def work():
            await run_job(job, audio, formulas, transcribe=transcribe, summarize=summarize)
            db.log_ai(
                kind="ringkas_kelas",
                status="berhasil" if job.status == "selesai" else "gagal",
                duration_ms=int((job.seconds or 0) * 1000),
                provider="whisper",
                model=settings.whisper_model,
            )

        task = asyncio.create_task(work())
        state.tasks.add(task)
        task.add_done_callback(state.tasks.discard)
        return {"id": job.id, "status": job.status}

    @app.get("/kelas/ringkas/{job_id}")
    async def lesson_summary(job_id: str, request: Request, address: Authed):
        job = request.app.state.summaries.get(job_id)
        if job is None:
            raise ApiError(404, "ringkasan_tidak_ada", "Ringkasan tidak ditemukan.")
        return {"id": job.id, "status": job.status, "ringkasan": job.summary, "kode": job.error}

    @app.get("/video/{video_id}")
    async def video_file(video_id: str, address: Authed):
        """Plays a catalog video (REQ-24); the panel streams it with Range
        requests, which FileResponse answers."""
        for v in load_catalog(settings.video_dir):
            if v.id == video_id:
                return FileResponse(v.path, media_type=v.media_type)
        raise ApiError(404, "video_tidak_ada", "Video tidak ada di katalog sekolah.")

    @app.post("/ai/jalankan")
    async def run_ai(body: RunRequest, request: Request, address: Authed):
        """One AI action (SPEC 5.7). Board content is used for the call only
        and never stored or logged (NFR-21)."""
        if body.gambar is not None:
            try:
                raw = base64.b64decode(body.gambar, validate=True)
            except binascii.Error as e:
                raise ApiError(422, "gambar_rusak", "Gambar area tidak bisa dibaca.") from e
            if not raw.startswith(b"\x89PNG\r\n\x1a\n"):
                raise ApiError(422, "gambar_rusak", "Gambar area harus PNG.")
        if not body.isi.strip() and body.gambar is None:
            raise ApiError(422, "isi_kosong", "Tidak ada isi papan yang dikirim.")
        if body.jenis == "grafik" and body.gambar is None:
            raise ApiError(422, "isi_kosong", "Jadikan grafik butuh gambar area.")
        limit_ai(address)
        db: Database = request.app.state.db
        cfg: ProviderConfig = request.app.state.providers
        if body.jenis == "grafik":
            return await make_graph(request.app.state.reader, db, raw)
        start = time.monotonic()
        try:
            result = await run_with_fallback(
                request.app.state.http,
                cfg,
                provider_id=body.penyedia,
                model=body.model,
                prompt=build_prompt(body.jenis, body.isi, has_image=body.gambar is not None),
                primary_timeout=settings.primary_timeout,
                total_timeout=settings.total_timeout,
                image_b64=body.gambar,
            )
        except AiUnavailable as e:
            status = "batas_waktu" if e.reason == "batas_waktu" else "gagal"
            db.log_ai(
                kind=body.jenis,
                status=status,
                duration_ms=int((time.monotonic() - start) * 1000),
                provider=e.provider,
                model=e.model,
            )
            raise ApiError(
                503,
                "ai_tidak_tersedia",
                "AI sedang tidak tersedia.",
                alasan=e.reason,
            ) from e
        quiz = None
        if body.jenis == "kuis":
            quiz = parse_quiz(result.text)
            if len(quiz) < 2:
                db.log_ai(
                    kind=body.jenis,
                    status="gagal",
                    duration_ms=result.duration_ms,
                    provider=result.provider.id,
                    model=result.model,
                )
                raise ApiError(422, "tanpa_kuis", "AI tidak bisa menyusun kuis dari papan ini.")
        db.log_ai(
            kind=body.jenis,
            status="berhasil",
            duration_ms=result.duration_ms,
            provider=result.provider.id,
            model=result.model,
            fallback_from=result.fallback_from,
            fallback_reason=result.fallback_reason,
        )
        fallback_name = None
        if result.fallback_from:
            original = cfg.get(result.fallback_from)
            fallback_name = original.display_name if original else result.fallback_from
        return {
            "hasil": None if quiz is not None else plain_text(result.text),
            "grafik": None,
            "kuis": quiz,
            "penyedia": result.provider.id,
            "nama": result.provider.display_name,
            "model": result.model,
            "durasi_ms": result.duration_ms,
            "cadangan_dari": result.fallback_from,
            "cadangan_dari_nama": fallback_name,
            "alasan_cadangan": result.fallback_reason,
        }

    class PinChange(BaseModel):
        pin_lama: str
        pin_baru: str

    @app.post("/admin/pin")
    async def change_pin(body: PinChange, request: Request):
        """Ganti PIN admin (TSK-10). The old PIN counts toward the lockout."""
        try:
            address = check_pin(request, body.pin_lama)
        except ApiError as e:
            if e.code == "pin_salah":
                raise ApiError(
                    401, "pin_lama_salah", "PIN lama salah. PIN admin tidak berubah."
                ) from e
            raise
        if problem := pin_problem(body.pin_baru):
            raise ApiError(422, "pin_baru_tidak_valid", problem)
        if body.pin_baru == body.pin_lama:
            raise ApiError(422, "pin_baru_sama", "PIN baru tidak boleh sama dengan PIN lama.")
        db: Database = request.app.state.db
        db.set_setting(PIN_KEY, hash_pin(body.pin_baru))
        db.log_pin_change(address)
        return {"status": "ok"}

    return app


app = create_app()
