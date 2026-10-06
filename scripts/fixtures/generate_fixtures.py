#!/usr/bin/env python3
"""Generate Anki package fixtures + expected rendering using the official Anki library.

Usage:
    python -m venv venv && . venv/bin/activate && pip install anki genanki
    python scripts/fixtures/generate_fixtures.py NegotoCore/Tests/NegotoCoreTests/Fixtures

The expected output (expected.json) is produced by Anki's own Rust renderer and
scheduler, so the Swift test-suite verifies that Negoto renders/schedules every
card the same way Anki does, for every package format Anki can produce.
"""
import json
import os
import shutil
import struct
import sys
import tempfile
import zlib

from anki.collection import Collection, ExportAnkiPackageOptions



def png_bytes(w=4, h=3, rgb=(200, 50, 50)):
    raw = b"".join(b"\x00" + bytes(rgb) * w for _ in range(h))

    def chunk(t, d):
        c = struct.pack(">I", len(d)) + t + d
        return c + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)

    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))


CUSTOM_FRONT = """{{=<% %>=}}
<div class=expr><%Expression%></div>
<%#Reading%><div class=reading><%furigana:Reading%></div><%/Reading%>
<%^Notes%><div class=nonotes>no notes</div><%/Notes%>
<%tts ja_JP voices=Apple_Otoya speed=1.1:Expression%>
<div class=meta><%Deck%>|<%Subdeck%>|<%Card%>|<%Type%>|<%Tags%></div>
"""
CUSTOM_BACK = """{{FrontSide}}<hr id=answer>
<div class=meaning>{{Meaning}}</div>
<div class=kana>{{kana:Reading}}</div><div class=kanji>{{kanji:Reading}}</div>
<div class=text>{{text:Meaning}}</div>
{{#Notes}}{{hint:Notes}}{{/Notes}}
{{Audio}}
"""
CUSTOM_CSS = """@font-face { font-family: myfont; src: url("_myfont.ttf"); }
.card { font-family: myfont; background-image: url('_bg image.png'); }
"""


def build_collection(path, media_dir_files):
    col = Collection(path)
    mm = col.models

    # custom note type
    m = mm.new("Japanese Custom")
    for f in ["Expression", "Reading", "Meaning", "Audio", "Notes"]:
        mm.add_field(m, mm.new_field(f))
    t = mm.new_template("Recognition")
    t["qfmt"] = CUSTOM_FRONT
    t["afmt"] = CUSTOM_BACK
    mm.add_template(m, t)
    t2 = mm.new_template("Production")
    t2["qfmt"] = "{{#Meaning}}{{Meaning}}{{/Meaning}}"
    t2["afmt"] = "{{FrontSide}}<hr id=answer>{{Expression}} {{type:Expression}}"
    mm.add_template(m, t2)
    m["css"] = CUSTOM_CSS
    mm.add(m)
    custom = mm.by_name("Japanese Custom")

    for name, data in media_dir_files.items():
        col.media.write_data(name, data)

    d_vocab = col.decks.id("日本語::語彙")
    d_math = col.decks.id("Math & Science")
    d_io = col.decks.id("Occlusion")

    def add(model_name, fields, deck, tags=()):
        model = mm.by_name(model_name)
        n = col.new_note(model)
        for k, v in fields.items():
            n[k] = v
        n.tags = list(tags)
        col.add_note(n, deck)
        return n

    add("Basic", {"Front": 'Cat <img src="猫 picture.png">', "Back": "ねこ [sound:hello world.mp3]"}, d_vocab, ["animal", "jp::n5"])
    add("Basic", {"Front": "Empty back", "Back": ""}, d_vocab)
    add("Basic (and reversed card)", {"Front": "Hund<br>", "Back": "<b>dog</b> &amp; &nbsp;friend"}, d_vocab)
    add("Basic (optional reversed card)", {"Front": "only front", "Back": "b", "Add Reverse": ""}, d_vocab)
    add("Basic (optional reversed card)", {"Front": "both", "Back": "b2", "Add Reverse": "y"}, d_vocab)
    add("Basic (type in the answer)", {"Front": "Capital of France?", "Back": "Paris"}, d_vocab)
    add("Cloze", {"Text": "{{c1::Canberra::city}} is the capital of {{c2::Australia}}. {{c1::Nested {{c3::inner}} outer}}",
                  "Back Extra": "extra"}, d_math)
    add("Cloze", {"Text": r"Math: {{c1::\(x^2 + y^2 = z^2\)}} and \[\int_0^1 f(x)\,dx\] [$]a^b[/$] [latex]E=mc^2[/latex]",
                  "Back Extra": ""}, d_math)
    add("Basic (type in the answer)", {"Front": "{{c1::not a cloze}} type", "Back": "Ünïcödé <i>text</i>"}, d_math)
    add("Image Occlusion", {
        "Occlusion": "{{c1::image-occlusion:rect:left=.1:top=.2:width=.3:height=.4:oi=1}}"
                     "{{c2::image-occlusion:ellipse:left=.5:top=.5:rx=.1:ry=.2}}"
                     "{{c3::image-occlusion:polygon:points=.1,.1 .2,.3 .3,.1}}"
                     "{{c3::image-occlusion:text:left=.6:top=.1:text=Hi there:scale=1}}",
        "Image": '<img src="io-image.png">', "Header": "head", "Back Extra": "", "Comments": ""}, d_io)
    n = col.new_note(custom)
    n["Expression"] = "日本語"
    n["Reading"] = "日本語[にほんご] 漢字[かんじ]を 勉強[べんきょう]"
    n["Meaning"] = "<span style='color:red'>Japanese</span> language"
    n["Audio"] = "[sound:日本語.mp3][sound:clip.mp4]"
    n["Notes"] = "a hint"
    n.tags = ["tag1", "Tag2"]
    col.add_note(n, d_vocab)
    n = col.new_note(custom)
    n["Expression"] = "空"
    n["Reading"] = ""
    n["Meaning"] = ""
    col.add_note(n, d_vocab)

    # Answer a few cards so that the package contains every scheduling state.
    col.set_config("rollover", 4)
    cards = [col.get_card(cid) for cid in col.find_cards("")]
    sched = col.sched
    for i, card in enumerate(cards[:8]):
        for ease in [[3], [1], [3, 3], [4], [3, 3, 3], [2], [4, 4], [1, 3]][i]:
            c = col.get_card(card.id)
            c.start_timer()
            sched.answerCard(c, ease)

    return col


