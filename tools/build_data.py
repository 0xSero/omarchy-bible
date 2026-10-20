#!/usr/bin/env python3
"""Convert bible-rs .bbl files into the compact JSON the panel reads.

The .bbl layout is documented in bible-rs/crates/core/src/format.rs. We keep
verse text, structural marks (paragraphs, poetry, headings) and character
styles (words of Christ, translator additions, italics) so the panel can
typeset the same text the native app does.

Usage:
    python3 tools/build_data.py .sources data

The .bbl files are downloaded by tools/fetch_sources.sh. Generated JSON is
committed, so a plugin install needs no build step.
"""
from __future__ import annotations

import json
import struct
import sys
from pathlib import Path

import zstandard

BOOKS = [
    ("Genesis", "Gen", 50), ("Exodus", "Exod", 40), ("Leviticus", "Lev", 27),
    ("Numbers", "Num", 36), ("Deuteronomy", "Deut", 34), ("Joshua", "Josh", 24),
    ("Judges", "Judg", 21), ("Ruth", "Ruth", 4), ("1 Samuel", "1 Sam", 31),
    ("2 Samuel", "2 Sam", 24), ("1 Kings", "1 Kgs", 22), ("2 Kings", "2 Kgs", 25),
    ("1 Chronicles", "1 Chr", 29), ("2 Chronicles", "2 Chr", 36), ("Ezra", "Ezra", 10),
    ("Nehemiah", "Neh", 13), ("Esther", "Esth", 10), ("Job", "Job", 42),
    ("Psalms", "Ps", 150), ("Proverbs", "Prov", 31), ("Ecclesiastes", "Eccl", 12),
    ("Song of Solomon", "Song", 8), ("Isaiah", "Isa", 66), ("Jeremiah", "Jer", 52),
    ("Lamentations", "Lam", 5), ("Ezekiel", "Ezek", 48), ("Daniel", "Dan", 12),
    ("Hosea", "Hos", 14), ("Joel", "Joel", 3), ("Amos", "Amos", 9),
    ("Obadiah", "Obad", 1), ("Jonah", "Jonah", 4), ("Micah", "Mic", 7),
    ("Nahum", "Nah", 3), ("Habakkuk", "Hab", 3), ("Zephaniah", "Zeph", 3),
    ("Haggai", "Hag", 2), ("Zechariah", "Zech", 14), ("Malachi", "Mal", 4),
    ("Matthew", "Matt", 28), ("Mark", "Mark", 16), ("Luke", "Luke", 24),
    ("John", "John", 21), ("Acts", "Acts", 28), ("Romans", "Rom", 16),
    ("1 Corinthians", "1 Cor", 16), ("2 Corinthians", "2 Cor", 13),
    ("Galatians", "Gal", 6), ("Ephesians", "Eph", 6), ("Philippians", "Phil", 4),
    ("Colossians", "Col", 4), ("1 Thessalonians", "1 Thess", 5),
    ("2 Thessalonians", "2 Thess", 3), ("1 Timothy", "1 Tim", 6),
    ("2 Timothy", "2 Tim", 4), ("Titus", "Titus", 3), ("Philemon", "Phlm", 1),
    ("Hebrews", "Heb", 13), ("James", "Jas", 5), ("1 Peter", "1 Pet", 5),
    ("2 Peter", "2 Pet", 3), ("1 John", "1 John", 5), ("2 John", "2 John", 1),
    ("3 John", "3 John", 1), ("Jude", "Jude", 1), ("Revelation", "Rev", 22),
]
CHAPTER_OFFSETS = []
_acc = 0
for _name, _short, _chapters in BOOKS:
    CHAPTER_OFFSETS.append(_acc)
    _acc += _chapters
CHAPTER_COUNT = _acc  # 1189


class Reader:
    def __init__(self, data: bytes):
        self.data = data
        self.pos = 0

    def take(self, n: int) -> bytes:
        end = self.pos + n
        if end > len(self.data):
            raise ValueError("truncated .bbl")
        out = self.data[self.pos:end]
        self.pos = end
        return out

    def u16(self) -> int:
        return struct.unpack("<H", self.take(2))[0]

    def u32(self) -> int:
        return struct.unpack("<I", self.take(4))[0]

    def blob(self) -> bytes:
        return self.take(self.u32())


def byte_to_char(text: str) -> list[int]:
    """Map UTF-8 byte offsets to JS/QML string indices.

    The .bbl offsets are byte offsets, but QML slices UTF-16 code units. Most
    English text is ASCII, where the two agree; curly quotes and dashes are not.
    """
    raw = text.encode("utf-8")
    if len(raw) == len(text):
        return list(range(len(text) + 1))
    out = [0] * (len(raw) + 1)
    at = 0
    for index, char in enumerate(text):
        width = len(char.encode("utf-8"))
        for _ in range(width):
            out[at] = index
            at += 1
    out[at] = len(text)
    return out


