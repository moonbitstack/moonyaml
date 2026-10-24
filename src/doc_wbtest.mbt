// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Read a document, write it back, read it again: the tree has to survive the
/// round trip, which is the whole point of a document model.
fn round(src : String) -> Bool raise Refused {
  let first = parse(src[:])
  let written = emit(first)
  let second = parse(written[:])
  if first.same(second) {
    true
  } else {
    println("written: >\{written}<")
    println("first:  \{show_tree(first)}")
    println("second: \{show_tree(second)}")
    false
  }
}

///|
fn style_name(style : ScalarStyle) -> String {
  match style {
    Plain => "plain"
    ScalarStyle::Single => "single"
    ScalarStyle::Double => "double"
    Literal(n) => "literal\{n}"
    Folded(n) => "folded\{n}"
  }
}

///|
fn show_tree(node : Node) -> String {
  match node.kind {
    Mapping(pairs) => {
      let parts : Array[String] = []
      for pair in pairs {
        parts.push(show_tree(pair.0) + ": " + show_tree(pair.1))
      }
      "{" + parts.join(", ") + "}"
    }
    Sequence(items) => {
      let parts : Array[String] = []
      for item in items {
        parts.push(show_tree(item))
      }
      "[" + parts.join(", ") + "]"
    }
    Alias(name) => "*" + name
    _ => style_name(node.style) + "<" + node.text + ">"
  }
}

///|
test "a round trip keeps the document a document" {
  assert_eq(round("a: 1\nb: two\nc: [1, 2, 3]\n"), true)
  assert_eq(round("- a\n- b: c\n  d: e\n"), true)
  assert_eq(round("nested:\n  - - 1\n    - 2\n  - key: value\n"), true)
  assert_eq(round("flow: {a: 1, b: [2, 3]}\n"), true)
  assert_eq(round("empty: {}\nlist: []\nnull: ~\n"), true)
  assert_eq(round("quoted: 'it''s'\ndouble: \"a\\tb\"\n"), true)
  assert_eq(round("text: |\n  one\n  two\nfolded: >\n  one\n  two\n"), true)
  assert_eq(round("strip: |-\n  one\nkeep: |+\n  one\n\n"), true)
  assert_eq(round("# above\na: 1 # beside\n# below\nb: 2\n"), true)
  assert_eq(round("base: &b\n  x: 1\nchild:\n  <<: *b\n  y: 2\n"), true)
  assert_eq(round("? [one, two]\n: a value\n"), true)
  assert_eq(round("1: one\ntrue: yes\nnull: nothing\n"), true)
  assert_eq(round("tagged: !!str 1\n"), true)
  assert_eq(round("%YAML 1.2\n---\na: 1\n"), true)
}

///|
test "the style a scalar was written in is the style it is written back in" {
  let doc = parse(
    "plain: 1\nsingle: 'a'\ndouble: \"b\"\nblock: |\n  c\nfolded: >\n  d\n",
  )
  match doc.kind {
    Mapping(pairs) => {
      assert_eq(pairs[0].1.style == Plain, true)
      assert_eq(pairs[1].1.style == ScalarStyle::Single, true)
      assert_eq(pairs[2].1.style == ScalarStyle::Double, true)
      assert_eq(pairs[3].1.style == ScalarStyle::Literal(0), true)
      assert_eq(pairs[4].1.style == ScalarStyle::Folded(0), true)
    }
    _ => fail("a mapping")
  }
  let written = emit(doc)
  // And a reader that only wants the values still gets the strings.
  assert_eq(
    loads(written[:]).stringify(),
    "{\"plain\":1,\"single\":\"a\",\"double\":\"b\",\"block\":\"c\\n\",\"folded\":\"d\\n\"}",
  )
}

///|
test "a comment stays where it was written" {
  let doc = parse("# the top\na: 1 # beside\n")
  assert_eq(doc.before, ["the top"])
  match doc.kind {
    Mapping(pairs) => assert_eq(pairs[0].1.after, Some("beside"))
    _ => fail("a mapping")
  }
  assert_eq(emit(doc), "# the top\na: 1 # beside\n")
}

///|
test "an anchor stays an anchor and an alias stays a reference" {
  let doc = parse("a: &x 1\nb: *x\n")
  match doc.kind {
    Mapping(pairs) => {
      assert_eq(pairs[0].1.anchor, Some("x"))
      match pairs[1].1.kind {
        Alias(name) => assert_eq(name, "x")
        _ => fail("an alias")
      }
    }
    _ => fail("a mapping")
  }
  // The value, for a caller who only wants the value.
  assert_eq(doc.to_json().stringify(), "{\"a\":1,\"b\":1}")
  assert_eq(emit(doc), "a: &x 1\nb: *x\n")
}

///|
test "a key that is not a string is kept as the node it is" {
  let doc = parse("1: one\ntrue: two\n? [a, b]\n: three\n")
  match doc.kind {
    Mapping(pairs) => {
      assert_eq(pairs[0].0.text, "1")
      assert_eq(pairs[1].0.text, "true")
      match pairs[2].0.kind {
        Sequence(items) => assert_eq(items.length(), 2)
        _ => fail("a sequence key")
      }
    }
    _ => fail("a mapping")
  }
  // `Json` has only string keys, so the value keeps them as text.
  assert_eq(
    doc.to_json().stringify(),
    "{\"1\":\"one\",\"true\":\"two\",\"[\\\"a\\\",\\\"b\\\"]\":\"three\"}",
  )
}

///|
test "a tree written for a value reads back as that value" {
  let value = loads("a: 1\nb:\n  - x\n  - y: 2\n"[:])
  let written = emit(Node::of_json(value))
  assert_eq(loads(written[:]).stringify(), value.stringify())
  assert_eq(written, "a: 1\nb:\n  - x\n  - y: 2\n")
}

///|
test "a document that is only a scalar is still a document" {
  assert_eq(emit(parse("hello\n")), "hello\n")
  assert_eq(emit(parse("42\n")), "42\n")
  assert_eq(parse("42\n").text, "42")
  assert_eq(emit(parse("")), "\n")
}
