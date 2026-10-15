"""Perpustakaan video eksperimen sekolah (SPEC 1.9, REQ-24).

The operator puts video files (MP4/WebM) in the video folder and lists them
in ``katalog.toml`` next to them:

    [[video]]
    id = "natrium-klorin"
    judul = "Reaksi natrium dengan gas klorin"
    berkas = "natrium-klorin.mp4"
    kata_kunci = ["Na", "Cl2", "NaCl"]

A video matches a circled reaction when one of its keywords is one of the
formulas found there. The catalog is read on each request, so a new video
shows up without restarting the server. Broken entries are skipped.
"""

from __future__ import annotations

import re
import tomllib
from dataclasses import dataclass
from pathlib import Path

_ID = re.compile(r"^[a-z0-9][a-z0-9-]{0,63}$")
MEDIA_TYPES = {".mp4": "video/mp4", ".webm": "video/webm", ".m4v": "video/mp4"}
MAX_RESULTS = 6


@dataclass(frozen=True)
class Video:
    id: str
    title: str
    path: Path
    keywords: tuple[str, ...]

    @property
    def media_type(self) -> str:
        return MEDIA_TYPES[self.path.suffix.lower()]


def load_catalog(folder: Path) -> list[Video]:
    try:
        data = tomllib.loads((folder / "katalog.toml").read_text(encoding="utf-8"))
    except (OSError, tomllib.TOMLDecodeError, UnicodeDecodeError):
        return []
    root = folder.resolve()
    videos, seen = [], set()
    for entry in data.get("video", []):
        if not isinstance(entry, dict):
            continue
        vid, title, name = entry.get("id"), entry.get("judul"), entry.get("berkas")
        keywords = entry.get("kata_kunci")
        if not (
            isinstance(vid, str)
            and _ID.match(vid)
            and vid not in seen
            and isinstance(title, str)
            and title.strip()
            and isinstance(name, str)
            and isinstance(keywords, list)
            and all(isinstance(k, str) for k in keywords)
        ):
            continue
        path = (folder / name).resolve()
        # Only files inside the video folder, of a playable type, that exist.
        if root not in path.parents or path.suffix.lower() not in MEDIA_TYPES:
            continue
        if not path.is_file():
            continue
        seen.add(vid)
        videos.append(Video(vid, title.strip(), path, tuple(k.strip() for k in keywords)))
    return videos


def find_videos(videos: list[Video], formulas: list[str]) -> list[Video]:
    wanted = {f.replace(" ", "") for f in formulas}
    lowered = {f.lower() for f in wanted}
    hits = [
        v
        for v in videos
        if any(k.replace(" ", "") in wanted or k.lower() in lowered for k in v.keywords)
    ]
    return hits[:MAX_RESULTS]
