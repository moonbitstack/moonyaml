# moonyaml

YAML for MoonBit, in five versions and two shapes.

<p>
<a href="https://moonbitstack.github.io/moonyaml/">Home</a> ·
<a href="https://moonbitstack.github.io/moonyaml/docs.html">Guide</a> ·
<a href="https://moonbitstack.github.io/moonyaml/api.html">API</a> ·
<a href="https://mooncakes.io/docs/#/moonbitstack/moonyaml/">mooncakes</a>
</p>

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

<!-- nocheck -->
```bash
moon add moonbitstack/moonyaml
```

## The packages

| Package | What it is |
|:--|:--|
| `moonbitstack/moonyaml` | YAML 1.2.2's core schema, the writer, the document model, and the typed codec |
| `moonbitstack/moonyaml/yaml11` | YAML 1.1: `yes`/`no`/`on`/`off` as booleans, `014` as octal, sexagesimals, `1_000`, and the `<<` merge key |
| `moonbitstack/moonyaml/yaml10` | YAML 1.0's types, which 1.1 inherited but did not always keep |
| `moonbitstack/moonyaml/strict` | The strict dialect: block structure only, every scalar a string, no flow style, no anchors, no tags, no repeated keys |
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
| `events_all(nodes)` / `node.events()` | The parse, as the event stream a reader would report |
| `declared_version(src)` | The `%YAML` a document asks for, or `None` |

Each version package carries the same `loads`/`loads_all`/`load`/`load_all`/
`dumps`/`dumps_all`, so a caller can take one as a parameter and a program can
hold a list of versions instead of a branch per version.

## What it reads

| | |
|:--:|:--|
| Collections | Block mappings and sequences, flow `{}` and `[]`, nested in either direction, a sequence in its parent key's own column, a collection as a key |
| Scalars | Plain over several lines (breaks fold, blank lines do not), single- and double-quoted with the escapes of §5.7, literal `\|` and folded `>` with chomping and explicit indentation |
| Structure | Anchors and aliases, tags including `%TAG` handles and verbatim `!<…>`, `%YAML`, `---` and `...` markers, `? key` explicit pairs, complex keys |
| Resolution | The core schema of §10.2: `null`/`~`, booleans, decimal, `0o` and `0x` integers, floats with exponents, `.inf` and `.nan` |

`yes` and `no` are strings here, as YAML 1.2 says they are. They are booleans in
1.1, which is `yaml11`, and the difference is a package boundary rather than a
flag: `014` is twelve there and fourteen here, and `1:30` is ninety there and a
string here.

## The document

`parse` gives back a `Node`: a `kind`, the `text` a scalar was written as, the
`style` of the quoting, whether a collection was `flow`, its `anchor` and `tag`,
the comments `before` it and the one `after` it, and whether the document it heads
was opened by an explicit `---` or closed by a `...`.

```moonbit
let doc = @moonyaml.parse(
  #|# the deployment
  #|name: web
  #|ports: [80, 443]
  #|motd: |
  #|  one
  #|  two
)

match doc.kind {
  Mapping(pairs) => println(pairs[2].0.text)   // ports
  _ => ()
}
println(@moonyaml.emit(doc))   // the same file, comment and all
```

A mapping is an `Array[(Node, Node)]` rather than a map: order is part of a
document, a key is a node rather than a string, and a file may legitimately have a
sequence as a key. An alias stays an alias, so `emit` writes `*shared` instead of
the lines it stands for, and a scalar keeps the spelling it had — `014` is written
back as `014`.

`Node::events` reports the parse instead of the value: one line per event, the
notation the YAML Test Suite uses for a parse tree. It is what a caller compares
with when two documents should be the same *document* rather than the same value —
after an edit that was supposed to touch nothing, say.

<!-- nocheck -->
```
+STR
 +DOC
  +MAP
   =VAL :name
   =VAL :web
  -MAP
 -DOC
-STR
```

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

| `Flavor` | Preset | Why that value |
|:--|:--|:--|
| `depth` | 500 | Deeper than any configuration file nests, shallow enough that the reader's own recursion cannot be driven off the stack |
| `duplicates` | `Last` | A mapping names each key once (§3.2.1.1); where one is written twice, the last is the one the document ends with. `First` and `Reject` are there because a repeated key is usually a mistake |
| `aliases` | `true` | An alias is part of the language; `false` refuses one outright |
| `budget` | 10 000 000 | Nodes one document's aliases may expand to. A dozen lines of aliases can name billions of nodes, so the expansion is counted and capped rather than performed |

| `Style` | Preset | Why that value |
|:--|:--|:--|
| `indent` | 2 | Two columns per level, which is what a hand-written configuration file uses and what fits a diff |
| `width` | 80 | Where a collection stops fitting on a line and `Auto` breaks it |
| `layout` | `Block` | Block style reads better in a diff; `Flow` writes JSON's own shape, `Auto` decides per collection by width |
| `quotes` | `Minimal` | Quote only what has to be quoted, which is what a person writing YAML does |
| `anchors` | `true` | A collection that appears twice is written once and referenced |
| `sort` | `false` | A document keeps the order it was written in; a caller who wants a stable file turns this on |

`dumps_all` opens every document with its own `---`, which is the convention that
stays correct when streams are concatenated. `emit` puts back the markers the
document it was given carried, and nothing else.

## What it refuses

Everything it cannot resolve to one reading. YAML's own answer to ambiguity is to
be permissive, which is how a configuration file comes to mean something other
than what it looks like; this reader raises `Refused` with a line and a column
instead:

<!-- nocheck -->
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
`!!nope 1` is the number 1. Refusing the file instead would make it unreadable,
and inventing a type for it would be worse. `parse` keeps the tag on the node, so
a document can be written back with it intact.

## Examples

<!-- nocheck -->
```bash
moon run src/examples/tour        # everything it reads, in one file
moon run src/examples/versions    # one document, read five ways
moon run src/examples/document    # the document model, and a round trip
```

## Licence

Apache-2.0. See [LICENSE](LICENSE).
