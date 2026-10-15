"""SQLite storage: PIN hash, lockouts, PIN changes, and AI request log.

Board content and AI answers are never stored here (NFR-21).
"""

from __future__ import annotations

import sqlite3
import threading
import time
from pathlib import Path

SCHEMA_VERSION = 1

_SCHEMA = """
CREATE TABLE IF NOT EXISTS pengaturan (
  kunci TEXT PRIMARY KEY,
  nilai TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS pin_gagal (
  alamat TEXT PRIMARY KEY,
  jumlah INTEGER NOT NULL,
  terkunci_sampai REAL NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS log_pin (
  waktu TEXT NOT NULL,
  alamat TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS log_ai (
  waktu TEXT NOT NULL,
  jenis TEXT NOT NULL,
  status TEXT NOT NULL,
  durasi_ms INTEGER NOT NULL,
  penyedia TEXT NOT NULL,
  model TEXT NOT NULL,
  cadangan_dari TEXT,
  alasan_cadangan TEXT
);
"""


def utc_now() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


class Database:
    def __init__(self, path: Path):
        path.parent.mkdir(parents=True, exist_ok=True)
        self._conn = sqlite3.connect(path, check_same_thread=False)
        self._lock = threading.Lock()
        with self._lock:
            self._conn.executescript(_SCHEMA)
            self._conn.execute(f"PRAGMA user_version = {SCHEMA_VERSION}")
            self._conn.commit()

    def close(self) -> None:
        self._conn.close()

    # --- settings -----------------------------------------------------------

    def get_setting(self, key: str) -> str | None:
        with self._lock:
            row = self._conn.execute(
                "SELECT nilai FROM pengaturan WHERE kunci = ?", (key,)
            ).fetchone()
        return row[0] if row else None

    def set_setting(self, key: str, value: str) -> None:
        with self._lock:
            self._conn.execute(
                "INSERT INTO pengaturan (kunci, nilai) VALUES (?, ?) "
                "ON CONFLICT(kunci) DO UPDATE SET nilai = excluded.nilai",
                (key, value),
            )
            self._conn.commit()

    # --- PIN lockout ----------------------------------------------------------

    def locked_until(self, address: str) -> float:
        with self._lock:
            row = self._conn.execute(
                "SELECT terkunci_sampai FROM pin_gagal WHERE alamat = ?", (address,)
            ).fetchone()
        return row[0] if row else 0.0

    def record_failure(self, address: str, limit: int, lock_seconds: int, now: float) -> int:
        """Counts a wrong PIN; locks the address when it reaches [limit].
        Returns the failure count."""
        with self._lock:
            row = self._conn.execute(
                "SELECT jumlah FROM pin_gagal WHERE alamat = ?", (address,)
            ).fetchone()
            count = (row[0] if row else 0) + 1
            locked = now + lock_seconds if count >= limit else 0.0
            if count >= limit:
                count = 0
            self._conn.execute(
                "INSERT INTO pin_gagal (alamat, jumlah, terkunci_sampai) VALUES (?, ?, ?) "
                "ON CONFLICT(alamat) DO UPDATE SET jumlah = excluded.jumlah, "
                "terkunci_sampai = excluded.terkunci_sampai",
                (address, count, locked),
            )
            self._conn.commit()
            return count

    def clear_failures(self, address: str) -> None:
        with self._lock:
            self._conn.execute("DELETE FROM pin_gagal WHERE alamat = ?", (address,))
            self._conn.commit()

    def log_pin_change(self, address: str) -> None:
        with self._lock:
            self._conn.execute(
                "INSERT INTO log_pin (waktu, alamat) VALUES (?, ?)", (utc_now(), address)
            )
            self._conn.commit()

    # --- AI log ---------------------------------------------------------------

    def log_ai(
        self,
        *,
        kind: str,
        status: str,
        duration_ms: int,
        provider: str,
        model: str,
        fallback_from: str | None = None,
        fallback_reason: str | None = None,
    ) -> None:
        with self._lock:
            self._conn.execute(
                "INSERT INTO log_ai (waktu, jenis, status, durasi_ms, penyedia, model, "
                "cadangan_dari, alasan_cadangan) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
                (
                    utc_now(),
                    kind,
                    status,
                    duration_ms,
                    provider,
                    model,
                    fallback_from,
                    fallback_reason,
                ),
            )
            self._conn.commit()

    def ai_log(self) -> list[dict]:
        with self._lock:
            cur = self._conn.execute("SELECT * FROM log_ai ORDER BY rowid")
            names = [c[0] for c in cur.description]
            return [dict(zip(names, row, strict=True)) for row in cur.fetchall()]
