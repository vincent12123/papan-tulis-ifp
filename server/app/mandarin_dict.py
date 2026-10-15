"""Pinyin & arti for Mandarin text (SPEC 1.13, REQ-30).

Pinyin and the word list come from libraries and a dictionary, never from a
language model: jieba splits the sentence into words, pypinyin gives tone-
marked pinyin (written with the dictionary tones, as in textbooks: nǐ hǎo;
tone changes are heard in the panel's voice), and CC-CEDICT (CC BY-SA 4.0)
gives each word's English meaning.

Indonesian meanings live in an operator-editable JSON file (word → arti).
Missing ones are asked from the AI once, together with the sentence
translation, and stored there; until then the English meaning is shown and
marked as such.
"""

from __future__ import annotations

import gzip
import json
import re
import threading
from dataclasses import dataclass, field
from pathlib import Path

from .hanzi_reader import is_han

MAX_TEXT = 60
MAX_WORDS = 24
MAX_ARTI = 80
_PUNCTUATION = re.compile(r"[，。！？、；：（）《》“”‘’…·,.!?;:()\s]+")  # noqa: RUF001
_LINE = re.compile(r"^(\S+) (\S+) \[([^\]]+)\] /(.+)/$")
_BOUND = re.compile(r"^\((bound form|literary|coll\.|dialect)\)\s*")


@dataclass
class Word:
    hanzi: str
    pinyin: str
    english: str  # from CC-CEDICT; "" when not in the dictionary
    arti: str = ""  # Indonesian
    source: str = "tidak_ada"  # kamus (Indonesian), inggris, tidak_ada


@dataclass
class Reading:
    hanzi: str
    pinyin: str
    words: list[Word] = field(default_factory=list)

    @property
    def missing(self) -> list[Word]:
        """Words still without an Indonesian meaning."""
        return [w for w in self.words if w.source != "kamus"]


class Dictionary:
    """CC-CEDICT plus the Indonesian meaning file; loaded on first use."""

    def __init__(self, cedict_file: Path, arti_file: Path):
        self.cedict_file = cedict_file
        self.arti_file = arti_file
        self._lock = threading.Lock()
        self._english: dict[str, str] | None = None
        self._arti: dict[str, str] | None = None

    # --- loading ------------------------------------------------------------

    def _load(self) -> tuple[dict[str, str], dict[str, str]]:
        if self._english is None:
            self._english = load_cedict(self.cedict_file)
        if self._arti is None:
            self._arti = load_arti(self.arti_file)
        return self._english, self._arti

    # --- lookup -------------------------------------------------------------

    def read(self, text: str) -> Reading:
        """Words, pinyin and known meanings of [text] (Hanzi only)."""
        from pypinyin import Style, pinyin

        with self._lock:
            english, arti = self._load()
            words: list[Word] = []
            for word in split_words(text, english):
                py = " ".join(s[0] for s in pinyin(word, style=Style.TONE, errors="ignore"))
                w = Word(word, py, english.get(word, ""))
                if word in arti:
                    w.arti, w.source = arti[word], "kamus"
                elif w.english:
                    w.arti, w.source = w.english, "inggris"
                words.append(w)
                if len(words) == MAX_WORDS:
                    break
        return Reading(text, " ".join(w.pinyin for w in words), words)

    def remember(self, meanings: dict[str, str]) -> None:
        """Stores Indonesian meanings (from the AI) for next time."""
        clean = {
            k: v.strip()[:MAX_ARTI]
            for k, v in meanings.items()
            if isinstance(k, str)
            and isinstance(v, str)
            and v.strip()
            and 0 < len(k) <= 8
            and all(is_han(c) for c in k)
        }
        if not clean:
            return
        with self._lock:
            _, arti = self._load()
            new = {k: v for k, v in clean.items() if k not in arti}
            if not new:
                return
            arti.update(new)
            self.arti_file.parent.mkdir(parents=True, exist_ok=True)
            tmp = self.arti_file.with_suffix(".tmp")
            tmp.write_text(
                json.dumps(dict(sorted(arti.items())), ensure_ascii=False, indent=1),
                encoding="utf-8",
            )
            tmp.replace(self.arti_file)


