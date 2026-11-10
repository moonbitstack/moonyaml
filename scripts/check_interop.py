#!/usr/bin/env python3
"""Bidirectional interop with another YAML implementation.

The same corpus goes through both implementations in both directions:

* this library writes every case, the other implementation reads the document
  back, and the value is compared with the one the corpus names;
* the other implementation writes every case, this library reads it back, and
  the value is compared with the same one.

So a disagreement is always a disagreement between two readers over the same
text, never between a reader and its own writer. Both directions run under
YAML 1.2 and again under 1.1, because a version is a schema over one scanner
and the two schemas differ in what a bare scalar means.

The other implementation is ruamel.yaml, and the reasons are:

* it resolves scalars under the same schema as the root package here — 1.2's
  core schema, where `yes` is a string and `0x1f` a number — so a disagreement
  is about reading, not about which version a partner happens to implement;
* it can be told to resolve under 1.1 as well, so one dependency covers both
  lanes, including the 1.1 package whose rules are hardest to check;
* it both reads and writes, which is what "in both directions" needs; a
  parser-only partner would leave the writer unmeasured;
* it is pure Python and pins to an exact version, so the check is the same on
  every machine and needs no build step.

Its 1.2 resolver is wider than the core schema in three places, and the corpus
says so where it matters: `1_000` and `0b1010` are numbers to it and strings to
the core schema, so those cases are exchanged under 1.1 only, where both sides
agree; a timestamp-shaped scalar is left out of the corpus altogether, since
this library has no timestamp type to hand back and the divergence is written
down in the README instead.

    python scripts/check_interop.py [--keep]

Needs `moon` and `ruamel.yaml==0.19.1` (see scripts/interop-requirements.txt).
"""

from __future__ import annotations

import argparse
import io
import json
import warnings
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CORPUS = ROOT / "integration" / "interop" / "corpus.json"
EXCHANGE = ROOT / "integration" / "interop"

LANES = {"1.2": (1, 2), "1.1": (1, 1)}


def load_ruamel():
    try:
        from ruamel.yaml import YAML
        from ruamel.yaml.error import MantissaNoDotYAML1_1Warning

        # 1.1 wants a dot in a float's mantissa and 1.2 does not; this library
        # writes the shortest form, and the partner reads it as the same float.
        warnings.simplefilter("ignore", MantissaNoDotYAML1_1Warning)
    except ModuleNotFoundError:
        sys.exit(
            "ruamel.yaml is not installed; "
            "pip install -r scripts/interop-requirements.txt"
        )
    return YAML


def reader(YAML, version):
    yaml = YAML(typ="safe")
    yaml.version = version
    return yaml


def writer(YAML, version):
    yaml = YAML(typ="safe")
    yaml.version = version
    yaml.default_flow_style = False
    yaml.width = 80
    return yaml


def same(one, other) -> bool:
    """Whether two values are the same value, with a boolean never an integer."""
    if isinstance(one, bool) or isinstance(other, bool):
        return isinstance(one, bool) and isinstance(other, bool) and one == other
    if one is None or other is None:
        return one is None and other is None
    if isinstance(one, (int, float)) and isinstance(other, (int, float)):
        # Python compares an int with a float exactly, which is what a value
        # that came back through a double needs.
        return one == other
    if isinstance(one, str) and isinstance(other, str):
        return one == other
    if isinstance(one, list) and isinstance(other, list):
        return len(one) == len(other) and all(same(a, b) for a, b in zip(one, other))
    if isinstance(one, dict) and isinstance(other, dict):
        return one.keys() == other.keys() and all(same(one[k], other[k]) for k in one)
    return False


def describe(value) -> str:
    """A value as one line of a report — a date or a set is not JSON, and is said as it is."""
    try:
        text = json.dumps(value, ensure_ascii=False)
    except TypeError:
        text = repr(value)
    return text if len(text) <= 120 else text[:117] + "..."


