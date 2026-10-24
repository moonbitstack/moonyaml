# moonyaml

YAML for MoonBit, in five versions and two shapes.

A document can be read as a **value** — the `Json` tree every reader in this family
produces — or as a **document**, a tree that keeps the comments, the anchors, the
tags and the style it was written with, so it can be written back. Both come from
one scanner: a version is a resolver, not a fork.

```moonbit
let config = @moonyaml.loads(
  #|server:
  #|  host: 0.0.0.0
  #|  port: 12000
  #|limits: &shared { files: 1000, bytes: 1048576 }
  #|upload: *shared
)

@moonyaml.dumps(config)      // back to YAML, block style
@moonyaml.loads_all(stream)  // every document in a `---` stream
```

```moonbit
let doc = @moonyaml.parse(src)   // keeps the comments too
@moonyaml.emit(doc)              // and writes them back
doc.to_json()                    // what it means, for a caller who wants a value
```

## Install

```bash
moon add moonbitstack/moonyaml
```

## The packages

| Package | What it is |
|:--|:--|
| `moonbitstack/moonyaml` | YAML 1.2.2's core schema, the writer, the document model, and the typed codec |
| `moonbitstack/moonyaml/yaml11` | YAML 1.1: `yes`/`no`/`on`/`off` as booleans, `014` as octal, sexagesimals, `1_000`, and the `<<` merge key |
| `moonbitstack/moonyaml/yaml10` | YAML 1.0's types, which 1.1 inherited but did not always keep |
| `moonbitstack/moonyaml/strict` | StrictYAML: block structure only, every scalar a string, no flow style, no anchors, no tags, no duplicate keys |
| `moonbitstack/moonyaml/any` | Reads the version a document asks for with `%YAML`, and 1.2.2 when it asks for nothing |

They are packages rather than a flag because a version is a promise about meaning:
`yes` is a boolean in one and a string in another, and a reader that decides which
by looking at the file is a reader whose output a caller cannot type. `any` exists
for the caller who is reading files they did not write, and it is the only package
that guesses — from the document, once, at the top.

## The interface

| Function | Gives back |
|:--|:--|
| `loads(src)` / `loads_all(src)` | `Json` — the one document, or every document in the stream |
| `load(bytes)` / `load_all(bytes)` | The same, decoding UTF-8 and skipping a leading BOM |
| `loads_as[T](src)` / `load_as[T](bytes)` | A typed value, through `@json.FromJson` |
| `dumps(value)` / `dumps_all(values)` | YAML text |
| `dump(value)` / `dump_all(values)` | The same, as `Bytes` |
| `dumps_of[T](value)` / `dumps_of_all[T](values)` | The same, through `@json.ToJson` |
| `round_trip[T](src, adjust~)` | A typed value written back, for checking that a decode is a decode |
| `parse(src)` / `parse_all(src)` | `Node` — the document, comments and all |
| `emit(node)` | YAML text that reads back as the same document |

Each version package carries the same `loads`/`loads_all`/`load`/`load_all`/
`dumps`/`dumps_all`, so a caller can take one as a parameter. `tests/versions`
holds a `Version` record for exactly that, and the examples use it.

## What it reads

| | |
|:--:|:--|
| Collections | Block mappings and sequences, flow `{}` and `[]`, nested in either direction, a sequence in its parent key's own column |
| Scalars | Plain over several lines (breaks fold, blank lines do not), single- and double-quoted with the escapes of §5.7, literal `\|` and folded `>` with chomping and explicit indentation |
| Structure | Anchors and aliases, tags including `%TAG` handles and verbatim `!<…>`, `%YAML`, `---` and `...` markers, `? key` explicit pairs, complex keys |
| Resolution | The core schema of §10.2: `null`/`~`, booleans, decimal, `0o` and `0x` integers, floats with exponents, `.inf` and `.nan` |

`yes` and `no` are strings here, as YAML 1.2 says they are. They are booleans in
1.1, which is `yaml11`, and the difference is a package boundary rather than a
flag — see the suite table below for exactly where the versions part company.

## The versions, measured

