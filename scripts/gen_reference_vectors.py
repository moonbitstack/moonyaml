#!/usr/bin/env python3
"""Generate the MoonBit data files for the two YAML 1.1 behaviours that have no
official test set: the line breaks NEL, LS and PS, and the `!!timestamp` type.

Neither is covered by the YAML Test Suite, which is written for 1.2, so the
reference for both is another implementation. PyYAML's scanner and resolver are
the ones libyaml gives to most of the world's YAML readers, and it implements
1.1, so it is the second opinion here. Every document and every spelling is
listed below rather than sampled: a vector file says what it measures.

    python scripts/gen_reference_vectors.py           # write the data files
    python scripts/gen_reference_vectors.py --check   # fail if they would change

`--check` is what CI runs, so a data file that no longer matches the reference
fails the build instead of quietly measuring a different state of it.
"""

from __future__ import annotations

import argparse
import datetime
import json
import os
import subprocess
import sys
from pathlib import Path

try:
    import yaml
except ModuleNotFoundError:
    raise SystemExit("PyYAML is needed: python -m pip install -r scripts/interop-requirements.txt")

DATA = Path(__file__).resolve().parent.parent / "src" / "tests" / "data"

LOADER = getattr(yaml, "CSafeLoader", yaml.SafeLoader)

NEL = "\u0085"
LS = "\u2028"
PS = "\u2029"

# Documents whose lines end in one of the three characters 1.1 read as a break.
# They cover the places a break can stand: between two block entries, inside a
# folded scalar, inside a literal one, inside flow brackets, in a quoted scalar,
# around the document markers, and mixed with the CRLF a Windows editor writes.
BREAK_DOCUMENTS = [
    ("nel-between-entries", f"a: 1{NEL}b: 2{NEL}"),
    ("nel-folds-a-plain-scalar", f"a: one{NEL}  two{NEL}"),
    ("nel-in-a-literal", f"a: |{NEL}  one{NEL}  two{NEL}"),
    ("nel-keeps-trailing-breaks", f"a: |+{NEL}  one{NEL}{NEL}"),
    ("nel-in-a-folded-scalar", f"a: >{NEL}  one{NEL}  two{NEL}"),
    ("nel-before-the-first-entry", f"{NEL}{NEL}a: 1{NEL}"),
    ("nel-between-document-markers", f"---{NEL}a: 1{NEL}...{NEL}"),
    ("nel-inside-flow-brackets", f"a: [1,{NEL} 2]{NEL}"),
    ("nel-keeps-a-sequence-entry", f"-{NEL}  a{NEL}"),
    ("nel-beside-crlf", f"a: 1\r\nb: 2{NEL}c: 3\r\n"),
    ("ls-in-a-literal", f"a: |{LS}  one{LS}  two{LS}"),
    ("ls-in-a-folded-scalar", f"a: >{LS}  one{LS}  two{LS}"),
    ("ls-folds-nothing", f"a: x{LS}  y{LS}"),
    ("ls-twice-folds-nothing", f"a: x{LS}{LS}  y{LS}"),
    ("ls-in-a-double-quoted-scalar", f'a: "x{LS}y"{LS}'),
    ("ls-in-a-single-quoted-scalar", f"a: 'x{LS}y'{LS}"),
    ("ps-in-a-literal", f"a: |{PS}  one{PS}"),
    ("ps-in-a-double-quoted-scalar", f'a: "x{PS}y"{PS}'),
]

# Spellings of a point in time, from yaml.org/type/timestamp.html and the
# neighbourhood of it: the padded and the bare forms, every separator, a zone
# written as an offset, as a bare hour and as a letter, and the dates a calendar
# does not have.
TIMESTAMP_TEXTS = [
    "2001-12-15T02:59:43.1Z",
    "2001-12-14t21:59:43.10-05:00",
    "2001-12-14 21:59:43.10 -5",
    "2001-12-15 02:59:43 Z",
    "2001-12-15T02:59:43",
    "2001-12-15T02:59:43+05",
    "2001-12-15T02:59:43-00:00",
    "2001-12-15T02:59:43.000Z",
    "2002-12-14",
    "2001-1-5",
    "2000-2-29",
    "2001-2-29",
    "2001-02-30",
    "2001-13-01",
    "2001-00-10",
    "2001-12-15T25:00:00Z",
    "2001-12-15T02:60:00Z",
    "2001-12-15T02:59:60Z",
    "20011215",
    "2001-12-15T02:59Z",
    "2001-12-15T02:59:43+0530",
    "0000-01-01",
    "not-a-date",
]


def mbt(text: str) -> str:
    """A MoonBit double-quoted literal for `text`."""
    out = ['"']
    for ch in text:
        if ch in '\\"':
            out.append("\\" + ch)
        elif ch == "\n":
            out.append("\\n")
        elif ch == "\r":
            out.append("\\r")
        elif ch == "\t":
            out.append("\\t")
        elif 0x20 <= ord(ch) <= 0x7E:
            out.append(ch)
        else:
            out.append("\\u{%x}" % ord(ch))
    out.append('"')
    return "".join(out)


