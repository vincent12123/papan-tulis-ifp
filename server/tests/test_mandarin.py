"""Pinyin & arti (REQ-30, AC-190 to AC-193)."""

from __future__ import annotations

import json

import pytest

from app.mandarin_dict import Reading, Word, clean_text, parse_mandarin_answer

from .conftest import auth
from .test_insight import kenali


def arti(client, teks="好好学习，天天向上", **extra):  # noqa: RUF001
    return client.post("/mandarin/arti", headers=auth(), json={"teks": teks, **extra})


def test_ac190_chinese_area_offers_mandarin_instead_of_formulas(client, fake_hanzi, fake_reader):
    fake_hanzi.raw = "你好"
    r = kenali(client)
    assert r.status_code == 200
    body = r.json()
    assert (body["jenis"], body["hanzi"], body["rapi"]) == ("mandarin", "你好", None)
    assert fake_reader.images == [], "formula reader not needed"


@pytest.mark.parametrize(("raw", "confidence"), [("", 0.9), ("你好", 0.4), ("y二x", 0.99)])
def test_ac190_no_or_unsure_chinese_keeps_the_formula_menu(client, fake_hanzi, raw, confidence):
    fake_hanzi.raw, fake_hanzi.confidence = raw, confidence
    body = kenali(client).json()
    assert body["jenis"] == "fungsi"
    assert "hanzi" not in body


def test_ac191_pinyin_and_words_come_from_the_dictionary(client, fake_ai):
    fake_ai.answer = json.dumps(
        {
            "terjemahan": "Belajarlah dengan giat, maju setiap hari.",
            "arti": {"好好": "dengan baik", "学习": "belajar", "天天": "setiap hari"},
        }
    )
    r = arti(client)
    assert r.status_code == 200
    body = r.json()
    assert body["pinyin"] == "hǎo hǎo xué xí tiān tiān xiàng shàng"
    assert [k["hanzi"] for k in body["kata"]] == ["好好", "学习", "天天", "向上"]
    assert [k["pinyin"] for k in body["kata"]] == ["hǎo hǎo", "xué xí", "tiān tiān", "xiàng shàng"]
    assert body["kata"][1] == {
        "hanzi": "学习",
        "pinyin": "xué xí",
        "arti": "belajar",
        "sumber": "kamus",
    }
    # Not answered by the AI: the English meaning, marked as such.
    assert body["kata"][3]["arti"] == "upward; up"
    assert body["kata"][3]["sumber"] == "inggris"
    assert body["terjemahan"] == "Belajarlah dengan giat, maju setiap hari."
    # The AI was asked only for words it did not know yet.
    prompt = json.dumps(fake_ai.bodies()[0], ensure_ascii=False)
    assert "学习" in prompt


def test_meanings_are_remembered_and_not_asked_again(client, fake_ai, dictionary):
    fake_ai.answer = json.dumps({"terjemahan": "Halo", "arti": {"你好": "halo"}})
    assert arti(client, teks="你好").json()["kata"][0]["arti"] == "halo"
    assert json.loads(dictionary.arti_file.read_text(encoding="utf-8")) == {"你好": "halo"}
    fake_ai.answer = json.dumps({"terjemahan": "Halo", "arti": {"你好": "SALAH"}})
    word = arti(client, teks="你好").json()["kata"][0]
    assert (word["arti"], word["sumber"]) == ("halo", "kamus")


def test_ac192_without_ai_the_card_still_comes_without_made_up_text(client, fake_ai):
    for host in ("ollama", "openai", "claude", "gemini", "lainnya"):
        fake_ai.fail[host] = 503
    r = arti(client, teks="我是学生")
    assert r.status_code == 200
    body = r.json()
    assert body["terjemahan"] is None
    assert body["pinyin"] == "wǒ shì xué shēng"
    assert [(k["hanzi"], k["sumber"]) for k in body["kata"]] == [
        ("我", "inggris"),
        ("是", "inggris"),
        ("学生", "inggris"),
    ]


def test_unknown_characters_get_pinyin_but_no_meaning(client, fake_ai):
    fake_ai.fail["ollama"] = 503
    body = arti(client, teks="喝").json()
    assert body["kata"] == [{"hanzi": "喝", "pinyin": "hē", "arti": "", "sumber": "tidak_ada"}]


def test_common_meaning_before_names_and_no_cross_references(dictionary):
    reading = dictionary.read("明")
    assert reading.words[0].english == "bright"


@pytest.mark.parametrize("teks", ["hello", "123", "x = 2"])
def test_text_without_hanzi_is_refused(client, teks):
    r = arti(client, teks=teks)
    assert (r.status_code, r.json()["kode"]) == (422, "tanpa_hanzi")


def test_needs_the_pin(client):
    r = client.post("/mandarin/arti", json={"teks": "你好"})
    assert r.status_code == 401


def test_text_is_not_logged(client, fake_ai, settings):
    fake_ai.answer = "{}"
    arti(client, teks="你好")
    log = settings.db_path.read_bytes()
    assert "你好".encode() not in log
    assert "你好".encode("utf-16-le") not in log


def test_clean_text_keeps_only_hanzi_and_chinese_punctuation():
    assert clean_text("你好! abc 123，再见") == "你好!，再见"  # noqa: RUF001


def test_ai_answer_is_checked():
    reading = Reading("你好", "nǐ hǎo", [Word("你好", "nǐ hǎo", "hello", "hello", "inggris")])
    assert parse_mandarin_answer("bukan json", reading) == (None, {})
    sentence, meanings = parse_mandarin_answer(
        'x {"terjemahan": "**Halo**", "arti": {"你好": "halo", "别的": "lain", "1": 2}} y',
        reading,
    )
    assert (sentence, meanings) == ("Halo", {"你好": "halo"})
