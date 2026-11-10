#!/usr/bin/env python3
"""Generate the MoonBit data file for the YAML Test Suite.

The suite itself is not vendored: this script reads a checkout of
https://github.com/yaml/yaml-test-suite (the `src/*.yaml` files) and writes
`src/tests/data/suite_data.mbt`, which is what the test harnesses compile
against. The revision is pinned below, so what the tests measure is one known
state of the suite rather than whatever `main` happened to be that morning:

    python scripts/gen_suite.py [checkout]          # write the file
    python scripts/gen_suite.py [checkout] --check  # fail if it would change

`--check` is what CI runs, against a tarball of the pinned revision, so a
committed data file that no longer matches its input fails the build instead of
quietly measuring something else. To move to a newer suite, bump `SUITE_COMMIT`
and `SUITE_DATE` here, regenerate, and commit the two together.

The default path is `.ref/yaml-test-suite`, which is where a checkout beside
this repository lands. The escape conventions (`␣`, `———»`, `↵`, `∎`, `←`, `⇔`)
are the suite's own, from bin/YAMLTestSuite.pm in that repository.
"""

from __future__ import annotations

import json
import re
import subprocess
import sys
import tempfile
from pathlib import Path

try:
    import yaml
except ModuleNotFoundError:
    # A checkout of https://github.com/yaml/pyyaml beside this repository is
    # enough: its `lib` directory is the package, so the data can be regenerated
    # without installing anything.
    vendored = Path(__file__).resolve().parent.parent / ".ref" / "pyyaml" / "lib"
    if not vendored.is_dir():
        raise SystemExit(
            "pyyaml is not installed; `pip install pyyaml` or clone yaml/pyyaml into .ref"
        )
    sys.path.insert(0, str(vendored))
    import yaml

DEFAULT_SUITE = Path(__file__).resolve().parent.parent / ".ref" / "yaml-test-suite"
OUT = Path(__file__).resolve().parent.parent / "src" / "tests" / "data" / "suite_data.mbt"

# The revision of yaml/yaml-test-suite the committed data file was made from.
# Every count in the file's header comes from this state of the suite, so the
# two have to move together.
SUITE_COMMIT = "da267a5c4782e7361e82889e76c0dc7df0e1e870"
SUITE_DATE = "2025-12-25"

# The suite's own unescape, from bin/YAMLTestSuite.pm.
UNESCAPES = [
    (re.compile("␣"), " "),
    (re.compile("—*»"), "\t"),
    (re.compile("←"), "\r"),
    (re.compile("⇔"), "\ufeff"),
    (re.compile("↵"), ""),
]

# What a case may inherit from the case above it in the same file, which is what
# the suite's own tooling does: a file of several cases that differ in nothing
# but the expected outcome writes the source once.
INHERITED = ("name", "tags", "yaml", "tree", "json")


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


def revision(suite: Path) -> str:
    """The revision of the checkout, so a file made from another one is refused."""
    git = suite / ".git"
    if not git.exists():
        # A tarball of the pinned revision has no history to ask; the file it
        # produces names the revision, and that is what `--check` compares.
        return SUITE_COMMIT
    return subprocess.run(
        ["git", "-C", str(suite), "rev-parse", "HEAD"],
        capture_output=True,
        text=True,
        check=True,
    ).stdout.strip()


def normalise(text: str) -> str:
    """The file as a run of tokens, with what the formatter owns taken out.

    Two runs of this script agree on the data; where a line breaks and whether the
    last element of an array carries a comma are `moon fmt`'s business, so the
    comparison is over the tokens rather than the layout. Commas are only dropped
    outside a string, since a document in one may hold anything.
    """
    tokens: list[tuple[str, bool]] = []
    inside = False
    escaped = False
    for line in text.split("\n"):
        if not inside and line.lstrip().startswith("//"):
            continue
        for ch in line:
            if inside:
                tokens.append((ch, True))
                if escaped:
                    escaped = False
                elif ch == "\\":
                    escaped = True
                elif ch == '"':
                    inside = False
            elif ch == '"':
                inside = True
                tokens.append((ch, True))
            elif not ch.isspace():
                tokens.append((ch, False))
    out = []
    for i, (ch, quoted) in enumerate(tokens):
        if ch == "," and not quoted:
            after = tokens[i + 1] if i + 1 < len(tokens) else None
            if after is not None and not after[1] and after[0] in "]}":
                continue
        out.append(ch)
    return "".join(out)