def clean_text(text: str) -> str:
    """Hanzi and Chinese punctuation only; anything else is dropped."""
    kept = (c for c in text if is_han(c) or (not c.isspace() and _PUNCTUATION.fullmatch(c)))
    return "".join(kept)[:MAX_TEXT]


def split_words(text: str, english: dict[str, str]) -> list[str]:
    """jieba words; a word the dictionary does not know (an idiom like
    好好学习) is split again into the longest dictionary words, so each part
    still gets a meaning."""
    import jieba

    words: list[str] = []
    for part in _PUNCTUATION.split(text):
        if not part:
            continue
        for word in jieba.lcut(part, HMM=False):
            if word in english or len(word) == 1:
                words.append(word)
            else:
                words.extend(_longest_match(word, english))
    return words


def _longest_match(word: str, english: dict[str, str]) -> list[str]:
    out, i = [], 0
    while i < len(word):
        for j in range(min(len(word), i + 6), i, -1):
            if j - i == 1 or word[i:j] in english:
                out.append(word[i:j])
                i = j
                break
    return out


def load_cedict(path: Path) -> dict[str, str]:
    """Simplified word → short English meaning (first meanings, no
    classifiers or variant notes). Surname/name entries come last."""
    opener = gzip.open if path.suffix == ".gz" else open
    entries: dict[str, tuple[int, str]] = {}
    with opener(path, "rt", encoding="utf-8") as f:
        for line in f:
            m = _LINE.match(line.strip())
            if not m:
                continue
            _, simplified, py, senses = m.groups()
            meanings = [
                _BOUND.sub("", s).strip()
                for s in senses.split("/")
                if s
                and "[" not in s  # cross-references such as 暗[an4]
                and not s.startswith(
                    ("CL:", "variant of", "old variant", "see ", "used in", "opposite:")
                )
            ]
            if not meanings:
                continue
            rank = 1 if py[:1].isupper() else 0  # proper nouns after common words
            gloss = "; ".join(meanings[:2])
            while len(gloss) > MAX_ARTI and "; " in gloss:
                gloss = gloss.rsplit("; ", 1)[0]
            gloss = gloss[:MAX_ARTI]
            if simplified not in entries or rank < entries[simplified][0]:
                entries[simplified] = (rank, gloss)
    return {k: v for k, (_, v) in entries.items()}


def load_arti(path: Path) -> dict[str, str]:
    if not path.exists():
        return {}
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        return {}
    return {k: v for k, v in data.items() if isinstance(k, str) and isinstance(v, str)}


# --- AI answer (sentence translation + missing meanings) ----------------------


def build_mandarin_prompt(reading: Reading) -> str:
    missing = {w.hanzi: w.english or "?" for w in reading.missing}
    return (
        "Terjemahkan kalimat bahasa Mandarin berikut ke Bahasa Indonesia yang wajar "
        "untuk siswa SMK, lalu beri arti singkat (1-4 kata) Bahasa Indonesia untuk "
        "setiap kata dalam daftar (arti Inggris dari kamus diberikan sebagai bantuan). "
        "Balas HANYA dengan JSON tanpa penjelasan, bentuk persis:\n"
        '{"terjemahan": "...", "arti": {"学习": "belajar"}}\n'
        f"Kalimat: {reading.hanzi}\n"
        f"Daftar kata: {json.dumps(missing, ensure_ascii=False)}"
    )


def parse_mandarin_answer(text: str, reading: Reading) -> tuple[str | None, dict[str, str]]:
    """Sentence translation (or None) and meanings for listed words only."""
    match = re.search(r"\{.*\}", text, re.DOTALL)
    if not match:
        return None, {}
    try:
        data = json.loads(match.group(0))
    except json.JSONDecodeError:
        return None, {}
    if not isinstance(data, dict):
        return None, {}
    sentence = data.get("terjemahan")
    sentence = (
        re.sub(r"[*_`$#]", "", sentence).strip()[:200]
        if isinstance(sentence, str) and sentence.strip()
        else None
    )
    wanted = {w.hanzi for w in reading.missing}
    raw = data.get("arti")
    meanings = {
        k: re.sub(r"[*_`$#]", "", v).strip()[:MAX_ARTI]
        for k, v in (raw.items() if isinstance(raw, dict) else [])
        if k in wanted and isinstance(v, str) and v.strip()
    }
    return sentence, meanings
