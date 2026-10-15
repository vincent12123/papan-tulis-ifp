"""Handwritten Hanzi → text for "Pinyin & arti" (SPEC 1.13, REQ-30).

The PP-OCRv4 Chinese text recognizer (PaddleOCR, Apache-2.0) runs with
onnxruntime on the server CPU, like the formula reader: no language model, no
extra packages. The circled area is cut into lines with the formula reader's
``split_lines`` and each line is read on its own (no text detector: it dropped
thin strokes such as 一 and mixed up the order of parts of a line).

A read is accepted only when it is all Han characters (Chinese punctuation
allowed) and the model is confident; otherwise it is rejected, so the panel
says "tidak dikenali" instead of showing a wrong reading (AC-195).
"""

from __future__ import annotations

import math
import threading
import unicodedata
from dataclasses import dataclass
from pathlib import Path
from typing import Protocol

import numpy as np
from PIL import Image

from .formula_reader import ReaderUnavailable, split_lines

MODEL_NAME = "ch_PP-OCRv4_rec_infer.onnx"

# Measured on 100 rendered phrases (5 handwriting-like fonts): at 0.7 every
# correct reading was kept and wrong ones dropped from 20 to 7, all cursive.
MIN_CONFIDENCE = 0.7

_HEIGHT = 48
_MIN_WIDTH = 320
_PUNCTUATION = set("，。！？、；：（）《》“”‘’…·,.!?;:")  # noqa: RUF001 (Chinese punctuation)


@dataclass(frozen=True)
class HanziReading:
    text: str
    """Recognized Hanzi (with Chinese punctuation); empty when rejected."""

    confidence: float
    """Lowest line confidence, 0 to 1."""

    raw: str
    """What the model read before the checks (for the operator test only)."""


class HanziReader(Protocol):
    def read(self, png: bytes) -> HanziReading: ...


def is_han(ch: str) -> bool:
    return unicodedata.name(ch, "").startswith("CJK UNIFIED IDEOGRAPH")


def accept(raw: str, confidence: float) -> str:
    """The reading the panel may show, or "" when it should be rejected."""
    text = "".join(raw.split())
    if confidence < MIN_CONFIDENCE or not any(is_han(c) for c in text):
        return ""
    if any(not is_han(c) and c not in _PUNCTUATION for c in text):
        return ""  # Latin letters, kana, digits mixed in: a misread
    return text


def ctc_decode(probs: np.ndarray, chars: list[str]) -> tuple[str, float]:
    """Greedy CTC: best class per step, repeats merged, blanks (0) dropped.
    Confidence is the mean probability of the kept characters."""
    best = probs.argmax(axis=1)
    score = probs.max(axis=1)
    out: list[str] = []
    kept: list[float] = []
    prev = -1
    for index, p in zip(best.tolist(), score.tolist(), strict=True):
        if index != prev and index != 0:
            out.append(chars[index])
            kept.append(p)
        prev = index
    return "".join(out), (sum(kept) / len(kept) if kept else 0.0)


class OnnxHanziReader:
    """Loads the model on first use; one image at a time (CPU bound)."""

    def __init__(self, model_file: Path):
        self.model_file = model_file
        self._lock = threading.Lock()
        self._loaded = None

    def _load(self):
        if self._loaded is None:
            try:
                import onnxruntime as ort

                opts = ort.SessionOptions()
                opts.intra_op_num_threads = 2
                session = ort.InferenceSession(
                    str(self.model_file), opts, providers=["CPUExecutionProvider"]
                )
                meta = session.get_modelmeta().custom_metadata_map
                chars = ["blank", *meta["character"].splitlines(), " "]
            except Exception as e:  # missing file, corrupt model, no dictionary
                raise ReaderUnavailable(str(e)) from e
            self._loaded = (session, session.get_inputs()[0].name, chars)
        return self._loaded

    def read(self, png: bytes) -> HanziReading:
        with self._lock:
            session, name, chars = self._load()
            parts = [self._read_line(session, name, chars, line) for line in split_lines(png)]
        raw = "".join(text for text, _ in parts)
        confidence = min((c for _, c in parts), default=0.0)
        return HanziReading(accept(raw, confidence), confidence, raw)

    @staticmethod
    def _read_line(session, name: str, chars: list[str], image: Image.Image):
        # Same preprocessing as PaddleOCR: height 48, keep the aspect ratio,
        # scale to -1..1, pad on the right to at least 320 wide.
        width = max(1, math.ceil(_HEIGHT * image.width / image.height))
        resized = image.convert("RGB").resize((width, _HEIGHT), Image.Resampling.BILINEAR)
        pixels = (np.asarray(resized, dtype=np.float32).transpose(2, 0, 1) / 255 - 0.5) / 0.5
        batch = np.zeros((1, 3, _HEIGHT, max(_MIN_WIDTH, width)), dtype=np.float32)
        batch[0, :, :, :width] = pixels
        probs = session.run(None, {name: batch})[0][0]
        return ctc_decode(probs, chars)