def le16(buf: bytes, i: int) -> int:
    return struct.unpack_from("<H", buf, i * 2)[0]


def le32(buf: bytes, i: int) -> int:
    return struct.unpack_from("<I", buf, i * 4)[0]


def decode(path: Path) -> dict:
    raw = path.read_bytes()
    r = Reader(raw)
    if r.take(4) != b"BIBL":
        raise ValueError(f"{path}: not a .bbl file")
    version = r.u16()
    if version != 1:
        raise ValueError(f"{path}: unsupported version {version}")
    meta = json.loads(r.blob())
    body_len = r.u32()
    body = zstandard.ZstdDecompressor().decompress(r.data[r.pos:], max_output_size=body_len)
    if len(body) != body_len:
        raise ValueError(f"{path}: body length mismatch")

    b = Reader(body)
    text = b.blob().decode("utf-8")
    extra = b.blob().decode("utf-8")
    chapter_verses = [b.u16() for _ in range(CHAPTER_COUNT)]
    n = b.u32()
    numbers = b.take(n)
    ends = b.take(n)
    text_lens = b.take(n * 2)
    mark_lens = b.take(n * 2)
    span_lens = b.take(n * 2)

    verses = []
    ts = ms = ss = 0
    for i in range(n):
        tl = le16(text_lens, i)
        ml = le16(mark_lens, i)
        sl = le16(span_lens, i)
        verses.append((numbers[i], ends[i], ts, tl, ms, ml, ss, sl))
        ts += tl
        ms += ml
        ss += sl
    text_bytes = text.encode("utf-8")
    if ts != len(text_bytes):
        raise ValueError(f"{path}: text length mismatch {ts} != {len(text_bytes)}")

    m = b.u32()
    offs = b.take(m * 2)
    kinds = b.take(m)
    levels = b.take(m)
    pstarts = b.take(m * 4)
    plens = b.take(m * 4)
    marks = []
    for i in range(m):
        payload = ""
        if pstarts[i] or plens[i]:
            payload = extra.encode("utf-8")[le32(pstarts, i):le32(pstarts, i) + le32(plens, i)].decode("utf-8")
        marks.append((le16(offs, i), kinds[i], levels[i], payload))

    k = b.u32()
    starts = b.take(k * 2)
    ends_b = b.take(k * 2)
    styles = b.take(k)
    spans = [(le16(starts, i), le16(ends_b, i), styles[i]) for i in range(k)]

    def cut(blob: bytes, start: int, length: int) -> str:
        return blob[start:start + length].decode("utf-8")

    chapters = []
    vi = 0
    for count in chapter_verses:
        chapter = []
        for _ in range(count):
            num, num_end, tstart, tlen, mstart, mlen, sstart, slen = verses[vi]
            vi += 1
            verse_text = cut(text_bytes, tstart, tlen)
            cmap = byte_to_char(verse_text)

            def at(offset: int) -> int:
                return cmap[offset] if offset < len(cmap) else len(verse_text)

            chapter.append([
                num,
                num_end,
                verse_text,
                [[at(o), kind, level, payload] for (o, kind, level, payload) in marks[mstart:mstart + mlen]],
                [[at(s), at(e), style] for (s, e, style) in spans[sstart:sstart + slen]],
            ])
        chapters.append(chapter)
    if vi != n:
        raise ValueError(f"{path}: verse count mismatch {vi} != {n}")

    meta_books = meta.get("books") or []
    books = []
    for i, (name, short, ch) in enumerate(BOOKS):
        meta_short = meta_books[i].get("short") if i < len(meta_books) else ""
        books.append([name, meta_short or short, ch])

    return {
        "schema": 1,
        "id": meta["id"],
        "abbrev": meta["abbrev"],
        "name": meta["name"],
        "language": meta.get("language", "en"),
        "license": meta.get("license", ""),
        "copyright": meta.get("copyright", ""),
        "books": books,
        "chapters": chapters,
    }


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__)
        return 2
    src = Path(sys.argv[1])
    out_dir = Path(sys.argv[2])
    out_dir.mkdir(parents=True, exist_ok=True)

    for path in sorted(src.glob("*.bbl")):
        data = decode(path)
        out = out_dir / f"{data['id']}.json"
        out.write_text(json.dumps(data, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
        verses = sum(len(ch) for ch in data["chapters"])
        print(f"{out.name:12} {out.stat().st_size / 1_000_000:5.2f} MB  {verses:>6} verses  {data['name']}")

    ids = sorted(p.stem for p in out_dir.glob("*.json"))
    (out_dir / "index.json").write_text(
        json.dumps({"translations": ids}, separators=(",", ":")),
        encoding="utf-8",
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
