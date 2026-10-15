"""Handwritten formula → LaTeX with Pix2Text MFR (SPEC 1.8, REQ-20).

No language model is involved: a small image-to-LaTeX model (TrOCR
architecture, MIT license) runs with onnxruntime on the server CPU. The model
files live in a folder (``PAPAN_MODEL_RUMUS``) holding ``encoder_model.onnx``,
``decoder_model.onnx`` and ``tokenizer.json`` from
huggingface.co/breezedeus/pix2text-mfr-1.5.
"""

from __future__ import annotations

import io
import threading
from pathlib import Path
from typing import Protocol

import numpy as np
from PIL import Image

MODEL_NAME = "pix2text-mfr-1.5"
MAX_LINES = 4
MAX_TOKENS = 160
_SIZE = 384
_START, _END = 1, 2


class ReaderUnavailable(Exception):
    """The model files are missing or broken."""


class FormulaReader(Protocol):
    def read(self, png: bytes) -> list[str]:
        """LaTeX for each formula line in the image, top to bottom."""
        ...


def split_lines(png: bytes) -> list[Image.Image]:
    """Cuts the circled area into one image per written line.

    Whatever the board background, the result is dark ink on white, which is
    what the model was trained on. Tiny specks are ignored."""
    img = Image.open(io.BytesIO(png)).convert("L")
    if img.width * img.height > 16_000_000:
        raise ValueError("gambar terlalu besar")
    pixels = np.asarray(img, dtype=np.int16)
    background = int(np.median(pixels))
    ink = np.abs(pixels - background) > 60
    if ink.sum() < 30:
        return []

    rows = ink.sum(axis=1) > 0
    gap = max(8, img.height // 50)
    runs: list[tuple[int, int]] = []
    start = None
    blank = 0
    for y, has_ink in enumerate(rows):
        if has_ink:
            if start is None:
                start = y
            blank = 0
        elif start is not None:
            blank += 1
            if blank >= gap:
                runs.append((start, y - blank + 1))
                start, blank = None, 0
    if start is not None:
        runs.append((start, len(rows) - blank))

    clean = np.where(ink, 0, 255).astype(np.uint8)
    lines = []
    for top, bottom in runs:
        band = ink[top:bottom]
        if bottom - top < 10 or band.sum() < 30:
            continue
        cols = np.flatnonzero(band.sum(axis=0))
        left, right = int(cols[0]), int(cols[-1]) + 1
        pad = max(10, (bottom - top) // 4)
        crop = Image.fromarray(clean[top:bottom, left:right])
        framed = Image.new("L", (crop.width + 2 * pad, crop.height + 2 * pad), 255)
        framed.paste(crop, (pad, pad))
        lines.append(framed.convert("RGB"))
        if len(lines) == MAX_LINES:
            break
    return lines


class OnnxFormulaReader:
    """Loads the model on first use; one image at a time (CPU bound)."""

    def __init__(self, model_dir: Path):
        self.model_dir = model_dir
        self._lock = threading.Lock()
        self._loaded = None

    def _load(self):
        if self._loaded is None:
            try:
                import onnxruntime as ort
                from tokenizers import Tokenizer

                opts = ort.SessionOptions()
                opts.intra_op_num_threads = 2
                encoder = ort.InferenceSession(
                    str(self.model_dir / "encoder_model.onnx"),
                    opts,
                    providers=["CPUExecutionProvider"],
                )
                decoder = ort.InferenceSession(
                    str(self.model_dir / "decoder_model.onnx"),
                    opts,
                    providers=["CPUExecutionProvider"],
                )
                tokenizer = Tokenizer.from_file(str(self.model_dir / "tokenizer.json"))
            except Exception as e:  # missing files, corrupt model
                raise ReaderUnavailable(str(e)) from e
            self._loaded = (encoder, decoder, tokenizer)
        return self._loaded

    def read(self, png: bytes) -> list[str]:
        with self._lock:
            encoder, decoder, tokenizer = self._load()
            return [self._read_line(encoder, decoder, tokenizer, line) for line in split_lines(png)]

    @staticmethod
    def _read_line(encoder, decoder, tokenizer, image: Image.Image) -> str:
        # Same preprocessing as the model's DeiT image processor.
        resized = image.resize((_SIZE, _SIZE), Image.Resampling.BICUBIC)
        pixels = (np.asarray(resized, dtype=np.float32) / 255.0 - 0.5) / 0.5
        pixels = pixels.transpose(2, 0, 1)[None]
        hidden = encoder.run(None, {"pixel_values": pixels})[0]
        ids = [_START]
        for _ in range(MAX_TOKENS):
            logits = decoder.run(
                None,
                {"input_ids": np.array([ids], dtype=np.int64), "encoder_hidden_states": hidden},
            )[0]
            nxt = int(logits[0, -1].argmax())
            if nxt == _END:
                break
            ids.append(nxt)
        return tokenizer.decode(ids[1:], skip_special_tokens=True).strip()