def sync_workspace() -> None:
    """Keep the exchange module's pin on this module in step with its version.

    `moon.work` resolves `moonbitstack/moonyaml` to the tree here, and the member
    has to name the version it resolves to; a release moves that number, so it is
    synced once before the build rather than left to fail on the next one.
    """
    subprocess.run(["moon", "work", "sync", "-q"], cwd=ROOT, check=False)


def exchange(*arguments: str) -> None:
    subprocess.run(
        ["moon", "run", "src/main", "--target", "native", "--", *arguments],
        cwd=EXCHANGE,
        check=True,
        stdout=subprocess.DEVNULL,
    )


def case_lanes(case) -> list[str]:
    return case.get("lanes") or list(LANES)


def lane_name(version) -> str:
    return f"{version[0]}.{version[1]}"


def check_lane(YAML, version, cases, work: Path) -> list[str]:
    """Both legs of one version, and every disagreement as a line of text."""
    lane = lane_name(version)
    ours = work / f"ours-{lane}"
    theirs = work / f"theirs-{lane}"
    ours.mkdir()
    theirs.mkdir()
    report = work / f"read-{lane}.json"
    applied = [c for c in cases if lane in case_lanes(c)]

    exchange("write", str(CORPUS), str(ours), lane)

    wrong: list[str] = []
    read = 0
    round_tripped = 0
    partner_reads = reader(YAML, version)
    partner_writes = writer(YAML, version)

    # Leg one: this library wrote each document, the partner reads it back.
    for case in applied:
        cid, want = case["id"], case["value"]
        document = (ours / f"{cid}.yaml").read_text(encoding="utf-8")
        try:
            got = partner_reads.load(document)
        except Exception as fault:  # the partner's refusal, reported as a line
            wrong.append(f"{lane} {cid}: the other implementation refused {describe(document)}: {fault}")
            continue
        if same(got, want):
            read += 1
        else:
            wrong.append(
                f"{lane} {cid}: wrote {describe(document)}, read there as {describe(got)},"
                f" wanted {describe(want)}"
            )

    # Leg two: the partner writes each value, and this library reads it back. It
    # reads the whole directory in one process rather than one per document.
    for case in applied:
        stream = io.StringIO()
        partner_writes.dump(case["value"], stream)
        (theirs / f"{case['id']}.yaml").write_text(stream.getvalue(), encoding="utf-8")
    exchange("read", str(theirs), str(report), lane)
    read_here = json.loads(report.read_text(encoding="utf-8"))
    values = read_here.get("values", {})
    refused = read_here.get("errors", {})
    for case in applied:
        cid, want = case["id"], case["value"]
        if cid in refused:
            wrong.append(f"{lane} {cid}: refused {refused[cid]}")
        elif cid not in values:
            wrong.append(f"{lane} {cid}: no document read")
        elif same(values[cid], want):
            round_tripped += 1
        else:
            wrong.append(
                f"{lane} {cid}: the other implementation wrote"
                f" {describe((theirs / f'{cid}.yaml').read_text(encoding='utf-8'))},"
                f" read here as {describe(values[cid])}, wanted {describe(want)}"
            )

    print(
        f"interop {lane}: {len(applied)} documents — {read} written here and read there,"
        f" {round_tripped} written there and read here, {len(wrong)} disagreed"
    )
    return wrong


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--keep", action="store_true", help="leave the exchanged documents in place")
    options = parser.parse_args()

    YAML = load_ruamel()
    sync_workspace()
    cases = json.loads(CORPUS.read_text(encoding="utf-8"))
    work = Path(tempfile.mkdtemp(prefix="moonyaml-interop-"))
    try:
        wrong: list[str] = []
        for version in LANES.values():
            wrong.extend(check_lane(YAML, version, cases, work))
        for line in wrong:
            print("  " + line)
        if wrong:
            print(f"{len(wrong)} disagreements")
            return 1
        print(f"interop: {len(cases)} cases agree in both directions, under YAML 1.2 and 1.1")
        return 0
    finally:
        if options.keep:
            print(f"documents kept in {work}")
        else:
            shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    raise SystemExit(main())