def expected_for(col):
    out = {}
    for cid in col.find_cards(""):
        card = col.get_card(cid)
        r = card.render_output(reload=True)
        states = col._backend.get_scheduling_states(cid)
        labels = col.sched.describe_next_states(states)
        out[str(cid)] = {
            "nid": card.nid,
            "ord": card.ord,
            "did": card.did,
            "question": r.question_text,
            "answer": r.answer_text,
            "question_av": [repr_av(t) for t in r.question_av_tags],
            "answer_av": [repr_av(t) for t in r.answer_av_tags],
            "css": r.css,
            "type": card.type, "queue": card.queue, "due": card.due, "ivl": card.ivl,
            "factor": card.factor, "left": card.left,
            "next_labels": list(labels),
        }
    return out


def repr_av(tag):
    from anki.sound import SoundOrVideoTag, TTSTag
    if isinstance(tag, SoundOrVideoTag):
        return {"sound": tag.filename}
    return {"tts": tag.field_text, "lang": tag.lang, "voices": list(tag.voices), "speed": tag.speed}


FSRS_PARAMS = [0.212, 1.2931, 2.3065, 8.2956, 6.4133, 0.8334, 3.0194, 0.001, 1.8722, 0.1666, 0.796, 1.4835,
               0.0614, 0.2629, 1.6483, 0.6014, 1.8729, 0.5425, 0.0912, 0.0658, 0.1542]