def render(cases) -> str:
    """The data file, as the text that goes in the repository."""
    out = []
    comparable = sum(1 for c in cases if c["comparable"])
    failing = sum(1 for c in cases if c["fail"])
    trees = sum(1 for c in cases if c["tree"])
    out.append("// Generated by scripts/gen_suite.py from the YAML Test Suite. DO NOT EDIT.\n")
    out.append("//\n")
    out.append(f"// The suite at revision {SUITE_COMMIT}\n")
    out.append(f"// ({SUITE_DATE}): {len(cases)} cases, {comparable} with a JSON value,\n")
    out.append(f"// {trees} with an event stream, {failing} that must be refused.\n")
    out.append("//\n")
    out.append("// One entry per case: the source, the event stream it must produce, the\n")
    out.append("// JSON each document is expected to read as, and whether the source must\n")
    out.append("// be refused at all.\n\n")
    out.append("///|\n")
    out.append("pub(all) struct Case {\n")
    out.append("  /// The suite's own id for the case: the file it came from, and which\n")
    out.append("  /// case in that file, since a name is not always unique.\n")
    out.append("  id : String\n")
    out.append("  /// What the case is about, in the suite's words.\n")
    out.append("  name : String\n")
    out.append("  /// The document, as the suite writes it.\n")
    out.append("  src : String\n")
    out.append("  /// One entry per expected document; empty is either a refusal or an\n")
    out.append("  /// empty stream, which `comparable` tells apart.\n")
    out.append("  docs : Array[String]\n")
    out.append("  comparable : Bool\n")
    out.append("  fail : Bool\n")
    out.append("  /// The event stream the source must produce, one event per line, in\n")
    out.append("  /// the suite's own notation.\n")
    out.append("  tree : String\n")
    out.append("}\n\n")
    out.append("///|\n")
    out.append("pub let cases : Array[Case] = [\n")
    for c in cases:
        docs = [mbt_string(d) for d in c["docs"]]
        out.append("  {\n")
        out.append(f"    id: {mbt_string(c['id'])},\n")
        out.append(f"    name: {mbt_string(c['name'])},\n")
        out.append(f"    src: {mbt_string(c['src'])},\n")
        # A trailing comma is what `moon fmt` puts after the last element, on one
        # line or several; an empty array has none.
        body = ", ".join(docs)
        out.append(f"    docs: [{body + ',' if docs else ''}],\n")
        out.append(f"    comparable: {str(c['comparable']).lower()},\n")
        out.append(f"    fail: {str(c['fail']).lower()},\n")
        out.append(f"    tree: {mbt_string(c['tree'])},\n")
        out.append("  },\n")
    out.append("]\n")
    return "".join(out)


def main() -> int:
    arguments = [a for a in sys.argv[1:] if not a.startswith("--")]
    check = "--check" in sys.argv[1:]
    suite = Path(arguments[0]) if arguments else DEFAULT_SUITE
    src = suite / "src"
    if not src.is_dir():
        print(f"no suite at {src}; pass the path to a yaml-test-suite checkout")
        return 1
    found = revision(suite)
    if found != SUITE_COMMIT:
        print(
            f"the suite at {suite} is at {found}, not the pinned {SUITE_COMMIT};"
            " check out the pinned revision, or bump the pin and regenerate"
        )
        return 1

    cases = []
    for path in sorted(src.glob("*.yaml")):
        data = yaml.safe_load(path.read_text(encoding="utf-8"))
        if data[0].get("skip"):
            continue
        cache = {}
        seen = 0
        for test in data:
            # `json: null` is a field the case wrote down as empty, not one it
            # left out: the suite's own tooling tests `exists`, and so does this.
            for key in INHERITED:
                if key not in test and cache.get(key) is not None:
                    test[key] = cache[key]
            cache = {k: test.get(k) for k in INHERITED}
            yaml_text = unescape(test["yaml"])
            fail = bool(test.get("fail"))
            raw_json = test.get("json")
            # A refusal has nothing to compare against, whatever the file says:
            # the document is not meant to be read at all.
            comparable = raw_json is not None and not fail
            docs = (
                [
                    json.dumps(d, ensure_ascii=False)
                    for d in split_docs(unescape(raw_json))
                ]
                if comparable
                else []
            )
            # The file name is the suite's own id for the case; a file holding
            # several cases gets a suffix, so every case has one of its own.
            seen += 1
            case_id = path.stem if seen == 1 else f"{path.stem}/{seen}"
            cases.append(
                {
                    "id": case_id,
                    "name": test["name"],
                    "src": yaml_text,
                    "docs": docs,
                    "comparable": comparable,
                    "fail": fail,
                    "tree": unescape(test.get("tree") or ""),
                }
            )

    cases.sort(key=lambda c: c["id"])
    text = render(cases)
    comparable = sum(1 for c in cases if c["comparable"])
    failing = sum(1 for c in cases if c["fail"])
    trees = sum(1 for c in cases if c["tree"])

    if check:
        if not OUT.exists():
            print(f"{OUT} does not exist; run scripts/gen_suite.py")
            return 1
        if normalise(OUT.read_text(encoding="utf-8")) != normalise(text):
            with tempfile.NamedTemporaryFile("w", suffix=".mbt", delete=False, encoding="utf-8") as fh:
                fh.write(text)
            print(
                f"{OUT} is not what the pinned suite produces;"
                f" the expected file is in {fh.name}"
            )
            return 1
        print(
            f"{OUT.name} is current: {len(cases)} cases at {SUITE_COMMIT[:7]}"
        )
        return 0

    OUT.parent.mkdir(parents=True, exist_ok=True)
    with OUT.open("w", encoding="utf-8", newline="\n") as fh:
        fh.write(text)
    print(
        f"{len(cases)} cases: {comparable} with a value, {trees} with events, "
        f"{failing} must fail"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