The [YAML Test Suite](https://github.com/yaml/yaml-test-suite) is 402 cases. This
build reads **363 of them as the suite says** — 271 compared against the JSON the
suite gives, 92 refused where the suite requires a refusal — and answers two
differently; 37 cases carry no JSON at all (complex keys, duplicate keys) and are
skipped by the comparison.

| Version | Same as 1.2.2 | Reads differently | Refused by both | Refused only here | Read only here |
|:--|--:|--:|--:|--:|--:|
| 1.2.2 (core) | 292 | 0 | 110 | 0 | 0 |
| 1.1 | 291 | 1 | 110 | 0 | 0 |
| 1.0 | 290 | 2 | 110 | 0 | 0 |
| StrictYAML | 155 | 25 | 110 | 112 | 0 |

Every version reads every document 1.2.2 reads and refuses every document it
refuses; the columns that would show otherwise are zero for each of them. That is
the claim the shared scanner makes, and the table is the test that checks it: it
is asserted in `src/tests/versions/suite_wbtest.mbt`, so a change that moves a
number moves this README too or fails the build.

What the differing cases are: `12:30` is a sexagesimal (750) in 1.1 and 1.0 and a
string in 1.2; `!!`-tagged documents resolve against the 1.0 tag set differently;
StrictYAML reads every scalar as a string and refuses the 112 documents that use
flow style, anchors, aliases or tags.

### The two cases read differently

Both are tab faults the suite wants refused and this reader reads:

| Case | Why |
|:--|:--|
| `DK95/2` | A tab where a continuation line's indentation belongs |
| `Y79Y/4` | A tab-only line at the head of a block scalar |

PyYAML, libyaml and ruamel.yaml all read both, which is why this reader does too:
refusing them would refuse documents that load everywhere else. The list is
pinned in `src/tests/core/harness.mbt` and cannot rot — a case that starts passing
fails the test.

### The document model, measured

Read as a document, 278 of the 292 documents this reader reads agree value for
value with the value reader. The other 14 are listed in
`src/tests/core/doc_wbtest.mbt` with their reason: twelve are constructs the value
reader understands and the document reader refuses to guess at (an implicit key
in a flow collection, an alias where a key belongs), one is a comment after an
alias, one is an explicit document that holds nothing.

## Configuration

Two records, each with presets, each field overridable, and every knob reachable
as a named argument on the call:

```moonbit
@moonyaml.loads(src, flavor=@moonyaml.Flavor::new(duplicates=Reject))
@moonyaml.loads(src, flavor={ ..@moonyaml.strict, budget: 1000 })
@moonyaml.dumps(value, style=@moonyaml.flow)
@moonyaml.dumps(value, indent=4, sort=true)
```

A flat argument wins over a field of the record, which wins over the preset's
value. There is no other way to change a default, and no default is hidden.

| `Flavor` | Preset | Where the number comes from |
|:--|:--|:--|
| `depth` | 500 | Between Jackson's 1000 and serde_json's 128, and the same as this family's JSON reader |
| `duplicates` | `Last` | What every loader in reach does. `First` and `Reject` are there because a key written twice is usually a mistake |
| `aliases` | `true` | An alias is part of the language; `false` refuses one outright |
| `budget` | 10 000 000 | An alias can name a node holding aliases, so a dozen lines can expand to billions — the "billion laughs", which libyaml and PyYAML's `safe_load` both still perform faithfully. There is no common value to follow, so this takes the safe side |

| `Style` | Preset | Where the number comes from |
|:--|:--|:--|
| `indent` | 2 | What Kubernetes manifests and Compose files use; the value `kubectl` writes |
| `width` | 80 | Where a flow collection stops fitting on a line — the width every formatter has used since the terminal |
| `layout` | `Block` | Block style reads better in a diff; `Flow` writes JSON's own shape, `Auto` decides per collection by width |
| `quotes` | `Minimal` | Quote only what has to be quoted, which is what a person writing YAML does |
| `anchors` | `true` | A collection that appears twice is written once and referenced, which is what PyYAML and ruamel.yaml do with a shared object |
| `sort` | `false` | A document keeps the order it was written in; a caller who wants a stable file turns this on |

`dumps_all` opens every document with its own `---`. Both conventions are in use —
PyYAML and Go's `yaml.v3` write the marker only between documents, `kubectl`
writes it before each — and this takes the one that stays correct when documents
are concatenated. The reader accepts either.

## What it refuses

Everything it cannot resolve to one reading. YAML's own answer to ambiguity is to
be permissive, which is how a configuration file comes to mean something other
than what it looks like; this reader raises `Refused` with a line and a column
instead:

```
a: [1, 2      =>  1:4:  ends mid-document
a: *nope      =>  1:4:  no anchor named `nope`
a: 1, a: 2    =>  2:1:  the key `a` is written twice
```

A mapping key that is itself a collection is refused by `loads`, because the tree
it produces has string keys and there is no honest way to spell a sequence as one
— `parse` keeps it, since a document has keys that are not strings.

A tag from a vocabulary this reader does not have — a local `!foo`, a
`!!python/object`, an unregistered `tag:example.com,2000:app/foo` — is **not** one
of those. §10.4 permits a processor to resolve such a node as if it carried no
tag, and that is what happens: the scalar keeps the type its text has, so
`!!nope 1` is the number 1. PyYAML raises `ConstructorError` instead, and the
difference is deliberate — a reader that refuses `!!python/object` cannot read the
file at all, and one that quietly turns it into a mapping has invented a type
nobody asked for. `parse` keeps the tag on the node, so a document can be written
back with it intact.

## Where this differs from the readers you know

| | PyYAML 6 | ruamel.yaml | libyaml (C) | moonyaml |
|:--|:--|:--|:--|:--|
| `yes`, `on` | boolean | boolean (1.1 mode) | boolean | **string** in `moonyaml`, boolean in `yaml11` |
| `014` | 12 | 12 | 12 | **14** in `moonyaml` (§10.2 makes it decimal), 12 in `yaml11` |
| `0o14` | string | string | string | 12 in `moonyaml`, **string** in `yaml11` |
| Duplicate keys | last wins, silently | warning, then last wins | last wins | last wins, or `First`/`Reject` — a choice |
| Unknown tag | `ConstructorError` | `ConstructorError` | accepted, tag ignored | accepted, resolved untagged (§10.4); `parse` keeps it |
| Alias expansion | unbounded | unbounded | unbounded | capped at 10 000 000 nodes |
| A collection as a key | tuple key | tuple key | accepted | refused by `loads`, kept by `parse` |
| Comments, style | dropped | kept | dropped | dropped by `loads`, kept by `parse` |
| Repeats on write | anchor + alias | anchor + alias | — | anchor + alias, or `anchors: false` |
| `---` on write | between documents | between documents | — | before every document |
| Tabs in indentation | read as separation | read as separation | read as separation | read as separation |

`ruamel.yaml` is the only one of them that keeps comments, and it is the model the
document tree here follows: read, change, write, and get the file back.

## Tests

```bash
moon test --target all     # 61 tests, four backends
```

Beyond the unit tests there are four gates, and each is a test rather than a
script, so it runs in CI:

- **the suite**, as YAML 1.2.2, against every case (`src/tests/core`)
- **the suite beside 1.2.2**, for every version (`src/tests/versions`)
- **the document model beside the value model**, over the same suite
  (`src/tests/core/doc_wbtest.mbt`)
- **the divergence lists**, which fail in either direction: a new difference is a
  decision, and a listed difference that starts passing is a stale claim

`tools/gen_suite.py` regenerates the suite data from a checkout of
`yaml-test-suite`, and `tools/sync_diverged.py` rewrites a divergence list from a
run. Neither is needed to build or test.

## Examples

```bash
moon run src/examples/tour        # everything it reads, in one file
moon run src/examples/versions    # one document, read five ways
moon run src/examples/document    # the document model, and a round trip
```

The guide and the API reference are at
[moonbitstack.github.io/moonyaml](https://moonbitstack.github.io/moonyaml/).

## Licence

Apache-2.0. See [LICENSE](LICENSE).
