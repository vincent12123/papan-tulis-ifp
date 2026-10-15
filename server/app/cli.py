"""Operator tools on the server.

python -m app.cli atur-pin     # set or reset the admin PIN (emergency)
python -m app.cli cek-penyedia # validate penyedia.toml and show providers
python -m app.cli uji-hanzi FOLDER  # read Hanzi in test pictures (REQ-30)
"""

from __future__ import annotations

import getpass
import sys
from pathlib import Path

from .config import ConfigError, Settings, load_providers
from .db import Database
from .formula_reader import ReaderUnavailable
from .hanzi_reader import HanziReader, OnnxHanziReader, is_han
from .security import PIN_KEY, hash_pin, pin_problem


def set_pin(settings: Settings, pin: str) -> str | None:
    """Stores the hash of [pin]. Returns an error message or None."""
    if problem := pin_problem(pin):
        return problem
    db = Database(settings.db_path)
    try:
        db.set_setting(PIN_KEY, hash_pin(pin))
        db.log_pin_change("operator-server")
    finally:
        db.close()
    return None


def hanzi_test(reader: HanziReader, folder: Path) -> list[str]:
    """Reads every PNG/JPG in [folder] (AC-195). A file named after what is
    written (e.g. 你好.png, 你好-2.jpg) is also checked; the summary counts
    benar / ditolak / salah. Pictures stay on this machine; nothing is saved."""
    lines: list[str] = []
    right = rejected = wrong = 0
    files = sorted(f for f in folder.iterdir() if f.suffix.lower() in {".png", ".jpg", ".jpeg"})
    for f in files:
        reading = reader.read(f.read_bytes())
        expected = "".join(c for c in f.stem.split("-")[0].split("_")[0] if is_han(c))
        got = "".join(c for c in reading.text if is_han(c))
        if not reading.text:
            verdict = "DITOLAK"
            rejected += 1
        elif not expected:
            verdict = ""
        elif got == expected:
            verdict = "benar"
            right += 1
        else:
            verdict = "SALAH"
            wrong += 1
        lines.append(
            f"{f.name:28} {reading.text or '-':16} keyakinan {reading.confidence:.2f}"
            f"  (dibaca: {reading.raw or '-'})  {verdict}"
        )
    lines.append(f"{len(files)} gambar: {right} benar, {rejected} ditolak, {wrong} salah")
    return lines


def main(argv: list[str]) -> int:
    settings = Settings.from_env()
    command = argv[1] if len(argv) > 1 else ""
    if command == "atur-pin":
        pin = getpass.getpass("PIN admin baru: ")
        if pin != getpass.getpass("Ulangi PIN admin baru: "):
            print("Ulangan PIN baru tidak sama.")
            return 1
        if error := set_pin(settings, pin):
            print(error)
            return 1
        print("PIN admin sudah diatur. Masukkan PIN ini di Pengaturan tiap panel.")
        return 0
    if command == "cek-penyedia":
        try:
            config = load_providers(settings.providers_file)
        except ConfigError as e:
            print(e)
            return 1
        for p in config.providers:
            status = "aktif" if p.active else "nonaktif"
            key = "kunci ada" if p.api_key else "KUNCI KOSONG"
            print(f"{p.id:12} {status:9} {key:13} {p.default_model}")
        return 0
    if command == "uji-hanzi":
        if len(argv) < 3 or not Path(argv[2]).is_dir():
            print("Sebutkan folder berisi gambar tulisan Hanzi (PNG/JPG).")
            return 1
        sys.stdout.reconfigure(encoding="utf-8")  # Windows consoles
        try:
            for line in hanzi_test(OnnxHanziReader(settings.hanzi_model), Path(argv[2])):
                print(line)
        except ReaderUnavailable:
            print(f"Model pengenal Hanzi belum ada di {settings.hanzi_model}. Lihat README.")
            return 1
        return 0
    print(__doc__)
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