def build_fsrs(outdir, tmp):
    """A collection with FSRS enabled, cards in every state, and Anki's answer-button labels."""
    import time
    col = Collection(os.path.join(tmp, "fsrs.anki2"))
    col.set_config("fsrs", True)
    conf = col.decks.config_dict_for_deck_id(1)
    conf["fsrsParams6"] = FSRS_PARAMS
    conf["desiredRetention"] = 0.9
    col.decks.update_config(conf)
    model = col.models.by_name("Basic")
    ids = []
    for i in range(10):
        n = col.new_note(model)
        n["Front"] = f"q{i}"
        n["Back"] = f"a{i}"
        col.add_note(n, 1)
        ids.append(n.cards()[0].id)
    # learning cards with memory states from today's answers
    for cid, eases in zip(ids[:4], [[1], [2], [3], [4]]):
        for e in eases:
            c = col.get_card(cid)
            c.start_timer()
            col.sched.answerCard(c, e)
    # review cards with explicit memory states, due at different offsets
    today = col.sched.today
    for cid, (ivl, off, s, d) in zip(ids[4:9], [(10, 0, 10.0, 5.0), (3, -2, 3.5, 7.5), (30, 5, 40.0, 3.0),
                                               (100, -20, 90.0, 6.0), (5, 0, 4.0, 9.5)]):
        col.db.execute("update cards set type=2, queue=2, ivl=?, due=?, factor=2500, data=? where id=?",
                       ivl, today + off, json.dumps({"s": s, "d": d}), cid)
    out = {"now": int(time.time()), "learn_ahead_secs": col.get_config("collapseTime", 1200), "cards": {}}
    for cid in ids:
        card = col.get_card(cid)
        states = col._backend.get_scheduling_states(cid)
        ms = card.memory_state
        out["cards"][str(cid)] = {
            "type": card.type, "queue": card.queue, "due": card.due, "ivl": card.ivl,
            "next_labels": list(col.sched.describe_next_states(states)),
            "stability": ms.stability if ms else None, "difficulty": ms.difficulty if ms else None,
        }
    with open(os.path.join(outdir, "expected_fsrs.json"), "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, indent=1, sort_keys=True)
    col.export_anki_package(
        out_path=os.path.join(outdir, "fsrs.apkg"),
        options=ExportAnkiPackageOptions(with_scheduling=True, with_deck_configs=True, with_media=False, legacy=False),
        limit=None)
    col.close()


def main(outdir):
    os.makedirs(outdir, exist_ok=True)
    tmp = tempfile.mkdtemp()
    media = {
        "猫 picture.png": png_bytes(),
        "io-image.png": png_bytes(20, 10, (10, 200, 10)),
        "hello world.mp3": b"ID3fake-mp3",
        "日本語.mp3": b"ID3fake-mp3-2",
        "clip.mp4": b"fake-mp4",
        "_myfont.ttf": b"fake-font",
        "_bg image.png": png_bytes(2, 2, (240, 240, 240)),
    }
    col = build_collection(os.path.join(tmp, "src.anki2"), media)
    import time
    expected = {
        "now": int(time.time()),
        "today": col.sched.today,
        "learn_ahead_secs": col.get_config("collapseTime", 1200),
        "cards": expected_for(col),
        "decks": sorted(d.name for d in col.decks.all_names_and_ids()),
        "note_count": col.note_count(),
        "card_count": col.card_count(),
        "media": sorted(media.keys()),
    }
    with open(os.path.join(outdir, "expected.json"), "w", encoding="utf-8") as f:
        json.dump(expected, f, ensure_ascii=False, indent=1, sort_keys=True)

    for name, legacy in [("modern.apkg", False), ("legacy.apkg", True)]:
        col.export_anki_package(
            out_path=os.path.join(outdir, name),
            options=ExportAnkiPackageOptions(with_scheduling=True, with_deck_configs=True,
                                             with_media=True, legacy=legacy),
            limit=None,
        )
    col.close()
    # colpkg exports close the collection, so reopen for each.
    for name, legacy in [("modern.colpkg", False), ("legacy.colpkg", True)]:
        c = Collection(os.path.join(tmp, "src.anki2"))
        c.export_collection_package(os.path.join(outdir, name), include_media=True, legacy=legacy)

    # Anki 2.0-era package (collection.anki2 only, schema 11, v1 scheduler) via genanki.
    import genanki
    model = genanki.Model(
        1607392319, "Simple Model",
        fields=[{"name": "Question"}, {"name": "Answer"}],
        templates=[{"name": "Card 1", "qfmt": "{{Question}}", "afmt": "{{FrontSide}}<hr id=answer>{{Answer}}"}])
    cmodel = genanki.Model(
        998877661, "Old Cloze", model_type=genanki.Model.CLOZE,
        fields=[{"name": "Text"}, {"name": "Extra"}],
        templates=[{"name": "Cloze", "qfmt": "{{cloze:Text}}", "afmt": "{{cloze:Text}}<br>{{Extra}}"}])
    deck = genanki.Deck(2059400110, "Genanki::Old Deck")
    deck.add_note(genanki.Note(model=model, fields=["Capital of Japan", 'Tokyo <img src="tokyo.png">']))
    deck.add_note(genanki.Note(model=cmodel, fields=["{{c1::A}} and {{c2::B}}", "x"]))
    pkg = genanki.Package(deck)
    tokyo = os.path.join(tmp, "tokyo.png")
    with open(tokyo, "wb") as f:
        f.write(png_bytes())
    pkg.media_files = [tokyo]
    pkg.write_to_file(os.path.join(outdir, "genanki.apkg"))
    build_fsrs(outdir, tmp)
    shutil.rmtree(tmp)
    # A short Ogg Vorbis clip for the audio decoder test.
    if shutil.which("ffmpeg"):
        import subprocess
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-f", "lavfi", "-i", "sine=frequency=440:duration=0.3",
                        "-ac", "1", "-ar", "22050", "-c:a", "libvorbis", "-q:a", "0", os.path.join(outdir, "tone.ogg")],
                       check=True)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "NegotoCore/Tests/NegotoCoreTests/Fixtures")