def formatted(text: str) -> str:
    """The text the formatter leaves.

    A generated data file is laid out by `moon fmt` rather than by this script, so
    what is committed is what the toolchain makes of it: the repository gate runs the
    formatter, and a layout written here by hand would have to be re-derived from it
    every time the formatter changed its mind.
    """
    probe = DATA / "_gen_probe.mbt"
    try:
        probe.write_text(text, encoding="utf-8", newline="\n")
        subprocess.run(
            [os.environ.get("MOON", "moon"), "fmt", str(probe)],
            check=True,
            cwd=DATA.parent.parent.parent,
            stdout=subprocess.DEVNULL,
        )
        return probe.read_text(encoding="utf-8").replace("\r\n", "\n")
    finally:
        probe.unlink(missing_ok=True)


def canonical(value) -> str:
    """A point in time the way this library writes one: ISO 8601 order, every field
    padded, the fraction without the zeros that carry no meaning, and the zone as
    `Z` or as an offset."""
    if not isinstance(value, datetime.datetime):
        return f"{value.year:04d}-{value.month:02d}-{value.day:02d}"
    text = (
        f"{value.year:04d}-{value.month:02d}-{value.day:02d}"
        f"T{value.hour:02d}:{value.minute:02d}:{value.second:02d}"
    )
    if value.microsecond:
        text += "." + f"{value.microsecond:06d}".rstrip("0")
    offset = value.utcoffset()
    if offset is not None:
        seconds = int(offset.total_seconds())
        if seconds == 0:
            text += "Z"
        else:
            sign = "+" if seconds > 0 else "-"
            seconds = abs(seconds)
            text += f"{sign}{seconds // 3600:02d}:{seconds % 3600 // 60:02d}"
    return text


def read_breaks() -> list[tuple[str, str]]:
    """Each document, and the value the reference reads it as, as JSON text."""
    vectors = []
    for name, document in BREAK_DOCUMENTS:
        try:
            value = yaml.load(document, Loader=LOADER)
        except Exception as fault:  # a document the reference cannot read is not a vector
            raise SystemExit(f"{name}: the reference refused it: {fault}")
        vectors.append((document, json.dumps(value, ensure_ascii=True, sort_keys=True)))
    return vectors


def read_timestamps() -> list[tuple[str, str | None]]:
    """Each spelling, and the point in time the reference makes of it, or `None`
    where it refuses the date."""
    vectors = []
    for text in TIMESTAMP_TEXTS:
        try:
            value = yaml.load(f"t: !!timestamp {text}", Loader=LOADER)["t"]
            vectors.append((text, canonical(value)))
        except Exception:
            vectors.append((text, None))
    return vectors


def write_breaks(vectors: list[tuple[str, str]]) -> str:
    lines = [
        "// Generated by scripts/gen_reference_vectors.py from PyYAML. Do not edit.",
        "",
        "///|",
        "/// Documents whose lines end in NEL, LS or PS, and the value YAML 1.1 reads each",
        "/// of them as: what the reference implementation makes of the same text.",
        "pub let breaks : Array[(String, String)] = [",
    ]
    for document, value in vectors:
        lines.append(f"  ({mbt(document)}, {mbt(value)}),")
    lines.append("]")
    return "\n".join(lines) + "\n"


def write_timestamps(vectors: list[tuple[str, str | None]]) -> str:
    lines = [
        "// Generated by scripts/gen_reference_vectors.py from PyYAML. Do not edit.",
        "",
        "///|",
        "/// Spellings of a point in time, and what `!!timestamp` makes of each: the text in",
        "/// ISO 8601 order, or `None` where the reference refuses a date that never",
        "/// happened.",
        "pub let timestamps : Array[(String, String?)] = [",
    ]
    for text, value in vectors:
        made = "None" if value is None else f"Some({mbt(value)})"
        lines.append(f"  ({mbt(text)}, {made}),")
    lines.append("]")
    return "\n".join(lines) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="fail if a data file would change")
    options = parser.parse_args()

    generated = {
        DATA / "breaks.mbt": formatted(write_breaks(read_breaks())),
        DATA / "timestamps.mbt": formatted(write_timestamps(read_timestamps())),
    }
    stale = []
    for path, text in generated.items():
        current = path.read_text(encoding="utf-8") if path.exists() else ""
        if current == text:
            continue
        if options.check:
            stale.append(path.name)
        else:
            path.write_text(text, encoding="utf-8", newline="\n")
    if stale:
        print("these data files no longer match the reference: " + ", ".join(stale))
        return 1
    if not options.check:
        print(f"{len(read_breaks())} documents and {len(read_timestamps())} spellings written")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
