# moonyaml

YAML 1.2.2, read and written as the `Json` tree every other reader in this family
produces. JSON is a subset of YAML, so a document that is JSON loads as itself.

```moonbit
let config = @moonyaml.loads(
  #|server:
  #|  host: 0.0.0.0
  #|  port: 12000
  #|  motd: |
  #|    welcome
  #|    to the party
  #|limits: &shared { files: 1000, bytes: 1048576 }
  #|upload: *shared
)

@moonyaml.dumps(config)        // back to YAML, block style
@moonyaml.loads_all(stream)    // every document in a `---` stream
```

## What it reads

| | |
|:--:|:--|
| Collections | Block mappings and sequences, flow `{}` and `[]`, nested in either direction, a sequence in its parent key's own column |
| Scalars | Plain over several lines, single- and double-quoted with the escapes of §5.7, literal `\|` and folded `>` with chomping and explicit indentation |
| Structure | Anchors and aliases, tags including `%TAG` handles and verbatim `!<…>`, `%YAML`, `---` and `...` document markers |
| Resolution | The core schema of §10.2: `null`/`~`, booleans, decimal, `0o` and `0x` integers, floats with exponents, `.inf` and `.nan` |

`yes` and `no` are strings here, as YAML 1.2 says they are. They are booleans in
YAML 1.1, which is a different version and belongs in a `v11` package rather than in
a flag on this one.

## What it refuses

Everything it cannot resolve to one reading. YAML's own answer to ambiguity is to be
permissive, which is how a configuration file comes to mean something other than what
it looks like; this reader raises `Refused` with a line and column instead.

An unknown tag is refused rather than dropped, because a document that asked for a
type and did not get it has not been read. A mapping key that is itself a collection
is refused, because the tree this produces has string keys and there is no honest way
to spell a sequence as one.

## Configuration

```moonbit
@moonyaml.loads(src, flavor=@moonyaml.Flavor::new(duplicates=Reject))
@moonyaml.loads(src, flavor={ ..@moonyaml.strict, budget: 1000 })
```

| Knob | Preset | Why |
|:--:|:--:|:--|
| `depth` | 500 | Between Jackson's 1000 and serde_json's 128, the same as this family's JSON |
| `duplicates` | `Last` | What every loader in reach does; `First` and `Reject` are there because a key written twice is usually a mistake |
| `aliases` | `true` | An alias is part of the language; `false` refuses one outright |
| `budget` | 10 000 000 | An alias can name a node holding aliases, so a dozen lines can expand to billions — the "billion laughs", which libyaml and PyYAML's `safe_load` both still perform faithfully. There is no common value to follow, so this takes the safe side |

The writer takes `indent` (2, what Kubernetes manifests and Compose files use) and
`sort` (off, so a document keeps the order it was written in).

`dumps_all` opens each document with its own `---`. The two conventions are both in
use — PyYAML and Go's `yaml.v3` write the marker only between documents, `kubectl`
writes it before each — and this takes the one that stays correct under
concatenation. The reader accepts either.

## What is not here

YAML 1.1 (`yes`/`no` booleans, sexagesimals, the `<<` merge key) and StrictYAML,
which are planned as `v11` and `strict` packages beside this one. A rich document
model that keeps anchors, tags and non-string keys as themselves rather than
resolving them into a `Json` tree; the tracking list lives with the project.

## Why this is a library

YAML is not a JSON dialect. It has its own specification, its own versions that
disagree with each other, and constructs — anchors, tags, block scalars, document
streams — that have no JSON counterpart. It reads into the same tree because that is
what a caller wants, not because it is the same language.

## Install

```bash
moon add moonbitstack/moonyaml
```

## Licence

Apache-2.0. See [LICENSE](LICENSE).
