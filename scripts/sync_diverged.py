#!/usr/bin/env python3
"""Keep a suite harness's `diverged` list in step with what the reader does.

The harnesses under `src/tests` run the YAML Test Suite and fail when the
divergences they see are not the ones they list. That is the right assertion to
make, but it means an improvement to the reader has to be recorded. This script
runs one harness, reads the list of divergences it printed, and rewrites the
`diverged` array in that harness's MoonBit source.

    python scripts/sync_diverged.py                      # the 1.2.2 harness
    python scripts/sync_diverged.py --package .../v11 --source .../v11_wbtest.mbt

It exits non-zero when it could not read the run at all, so a broken build is not
mistaken for a clean list.
"""

from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def moon() -> str:
    """The `moon` to run.

    `moon` on PATH may be a shell script — the installer's shim is — and a
    script is not something Windows can start as a process, so the toolchain's
    own binary is preferred where it exists.
    """
    from_env = os.environ.get("MOON")
    if from_env:
        return from_env
    candidates = [
        Path.home() / ".moon" / "bin" / "moon.exe",
        Path.home() / ".moon" / "bin" / "moon",
    ]
    for candidate in candidates:
        if candidate.exists():
            return str(candidate)
    found = shutil.which("moon")
    if found:
        return found
    raise SystemExit("moon is not installed, or not on PATH")

# What a harness prints after a case's id. Keeping the vocabulary here means a
# name that happens to contain a colon is not mistaken for the split.
REASONS = re.compile(
    r"^(?P<id>\S+?): (?P<why>refused|read a document the suite says must be refused|"
    r"\d+ documents?, expected \d+|\{.*\} is not \{.*\}|\[.*\] is not \[.*\])"
    r"  \(.*\)$"
)

ARRAY = re.compile(r"pub let diverged : Array\[\(String, String\)\] = \[\n(.*?)\n\]", re.S)


def run(package: str) -> list[tuple[str, str]]:
    result = subprocess.run(
        [moon(), "test", "-p", package, "--target", "wasm-gc"],
        cwd=ROOT,
        capture_output=True,
        text=True,
    )
    output = result.stdout + result.stderr
    if "Total tests:" not in output:
        sys.stderr.write(output)
        raise SystemExit("could not read the test run; is the build clean?")
    seen: list[tuple[str, str]] = []
    inside = False
    for line in output.splitlines():
        if line.startswith("suite("):
            inside = True
            continue
        if not inside:
            continue
        if not line.startswith("  "):
            if line.strip() == "":
                continue
            break
        match = REASONS.match(line[2:])
        if match is None:
            continue
        seen.append((match.group("id"), match.group("why")))
    return seen


def quote(text: str) -> str:
    """A MoonBit string literal, escaped the way the rest of the file is."""
    out = ['"']
    for ch in text:
        if ch == "\\":
            out.append("\\\\")
        elif ch == '"':
            out.append('\\"')
        elif ch == "\n":
            out.append("\\n")
        elif ch == "\t":
            out.append("\\t")
        else:
            out.append(ch)
    out.append('"')
    return "".join(out)


def rewrite(source: Path, seen: list[tuple[str, str]]) -> bool:
    text = source.read_text(encoding="utf-8")
    body = "\n".join(f"  ({quote(case_id)}, {quote(why)})," for case_id, why in seen)
    replaced, count = ARRAY.subn(
        lambda _: f"pub let diverged : Array[(String, String)] = [\n{body}\n]",
        text,
    )
    if count != 1:
        raise SystemExit(f"{source}: found {count} `diverged` arrays, expected one")
    if replaced == text:
        return False
    source.write_text(replaced, encoding="utf-8")
    return True


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--package", default="moonbitstack/moonyaml/tests/core")
    parser.add_argument(
        "--source", default=str(ROOT / "src" / "tests" / "core" / "harness.mbt")
    )
    args = parser.parse_args()

    seen = run(args.package)
    changed = rewrite(Path(args.source), seen)
    print(
        f"{len(seen)} diverged, {'rewritten' if changed else 'unchanged'}: {args.source}"
    )


if __name__ == "__main__":
    main()
