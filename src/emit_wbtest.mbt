// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
test "a document opened by a marker is written back with it" {
  assert_eq(emit(parse("---\na: 1\n")), "---\na: 1\n")
  assert_eq(emit(parse("a: 1\n...\n")), "a: 1\n...\n")
  assert_eq(emit(parse("---\na: 1\n...\n")), "---\na: 1\n...\n")
  // A document that carried neither gets neither, so embedding one in a stream
  // does not invent a marker its author did not write.
  assert_eq(emit(parse("a: 1\n")), "a: 1\n")
}

///|
test "the indent and the column are knobs, and the nesting follows them" {
  let nested = "a:\n  b:\n    c: 1\n"
  assert_eq(emit(parse(nested)), nested)
  assert_eq(emit(parse(nested), indent=4), "a:\n    b:\n        c: 1\n")
  assert_eq(emit(parse(nested), from=2), "  a:\n    b:\n      c: 1\n")
}

///|
test "the flow flag, the quoting and the block scalar are the document's own" {
  let src =
    #|plain: one
    #|single: 'two'
    #|double: "three"
    #|block: |
    #|  four
    #|  five
    #|flow: [6, 7]
  let text = src + "\n"
  assert_eq(emit(parse(text)), text)
}

///|
test "a comment attached to a node is written above the line it describes" {
  let built = Node::map([
    (Node::scalar("name"), Node::scalar("web")),
    (
      Node::scalar("ports").commented(before=["what it listens on"], after=""),
      Node::seq([Node::scalar("80"), Node::scalar("443")]).in_flow(true),
    ),
  ])
  assert_eq(emit(built), "name: web\n# what it listens on\nports: [80, 443]\n")
}

///|
test "a tree built from a value is a document this writes and reads back" {
  let value = loads("a: [1, 2]\nb:\n  c: d\n"[:])
  let doc = Node::of_json(value)
  let text = emit(doc)
  // Built from a value rather than parsed, so the shape is the writer's: block
  // collections, one entry a line, and no flow style to keep.
  assert_eq(text, "a:\n  - 1\n  - 2\nb:\n  c: d\n")
  assert_eq(loads(text[:]).stringify(), value.stringify())
}

///|
test "every document this parses, it emits and parses to the same document" {
  let cases = [
    "a: 1\n", "# c\nkey: value\n", "---\n- 1\n- 2\n", "a:\n  b:\n    - c: 1\n", "x: &a {p: 1}\ny: *a\n",
    "lit: |\n  one\n  two\n", "flow: {a: 1}\n", "? [1, 2]\n: three\n",
  ]
  for src in cases {
    let doc = parse(src[:])
    let again = parse(emit(doc)[:])
    assert_eq(again.same(doc), true)
    assert_eq(emit(again), emit(doc))
  }
}
