#!/usr/bin/env python3
"""Generate the MoonBit data file for the YAML Test Suite.

The suite itself is not vendored: this script reads a checkout of
https://github.com/yaml/yaml-test-suite (the `src/*.yaml` files) and writes
`tests/data/suite_data.mbt`, which is what the test harness compiles against.
Re-run it when the suite gains tests:

    python scripts/gen_suite.py [path-to-yaml-test-suite]

The default path is ../yaml-test-suite, which is where a clone beside this
repository lands. The escape conventions (`␣`, `———»`, `↵`, `∎`, `←`, `⇔`) are
the suite's own, from bin/YAMLTestSuite.pm in that repository.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

try:
    import yaml
except ModuleNotFoundError:
    # A checkout of https://github.com/yaml/pyyaml beside this repository is
    # enough: its `lib` directory is the package, so the suite can be regenerated
    # without installing anything.
    vendored = Path(__file__).resolve().parent.parent / ".ref" / "pyyaml" / "lib"
    if not vendored.is_dir():
        raise SystemExit("pyyaml is not installed; `pip install pyyaml` or clone yaml/pyyaml into .ref")
    sys.path.insert(0, str(vendored))
    import yaml

DEFAULT_SUITE = Path(__file__).resolve().parent.parent / ".ref" / "yaml-test-suite"
OUT = Path(__file__).resolve().parent.parent / "src" / "tests" / "data" / "suite_data.mbt"

# The suite's own unescape, from bin/YAMLTestSuite.pm.
UNESCAPES = [
    (re.compile("␣"), " "),
    (re.compile("—*»"), "\t"),
    (re.compile("←"), "\r"),
    (re.compile("⇔"), "\ufeff"),
    (re.compile("↵"), ""),
]


def unescape(text: str) -> str:
    for pattern, repl in UNESCAPES:
        text = pattern.sub(repl, text)
    return re.sub("∎\n\\Z", "", text)


def split_docs(text: str) -> list[str]:
    """A suite `json` field holds one JSON value per document, back to back."""
    decoder = json.JSONDecoder()
    docs = []
    index = 0
    while index < len(text):
        while index < len(text) and text[index] in " \t\r\n":
            index += 1
        if index >= len(text):
            break
        value, index = decoder.raw_decode(text, index)
        docs.append(value)
    return docs


def tree_flags(tree: str) -> dict[str, bool]:
    """What a document uses, read off its event stream.

    The tree marks an anchor `&a`, an alias `=ALI *a`, a tag `<…>` right after
    the event name, and flow style as `[]` / `{}` after the node name.
    """
    anchors = bool(re.search(r"&\S+", tree))
    aliases = bool(re.search(r"=ALI\s+\*", tree))
    tagged = bool(
        re.search(r"(?:^|\n)\s*(?:=VAL|[+-](?:MAP|SEQ|DOC))\s+(?:&\S+\s+)?<", tree)
    )
    flow = bool(re.search(r"[+-](?:MAP|SEQ)\s*\{\}|[+-](?:MAP|SEQ)\s*\[\]", tree))
    return {
        "anchors": anchors,
        "aliases": aliases,
        "tagged": tagged,
        "flow": flow,
    }


def mbt_string(text: str) -> str:
    """A MoonBit string literal, escaping only what has to be escaped."""
    out = ['"']
    for ch in text:
        code = ord(ch)
        if ch == '"':
            out.append('\\"')
        elif ch == "\\":
            out.append("\\\\")
        elif ch == "\n":
            out.append("\\n")
        elif ch == "\r":
            out.append("\\r")
        elif ch == "\t":
            out.append("\\t")
        elif code < 0x20 or 0x7F <= code <= 0x9F:
            out.append("\\u{%x}" % code)
        else:
            out.append(ch)
    out.append('"')
    return "".join(out)


def main() -> int:
    suite = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_SUITE
    src = suite / "src"
    if not src.is_dir():
        print(f"no suite at {src}; pass the path to a yaml-test-suite checkout")
        return 1

    cases = []
    for path in sorted(src.glob("*.yaml")):
        data = yaml.safe_load(path.read_text(encoding="utf-8"))
        if data[0].get("skip"):
            continue
        # A file may hold several cases; `name`, `tags` and `yaml` carry over
        # from the one before, which is what the suite's own tooling does.
        cache = {}
        seen = 0
        for test in data:
            for key in ("name", "tags", "yaml"):
                if test.get(key) is None and cache.get(key) is not None:
                    test[key] = cache[key]
            cache = {k: test.get(k) for k in ("name", "tags", "yaml")}
            yaml_text = unescape(test["yaml"])
            tree = unescape(test.get("tree") or "")
            fail = bool(test.get("fail"))
            raw_json = test.get("json")
            comparable = raw_json is not None and not fail
            docs = (
                [json.dumps(d, ensure_ascii=False) for d in split_docs(unescape(raw_json))]
                if comparable
                else []
            )
            flags = tree_flags(tree)
            # The file name is the suite's own id for the case; a file holding
            # several cases gets a suffix, so every case has one of its own.
            seen += 1
            case_id = path.stem if seen == 1 else f"{path.stem}/{seen}"
            cases.append(
                {
                    "id": case_id,
                    "name": test["name"],
                    "tags": (test.get("tags") or "").strip(),
                    "src": yaml_text,
                    "docs": docs,
                    "comparable": comparable,
                    "fail": fail,
                    **flags,
                }
            )

    cases.sort(key=lambda c: c["id"])
    OUT.parent.mkdir(parents=True, exist_ok=True)
    with OUT.open("w", encoding="utf-8", newline="\n") as fh:
        fh.write("// Generated by scripts/gen_suite.py from the YAML Test Suite. DO NOT EDIT.\n")
        fh.write("//\n")
        fh.write("// One entry per case: the source, the JSON each document is expected to\n")
        fh.write("// read as, whether it must be refused, and what its event stream says it\n")
        fh.write("// uses — which is what tells the StrictYAML harness what to refuse.\n\n")
        fh.write("pub(all) struct Case {\n")
        fh.write("  /// The suite's own id for the case: the file it came from, and which\n")
        fh.write("  /// case in that file, since a name is not always unique.\n")
        fh.write("  id : String\n")
        fh.write("  name : String\n")
        fh.write("  tags : String\n")
        fh.write("  src : String\n")
        fh.write("  /// One entry per expected document; empty is either a refusal or an\n")
        fh.write("  /// empty stream, which `comparable` tells apart.\n")
        fh.write("  docs : Array[String]\n")
        fh.write("  comparable : Bool\n")
        fh.write("  fail : Bool\n")
        fh.write("  anchors : Bool\n")
        fh.write("  aliases : Bool\n")
        fh.write("  tagged : Bool\n")
        fh.write("  flow : Bool\n")
        fh.write("}\n\n")
        fh.write("pub let cases : Array[Case] = [\n")
        for c in cases:
            docs = ", ".join(mbt_string(d) for d in c["docs"])
            fh.write("  {\n")
            fh.write(f"    id: {mbt_string(c['id'])},\n")
            fh.write(f"    name: {mbt_string(c['name'])},\n")
            fh.write(f"    tags: {mbt_string(c['tags'])},\n")
            fh.write(f"    src: {mbt_string(c['src'])},\n")
            fh.write(f"    docs: [{docs}],\n")
            fh.write(f"    comparable: {str(c['comparable']).lower()},\n")
            fh.write(f"    fail: {str(c['fail']).lower()},\n")
            fh.write(f"    anchors: {str(c['anchors']).lower()},\n")
            fh.write(f"    aliases: {str(c['aliases']).lower()},\n")
            fh.write(f"    tagged: {str(c['tagged']).lower()},\n")
            fh.write(f"    flow: {str(c['flow']).lower()},\n")
            fh.write("  },\n")
        fh.write("]\n")

    comparable = sum(1 for c in cases if c["comparable"])
    failing = sum(1 for c in cases if c["fail"])
    print(f"{len(cases)} cases: {comparable} comparable, {failing} must fail")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
