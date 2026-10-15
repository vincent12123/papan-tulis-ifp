"""Operator tools on the server.

python -m app.cli atur-pin     # set or reset the admin PIN (emergency)
python -m app.cli cek-penyedia # validate penyedia.toml and show providers
"""

from __future__ import annotations

import getpass
import sys

from .config import ConfigError, Settings, load_providers
from .db import Database
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
    print(__doc__)
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
