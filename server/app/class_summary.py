"""Rekam kelas + ringkasan (SPEC 1.9, REQ-25).

The panel uploads the lesson recording; the server turns speech into text
with Whisper running on the school's own server (faster-whisper, CPU), then
asks the configured AI (with the usual fallback to Ollama cloud) for a
summary in plain Indonesian. Long lessons take a while, so this is a job the
panel polls.

Privacy (NFR-21): the audio is written to a temporary file only while it is
transcribed and deleted right after; the transcript lives only in memory
inside the job and is dropped once the summary is made; nothing of it is
logged. Finished jobs are forgotten after a day.
"""

from __future__ import annotations

import re
import secrets
import time
from collections.abc import Awaitable, Callable
from dataclasses import dataclass, field
from pathlib import Path
from typing import Protocol

MAX_AUDIO_BYTES = 120 * 1024 * 1024  # ~4 h of AAC at 64 kbit/s
MAX_FORMULAS = 20
KEEP_SECONDS = 24 * 3600
MIN_WORDS = 5


class Transcriber(Protocol):
    def transcribe(self, audio: Path) -> str: ...


class WhisperTranscriber:
    """faster-whisper on CPU; the model downloads into [model_dir] on first
    use (``small`` ≈ 480 MB; ``base`` is faster, less accurate)."""

    def __init__(self, model_dir: Path, model: str = "small"):
        self.model_dir = model_dir
        self.model_name = model
        self._model = None

    def transcribe(self, audio: Path) -> str:
        if self._model is None:
            from faster_whisper import WhisperModel

            self._model = WhisperModel(
                self.model_name,
                device="cpu",
                compute_type="int8",
                cpu_threads=2,  # leave the other cores to the school's apps
                download_root=str(self.model_dir),
            )
        segments, _ = self._model.transcribe(
            str(audio), language="id", beam_size=1, vad_filter=True
        )
        return " ".join(s.text.strip() for s in segments).strip()


def summary_prompt(transcript: str, formulas: list[str]) -> str:
    board = "\n".join(f"- {f}" for f in formulas) or "- (tidak ada)"
    return (
        "Anda membantu guru di Indonesia. Berikut transkrip suara pelajaran di kelas "
        "dan rumus yang dikenali di papan. Buat ringkasan materi untuk siswa dalam "
        "Bahasa Indonesia, berupa TEKS BIASA (tanpa Markdown, tanpa tanda bintang, "
        "tanpa tanda $, tanpa LaTeX). Susunan:\n"
        "Judul: (satu baris)\n"
        "Poin penting: (paling banyak 8 butir, diawali tanda -)\n"
        "Rumus penting: (tulis sederhana, misalnya y = x^2 - 3)\n"
        "Tugas atau latihan: (bila disebut guru; bila tidak, tulis satu soal latihan "
        "singkat)\n"
        "Jangan menyebut nama siswa.\n\n"
        f"Rumus di papan:\n{board}\n\nTranskrip:\n{transcript}"
    )


def plain_text(text: str) -> str:
    """AI answers sometimes keep Markdown/LaTeX; the board shows plain text."""
    s = re.sub(r"\*\*|__|`", "", text)
    s = re.sub(r"(?m)^\s*#{1,6}\s*", "", s)
    s = re.sub(r"\$([^$]*)\$", r"\1", s)
    s = s.replace("\\(", "").replace("\\)", "")
    return s.strip()


@dataclass
class Job:
    id: str
    status: str = "antri"  # antri → mentranskrip → meringkas → selesai | gagal
    summary: str | None = None
    error: str | None = None  # code: tanpa_suara | ai_tidak_tersedia | gagal
    created: float = field(default_factory=time.time)
    seconds: float | None = None


class SummaryJobs:
    """Jobs in memory; one transcription at a time (CPU bound)."""

    def __init__(self, clock: Callable[[], float] = time.time):
        self.jobs: dict[str, Job] = {}
        self.clock = clock

    def new(self) -> Job:
        self._forget_old()
        job = Job(secrets.token_urlsafe(12), created=self.clock())
        self.jobs[job.id] = job
        return job

    def get(self, job_id: str) -> Job | None:
        self._forget_old()
        return self.jobs.get(job_id)

    def _forget_old(self) -> None:
        now = self.clock()
        for k in [k for k, j in self.jobs.items() if now - j.created > KEEP_SECONDS]:
            del self.jobs[k]


async def run_job(
    job: Job,
    audio: Path,
    formulas: list[str],
    *,
    transcribe: Callable[[Path], Awaitable[str]],
    summarize: Callable[[str], Awaitable[str]],
    clock: Callable[[], float] = time.monotonic,
) -> None:
    """Fills [job]; never raises (the panel reads the outcome by polling)."""
    start = clock()
    try:
        job.status = "mentranskrip"
        try:
            transcript = await transcribe(audio)
        finally:
            audio.unlink(missing_ok=True)
        if len(transcript.split()) < MIN_WORDS:
            job.status, job.error = "gagal", "tanpa_suara"
            return
        job.status = "meringkas"
        text = await summarize(summary_prompt(transcript, formulas[:MAX_FORMULAS]))
        del transcript
        job.summary = plain_text(text)
        job.status = "selesai"
    except Exception as e:
        job.status = "gagal"
        job.error = "ai_tidak_tersedia" if type(e).__name__ == "AiUnavailable" else "gagal"
    finally:
        job.seconds = clock() - start
