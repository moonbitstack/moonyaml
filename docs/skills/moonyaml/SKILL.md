---
name: moonyaml
description: "Reads and writes YAML 1.2.2, 1.1, 1.0 and the strict dialect in MoonBit, as a Json value or as a document that keeps its comments. Reach for it for configuration files, manifests and Compose files, and especially for files that have to be edited and written back."
---

# moonyaml

<!-- nocheck -->
```bash
moon add moonbitstack/moonyaml
```

The root package is YAML 1.2.2, with the writer, the document model and the typed
codec. A version that reads differently is a package of its own, and each carries
the same `loads`/`loads_all`/`load`/`load_all`/`dumps`/`dumps_all`:

| Package | Meaning |
|:--|:--|
| `moonbitstack/moonyaml` | 1.2.2: `yes` is a string, `014` is fourteen |
| `moonbitstack/moonyaml/yaml11` | 1.1: `yes` is a boolean, `014` is twelve, `12:30` is 750, `1e3` is a string, `<<` merges |
| `moonbitstack/moonyaml/yaml10` | 1.0: 1.1, and `y`/`n` are booleans too |
| `moonbitstack/moonyaml/strict` | Block structure, every scalar a string, no tags or anchors |
| `moonbitstack/moonyaml/any` | The version the document names with `%YAML`, 1.2.2 when it names none |

```moonbit
import {
  "moonbitstack/moonyaml",
  "moonbitstack/moonyaml/yaml11",
}
```

## Read a configuration file

```moonbit
test {
  let src =
    #|server:
    #|  host: 0.0.0.0
    #|  port: 12000
  let config = @moonyaml.loads(src + "\n")
  assert_eq(
    config.stringify(),
    "{\"server\":{\"host\":\"0.0.0.0\",\"port\":12000}}",
  )
}
```

A file usually has a shape you already know, and `loads_as` decodes into it through
the same `@json.FromJson` a JSON document uses — a record with
`#derive(FromJson)` on it, or any type that implements the trait:

```moonbit
test {
  let ports : Array[Int] = @moonyaml.loads_as("- 80\n- 443\n")
  assert_eq(ports, [80, 443])
}
```

`loads_as` raises `Malformed`, whose two arms are worth telling apart:
`Read(Refused)` means the text is not YAML, `Shape(JsonDecodeError)` means it is
YAML of the wrong shape.

## Read a file whose vintage you do not know

```moonbit
test {
  // A file that says what it is gets read that way.
  let config = @any.loads("%YAML 1.1\n---\nenabled: yes\n")
  assert_eq(config.stringify(), "{\"enabled\":true}")
  // One that says nothing is 1.2.2.
  assert_eq(
    @any.loads("enabled: yes\n").stringify(),
    "{\"enabled\":\"yes\"}",
  )
}
```

Taking the version from the document is the only guess this library makes, and it
makes it once, at the top. Reach for a fixed package when you know the answer.

## Edit a file and write it back

`loads` gives a value, and a value has no comments, anchors or quoting left in it.
`parse` gives a `Node`, which does, and `emit` writes it:

```moonbit
test {
  let src = "# deploy\nimage: nginx:1.27\nreplicas: 2\n"
  let doc = @moonyaml.parse(src)
  let bumped = match doc.kind {
    Mapping(pairs) =>
      {
        ..doc,
        kind: Mapping(
          pairs.map(fn(pair) {
            if pair.0.text == "replicas" {
              (pair.0, @moonyaml.Node::scalar("3"))
            } else {
              pair
            }
          }),
        ),
      }
    _ => doc
  }
  assert_eq(@moonyaml.emit(bumped), "# deploy\nimage: nginx:1.27\nreplicas: 3\n")
}
```

## Rules that catch people out

- `yes`, `no`, `on`, `014` and `12:30` are strings in the root package, because
  1.2 says they are. If a file means them as booleans and numbers, read it with
  `yaml11`, not with a flag on this one.
- A mapping in a `Node` is an `Array[(Node, Node)]`: order is part of a document,
  and a key is a node. Rebuild it with `{ ..doc, kind: Mapping(pairs) }` so the
  comments the node carried stay where they are.
- `loads` refuses a stream. Two documents separated by `---` are a `Trailing`
  refusal from `loads` and the answer from `loads_all`.
- Anchors do not survive `loads` — the alias is expanded, and writing the value
  back invents anchor names of its own (`&a0`). Use `parse` and `emit` to keep the
  names a person wrote.
- `dumps` writes block style at two spaces and quotes only what has to be quoted.
  `Style` and `Flavor` are records with presets; `Style::new()` by itself is the
  preset, and a flat argument (`indent=4`, `sort=true`) wins over both.
- What counts as "has to be quoted" comes from the `rules` you pass: with
  `rules=@moonyaml.legacy_rules` a `yes`, a `1_000` or a `1:30` that is a string
  is quoted, so a 1.1 reader gets the string. The preset rules quote only what
  1.2 would resolve.
- A whole number wider than a double holds keeps the digits it was read with, so
  an identifier of twenty digits survives a read and a write; compare it with
  `stringify()`, not as a `Double`.
- Every `Refused` carries `at`, `line` and `column`, and prints as
  `line:column: what` — `1:4: ends mid-document`. Match on the arm to tell a
  broken file from an unsupported one.
- `<<` is a merge key only in `yaml11`; in the root package it is an ordinary key
  named `<<`, as 1.2 has it.
- `load` takes bytes, decodes UTF-8 and skips a leading BOM; `loads` takes text.
