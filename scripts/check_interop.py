#!/usr/bin/env python3
"""Bidirectional interop with two other YAML implementations.

The same corpus goes through every implementation in both directions:

* this library writes every case, the other implementation reads the document
  back, and the value is compared with the one the corpus names;
* the other implementation writes every case, this library reads it back, and
  the value is compared with the same one.

So a disagreement is always a disagreement between two readers over the same
text, never between a reader and its own writer. Everything runs under YAML 1.2
and again under 1.1, which is the pair of schemas the implementations in reach
have; a version is a schema over one scanner, and the two differ in what a bare
scalar means.

The two partners, and why these two:

* **ruamel.yaml** — a full 1.2 implementation, and a round-trip one, so it both
  reads what this library writes and writes documents this library has to read.
  Its 1.2 resolver is the closest thing in reach to the core schema the root
  package implements, which makes a disagreement about reading rather than about
  which release a partner happens to implement. It can be told to resolve under
  1.1 as well, so it covers both lanes.
* **libyaml** — the C implementation the rest of the world is built on: PyYAML's
  C loader, Ruby's Psych and a good part of the Go and Rust ecosystem scan with
  it. Its scanner, parser and emitter are what runs here; the resolver on top is
  PyYAML's 1.1 one, which is what every libyaml user gets. It has no 1.2 mode —
  its resolver is 1.1's — so it is the second opinion on the 1.1 lane, and
  ruamel is the one on the 1.2 lane.

Two readings are declared in the corpus rather than compared, because the
implementations in reach genuinely differ on them and saying so is the honest
form of the test:

* a lone `y`, `Y`, `n` or `N` under 1.1: YAML 1.1's type repository lists the
  four as booleans, ruamel reads them that way, and PyYAML — and so everything
  driven by libyaml — reads them as strings, which is what this library does.
  The case says `contested`, and the check requires that the declared partner
  really does disagree, so the claim cannot quietly stop being true.
* the string `a<NEL>b` under 1.1, with ruamel: its 1.1 dumper puts a bare NEL
  inside a single-quoted scalar, but §5.4 of 1.1 makes NEL a generic line break
  that a reader normalises to a line feed, so here it folds to a space. libyaml
  escapes the character, and both legs agree with it. The case says `contested`
  for ruamel only.

A bare LS or PS used to be contested with libyaml for the same reason. Now that
this reader ends a 1.1 line at those characters too, both legs agree. A stale
`contested` declaration fails the check, so ours were removed rather than left
to overstate the divergence.

A scalar shaped like a timestamp is left out of the corpus: this library has no
date type to hand back, both partners resolve one to a date, and the divergence
is written down in the README instead.

    python scripts/check_interop.py [--keep]

Needs `moon` and the packages in scripts/interop-requirements.txt.
"""

from __future__ import annotations

import argparse
import io
import json
import shutil
import subprocess
import sys
import tempfile
import warnings
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CORPUS = ROOT / "integration" / "interop" / "corpus.json"
EXCHANGE = ROOT / "integration" / "interop"

VERSIONS = {"1.2": (1, 2), "1.1": (1, 1)}


class Ruamel:
    """ruamel.yaml: 1.2 and 1.1, reading and writing."""

    name = "ruamel.yaml"
    tag = "ruamel"
    lanes = ("1.2", "1.1")

    def __init__(self):
        from ruamel.yaml import YAML
        from ruamel.yaml.error import MantissaNoDotYAML1_1Warning

        # 1.1 wants a dot in a float's mantissa and 1.2 does not; this library
        # writes the shortest form, and the partner reads it as the same float.
        warnings.simplefilter("ignore", MantissaNoDotYAML1_1Warning)
        self.YAML = YAML

    def _yaml(self, lane, dumping=False):
        yaml = self.YAML(typ="safe")
        yaml.version = VERSIONS[lane]
        if dumping:
            yaml.default_flow_style = False
            yaml.width = 80
        return yaml

    def read(self, text, lane):
        return self._yaml(lane).load(text)

    def write(self, value, lane):
        stream = io.StringIO()
        self._yaml(lane, dumping=True).dump(value, stream)
        return stream.getvalue()


class Libyaml:
    """libyaml, as PyYAML drives it: 1.1 only, because that is its resolver."""

    name = "libyaml"
    tag = "libyaml"
    lanes = ("1.1",)

    def __init__(self):
        import yaml

        if not getattr(yaml, "__with_libyaml__", False):
            sys.exit(
                "PyYAML was built without libyaml, so what would be measured is"
                " PyYAML's own scanner and not the C implementation; install"
                " libyaml-dev and reinstall PyYAML, or use a wheel that carries it"
            )
        self.yaml = yaml

    def read(self, text, lane):
        return self.yaml.load(text, Loader=self.yaml.CSafeLoader)

    def write(self, value, lane):
        return self.yaml.dump(
            value,
            Dumper=self.yaml.CSafeDumper,
            default_flow_style=False,
            allow_unicode=True,
            sort_keys=False,
            width=80,
        )


