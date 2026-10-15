"""Pengenal Hanzi (REQ-30, AC-190, AC-195)."""

import io
from pathlib import Path

import numpy as np
import pytest
from PIL import Image, ImageDraw, ImageFont

from app.cli import hanzi_test
from app.formula_reader import ReaderUnavailable
from app.hanzi_reader import (
    MIN_CONFIDENCE,
    HanziReading,
    OnnxHanziReader,
    accept,
    ctc_decode,
)


def _png(img: Image.Image) -> bytes:
    buf = io.BytesIO()
    img.save(buf, "PNG")
    return buf.getvalue()


def test_confident_hanzi_is_accepted_with_chinese_punctuation():
    phrase = "好好学习，天天向上"  # noqa: RUF001
    assert accept(phrase, 0.95) == phrase
    assert accept("你 好", 0.9) == "你好"


@pytest.mark.parametrize(
    ("raw", "confidence"),
    [
        ("你好", MIN_CONFIDENCE - 0.01),  # not sure enough
        ("一二の", 0.99),  # kana: a misread
        ("WEn", 0.99),  # no Han at all
        ("小以n4", 0.99),  # letters and digits mixed in
        ("", 1.0),
        ("，。", 1.0),  # noqa: RUF001 (punctuation only)
    ],
)
def test_unsure_or_mixed_readings_are_rejected(raw, confidence):
    assert accept(raw, confidence) == ""


def test_ctc_merges_repeats_and_drops_blanks():
    chars = ["blank", "你", "好", " "]
    steps = [1, 1, 0, 2, 2, 0, 0, 2]  # 你 你 _ 好 好 _ _ 好
    probs = np.full((len(steps), len(chars)), 0.01, dtype=np.float32)
    for i, c in enumerate(steps):
        probs[i, c] = 0.9
    text, confidence = ctc_decode(probs, chars)
    assert text == "你好好"
    assert confidence == pytest.approx(0.9)
    assert ctc_decode(np.eye(4, dtype=np.float32)[[0, 0]], chars) == ("", 0.0)


def test_missing_model_raises_unavailable(tmp_path):
    reader = OnnxHanziReader(tmp_path / "tidak-ada.onnx")
    img = Image.new("RGB", (200, 80), "white")
    ImageDraw.Draw(img).rectangle((20, 20, 150, 50), fill="black")
    with pytest.raises(ReaderUnavailable):
        reader.read(_png(img))


class _FakeReader:
    def __init__(self, answers):
        self.answers = answers

    def read(self, png: bytes) -> HanziReading:
        raw, confidence = self.answers[png]
        return HanziReading(accept(raw, confidence), confidence, raw)


def test_operator_test_counts_right_rejected_and_wrong(tmp_path):
    files = {
        "你好.png": ("你好", 0.95),
        "谢谢-2.jpg": ("谢谢", 0.9),
        "再见.png": ("每见", 0.94),  # wrong but confident
        "朋友.png": ("友", 0.5),  # rejected
        "bebas.png": ("中文", 0.9),  # no expected text: just shown
        "catatan.txt": ("", 0),
    }
    answers = {}
    for name, answer in files.items():
        data = name.encode()
        (tmp_path / name).write_bytes(data)
        answers[data] = answer
    out = hanzi_test(_FakeReader(answers), tmp_path)
    assert out[-1] == "5 gambar: 2 benar, 1 ditolak, 1 salah"
    assert any("再见.png" in line and "SALAH" in line for line in out)
    assert any("朋友.png" in line and "DITOLAK" in line for line in out)


MODEL = (
    Path(__file__).resolve().parent.parent
    / "models"
    / "ppocr-v4-rec"
    / "ch_PP-OCRv4_rec_infer.onnx"
)
CJK_FONTS = [
    Path("C:/Windows/Fonts/simsun.ttc"),
    Path("/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc"),
    Path("/usr/share/fonts/truetype/wqy/wqy-microhei.ttc"),
]
FONT = next((f for f in CJK_FONTS if f.exists()), None)


@pytest.mark.skipif(not MODEL.exists(), reason="model belum diunduh")
@pytest.mark.skipif(FONT is None, reason="tidak ada font CJK untuk menggambar")
def test_real_model_reads_two_written_lines_and_ignores_empty():
    font = ImageFont.truetype(str(FONT), 72)
    img = Image.new("RGB", (900, 320), "white")
    draw = ImageDraw.Draw(img)
    draw.text((40, 30), "我爱中国", font=font, fill="#111827")
    draw.text((40, 180), "一二三四五", font=font, fill="#111827")
    reader = OnnxHanziReader(MODEL)
    reading = reader.read(_png(img))
    assert reading.text == "我爱中国一二三四五"
    assert reading.confidence >= MIN_CONFIDENCE
    empty = reader.read(_png(Image.new("RGB", (300, 100), "white")))
    assert (empty.text, empty.raw) == ("", "")