def partners() -> list:
    return [Ruamel(), Libyaml()]


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
    return case.get("lanes") or list(VERSIONS)


def contested(case, lane) -> list[str]:
    """The partners the corpus says read this case differently, on purpose."""
    return (case.get("contested") or {}).get(lane, [])


def check_lane(partner, lane, cases, work: Path) -> list[str]:
    """Both legs of one implementation under one version, and every disagreement."""
    ours = work / f"ours-{partner.tag}-{lane}"
    theirs = work / f"theirs-{partner.tag}-{lane}"
    ours.mkdir()
    theirs.mkdir()
    report = work / f"read-{partner.tag}-{lane}.json"
    applied = [c for c in cases if lane in case_lanes(c)]

    exchange("write", str(CORPUS), str(ours), lane)

    wrong: list[str] = []
    agreed_there: set[str] = set()
    agreed_here: set[str] = set()
    read = 0
    round_tripped = 0
    declared = 0

    # Leg one: this library wrote each document, the partner reads it back.
    for case in applied:
        cid, want = case["id"], case["value"]
        document = (ours / f"{cid}.yaml").read_text(encoding="utf-8")
        try:
            got, fault = partner.read(document, lane), None
        except Exception as failure:  # the partner's refusal, as a line of the report
            got, fault = None, failure
        if fault is None and same(got, want):
            read += 1
            agreed_there.add(cid)
        elif partner.name in contested(case, lane):
            declared += 1
        elif fault is not None:
            wrong.append(
                f"{partner.name} {lane} {cid}: refused {describe(document)}: {fault}"
            )
        else:
            wrong.append(
                f"{partner.name} {lane} {cid}: wrote {describe(document)},"
                f" read there as {describe(got)}, wanted {describe(want)}"
            )

    # Leg two: the partner writes each value, and this library reads it back. It
    # reads the whole directory in one process rather than one per document.
    for case in applied:
        stream = partner.write(case["value"], lane)
        (theirs / f"{case['id']}.yaml").write_text(stream, encoding="utf-8")
    exchange("read", str(theirs), str(report), lane)
    read_here = json.loads(report.read_text(encoding="utf-8"))
    values = read_here.get("values", {})
    refused = read_here.get("errors", {})
    for case in applied:
        cid, want = case["id"], case["value"]
        if cid in values and same(values[cid], want):
            round_tripped += 1
            agreed_here.add(cid)
        elif partner.name in contested(case, lane):
            declared += 1
        elif cid in refused:
            wrong.append(f"{partner.name} {lane} {cid}: refused {refused[cid]}")
        elif cid not in values:
            wrong.append(f"{partner.name} {lane} {cid}: no document read")
        else:
            wrong.append(
                f"{partner.name} {lane} {cid}: the other implementation wrote"
                f" {describe((theirs / f'{cid}.yaml').read_text(encoding='utf-8'))},"
                f" read here as {describe(values[cid])}, wanted {describe(want)}"
            )

    # A case the corpus declares contested has to stay contested: if a partner
    # starts agreeing on both legs, the declaration is stale.
    for case in applied:
        cid = case["id"]
        if partner.name in contested(case, lane) and cid in agreed_there and cid in agreed_here:
            wrong.append(
                f"{partner.name} {lane} {cid}: declared contested, but both legs agreed"
            )

    print(
        f"interop {partner.name} {lane}: {len(applied)} documents —"
        f" {read} written here and read there, {round_tripped} written there and read here,"
        f" {declared} declared different, {len(wrong)} disagreed"
    )
    return wrong


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--keep", action="store_true", help="leave the exchanged documents in place")
    options = parser.parse_args()

    sync_workspace()
    cases = json.loads(CORPUS.read_text(encoding="utf-8"))
    work = Path(tempfile.mkdtemp(prefix="moonyaml-interop-"))
    try:
        wrong: list[str] = []
        for partner in partners():
            for lane in partner.lanes:
                wrong.extend(check_lane(partner, lane, cases, work))
        for line in wrong:
            print("  " + line)
        if wrong:
            print(f"{len(wrong)} disagreements")
            return 1
        print(f"interop: {len(cases)} cases, two implementations, both directions")
        return 0
    finally:
        if options.keep:
            print(f"documents kept in {work}")
        else:
            shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    raise SystemExit(main())
