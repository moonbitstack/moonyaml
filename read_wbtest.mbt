// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A document, as the compact JSON it denotes, so a test reads as the mapping it
/// is checking rather than as a tree of constructors.
fn j(src : String) -> String raise Refused {
  loads(src[:]).stringify()
}

///|
test "a mapping, a sequence, and the nesting of one in the other" {
  assert_eq(j("a: 1\nb: two\n"), "{\"a\":1,\"b\":\"two\"}")
  assert_eq(j("- 1\n- 2\n"), "[1,2]")
  assert_eq(j("a:\n  b:\n    c: 1\n"), "{\"a\":{\"b\":{\"c\":1}}}")
  assert_eq(j("a:\n  - 1\n  - 2\n"), "{\"a\":[1,2]}")
  // A sequence's `-` may sit in the same column as its parent key (§8.2.1).
  assert_eq(j("a:\n- 1\n- 2\n"), "{\"a\":[1,2]}")
  // A mapping that begins on the `-` line continues under its first key.
  assert_eq(j("- a: 1\n  b: 2\n"), "[{\"a\":1,\"b\":2}]")
  // And a sequence nested compactly in a sequence.
  assert_eq(j("- - 1\n  - 2\n"), "[[1,2]]")
}

///|
test "the core schema resolves a scalar by what it looks like" {
  assert_eq(j("a: null\nb: ~\nc:\n"), "{\"a\":null,\"b\":null,\"c\":null}")
  assert_eq(j("a: Null\nb: NULL\n"), "{\"a\":null,\"b\":null}")
  assert_eq(
    j("a: true\nb: False\nc: TRUE\n"),
    "{\"a\":true,\"b\":false,\"c\":true}",
  )
  assert_eq(j("a: 1\nb: -2\nc: +3\n"), "{\"a\":1,\"b\":-2,\"c\":3}")
  assert_eq(j("a: 0x1f\nb: 0o17\n"), "{\"a\":31,\"b\":15}")
  assert_eq(
    j("a: 1.5\nb: 1e3\nc: 2.5e-2\n"),
    "{\"a\":1.5,\"b\":1000,\"c\":0.025}",
  )
  // A quoted scalar is a string whatever it looks like, which is the whole reason
  // to quote it.
  assert_eq(
    j("a: \"1\"\nb: '1.0'\nc: \"true\"\n"),
    "{\"a\":\"1\",\"b\":\"1.0\",\"c\":\"true\"}",
  )
  // And anything that is not wholly numeric is the string it looks like.
  assert_eq(j("a: 1.2.3\nb: 12ab\n"), "{\"a\":\"1.2.3\",\"b\":\"12ab\"}")
}

///|
test "the five scalar styles, including the two the old reader could not hold" {
  // Literal: the line breaks are the value, which is how a script or a key goes
  // into a configuration file.
  assert_eq(j("a: |\n  one\n  two\n"), "{\"a\":\"one\\ntwo\\n\"}")
  // Folded: a break between two content lines becomes a space.
  assert_eq(j("a: >\n  one\n  two\n"), "{\"a\":\"one two\\n\"}")
  // Chomping: `-` drops the trailing break, `+` keeps every one of them.
  assert_eq(j("a: |-\n  one\n"), "{\"a\":\"one\"}")
  assert_eq(j("a: |+\n  one\n\n\n"), "{\"a\":\"one\\n\\n\\n\"}")
  // A blank line inside a literal block is a blank line.
  assert_eq(j("a: |\n  one\n\n  two\n"), "{\"a\":\"one\\n\\ntwo\\n\"}")
  // An explicit indentation indicator, for content that starts with spaces.
  assert_eq(j("a: |2\n    one\n"), "{\"a\":\"  one\\n\"}")
}

///|
test "quoted scalars spell what no other style can" {
  assert_eq(j("a: \"x\\ty\"\n"), "{\"a\":\"x\\ty\"}")
  assert_eq(j("a: \"\\u0041\\x42\"\n"), "{\"a\":\"AB\"}")
  // A single-quoted scalar has no escapes at all, which is why a Windows path is
  // written in one.
  assert_eq(j("a: 'C:\\x'\n"), "{\"a\":\"C:\\\\x\"}")
  assert_eq(j("a: 'it''s'\n"), "{\"a\":\"it's\"}")
  // A break inside a quoted scalar folds to a space.
  assert_eq(j("a: \"one\n  two\"\n"), "{\"a\":\"one two\"}")
  // Except where a backslash eats it, which is the only way to write a long line
  // with no break in it.
  assert_eq(j("a: \"one\\\n  two\"\n"), "{\"a\":\"onetwo\"}")
}

///|
test "a plain scalar runs over lines, and stops where meaning begins" {
  assert_eq(j("a: one\n  two\n"), "{\"a\":\"one two\"}")
  assert_eq(j("a: one\n\n  two\n"), "{\"a\":\"one\\ntwo\"}")
  // It stops at the next key rather than swallowing the rest of the mapping.
  assert_eq(j("a: one\nb: two\n"), "{\"a\":\"one\",\"b\":\"two\"}")
  // A `#` after a space is a comment; one glued to a character is the value.
  assert_eq(j("a: one # note\n"), "{\"a\":\"one\"}")
  assert_eq(j("a: one#two\n"), "{\"a\":\"one#two\"}")
}

///|
test "flow collections, which may span lines" {
  assert_eq(j("a: [1, 2, 3]\n"), "{\"a\":[1,2,3]}")
  assert_eq(j("a: {x: 1, y: 2}\n"), "{\"a\":{\"x\":1,\"y\":2}}")
  assert_eq(j("a: [1, {x: 2}, [3]]\n"), "{\"a\":[1,{\"x\":2},[3]]}")
  // Spanning lines is what a line-based reader cannot do.
  assert_eq(j("a: [\n  1,\n  2,\n]\n"), "{\"a\":[1,2]}")
  assert_eq(j("a: {\n  x: 1,\n  y: 2,\n}\n"), "{\"a\":{\"x\":1,\"y\":2}}")
  // An empty one is empty, not null.
  assert_eq(j("a: []\nb: {}\n"), "{\"a\":[],\"b\":{}}")
  // JSON is YAML, which is the point of §1.3.
  assert_eq(j("{\"a\": [1, 2], \"b\": null}"), "{\"a\":[1,2],\"b\":null}")
}

///|
test "an anchor names a node and an alias is that node" {
  assert_eq(j("a: &x 1\nb: *x\n"), "{\"a\":1,\"b\":1}")
  assert_eq(
    j("base: &b\n  x: 1\n  y: 2\ncopy: *b\n"),
    "{\"base\":{\"x\":1,\"y\":2},\"copy\":{\"x\":1,\"y\":2}}",
  )
  // An anchor on a sequence entry, which is where a Compose file puts one.
  assert_eq(j("- &x one\n- *x\n"), "[\"one\",\"one\"]")
}

///|
test "an alias to nothing, and aliases turned off, are both refused" {
  assert_eq(refused("a: *nope\n"), true)
  let no_aliases = Flavor::new(aliases=false)
  let mut out = false
  try {
    let _ = loads("a: &x 1\nb: *x\n"[:], flavor=no_aliases)
  } catch {
    BadAnchor(_) => out = true
    _ => ()
  }
  assert_eq(out, true)
}

///|
test "the budget stops a document that expands to more than it spells" {
  // Eight anchors, each doubling the one before: the shape of the billion laughs.
  let bomb = "a: &a [x, x]\n" +
    "b: &b [*a, *a]\n" +
    "c: &c [*b, *b]\n" +
    "d: &d [*c, *c]\n" +
    "e: &e [*d, *d]\n" +
    "f: &f [*e, *e]\n" +
    "g: [*f, *f]\n"
  // Within the preset's budget this is merely large, and it loads.
  assert_eq(loads(bomb[:]) is Object(_), true)
  // With a small budget it is refused rather than expanded.
  let mut out = false
  try {
    let _ = loads(bomb[:], flavor=Flavor::new(budget=64))
  } catch {
    Exceeded(..) => out = true
    _ => ()
  }
  assert_eq(out, true)
}

///|
test "tags say what a scalar is, and an unknown one is refused" {
  assert_eq(j("a: !!str 1\n"), "{\"a\":\"1\"}")
  assert_eq(j("a: !!int 1\n"), "{\"a\":1}")
  assert_eq(j("a: !!bool yes\n"), "{\"a\":true}")
  assert_eq(j("a: !!null ~\n"), "{\"a\":null}")
  // `yes` is a boolean only under a tag: bare, YAML 1.2's core schema says string.
  assert_eq(j("a: yes\n"), "{\"a\":\"yes\"}")
  // A verbatim tag names the same thing the shorthand does.
  assert_eq(j("a: !<tag:yaml.org,2002:str> 1\n"), "{\"a\":\"1\"}")
  // An unknown tag is a document asking for something it did not get.
  assert_eq(refused("a: !!wat 1\n"), true)
}

///|
test "a %TAG directive redefines a handle for its document" {
  assert_eq(j("%TAG !! tag:yaml.org,2002:\n---\na: !!str 1\n"), "{\"a\":\"1\"}")
  assert_eq(refused("%NOPE x\n---\na: 1\n"), true)
}

///|
test "a stream is documents, and one document is not a stream" {
  assert_eq(loads_all("a: 1\n---\nb: 2\n"[:]).length(), 2)
  assert_eq(loads_all("---\na: 1\n...\n---\nb: 2\n...\n"[:]).length(), 2)
  // `loads` wants one document and says so when it is given two.
  let mut out = false
  try {
    let _ = loads("a: 1\n---\nb: 2\n"[:])
  } catch {
    Trailing(_) => out = true
    _ => ()
  }
  assert_eq(out, true)
  // A stream with nothing in it has no documents, which is not one empty document.
  assert_eq(loads_all(""[:]).length(), 0)
  assert_eq(loads_all("# only a comment\n"[:]).length(), 0)
}

///|
test "a repeated key is the caller's decision" {
  assert_eq(j("a: 1\na: 2\n"), "{\"a\":2}")
  assert_eq(
    loads("a: 1\na: 2\n"[:], flavor=Flavor::new(duplicates=First)).stringify(),
    "{\"a\":1}",
  )
  let mut out = false
  try {
    let _ = loads("a: 1\na: 2\n"[:], flavor=Flavor::new(duplicates=Reject))
  } catch {
    Repeated(_) => out = true
    _ => ()
  }
  assert_eq(out, true)
}

///|
test "nesting past the limit is refused rather than run into the ground" {
  let deep = StringBuilder()
  for i = 0; i < 40; i = i + 1 {
    deep.write_string("[")
  }
  for i = 0; i < 40; i = i + 1 {
    deep.write_string("]")
  }
  let src = deep.to_string()
  assert_eq(loads(src[:]) is Array(_), true)
  let mut out = false
  try {
    let _ = loads(src[:], flavor=Flavor::new(depth=8))
  } catch {
    TooDeep(_) => out = true
    _ => ()
  }
  assert_eq(out, true)
}

///|
test "a refusal says which line" {
  let said = try {
    let _ = loads("a: 1\nb: [1, 2\n"[:])
    ""
  } catch {
    e => e.to_string()
  }
  // The `[` that was never closed is on the second line.
  assert_eq(said.contains("2:"), true)
  assert_eq(said.contains("ends mid-document"), true)
}

///|
test "comments and blank lines carry no structure" {
  assert_eq(
    j("# head\n\na: 1   # trailing\n\n# between\nb: 2\n"),
    "{\"a\":1,\"b\":2}",
  )
  assert_eq(j("a:\n  # only a comment\n  b: 1\n"), "{\"a\":{\"b\":1}}")
}

///|
test "UTF-8, with or without the mark an editor writes" {
  assert_eq(load(b"a: \xe4\xb8\xad\n"[:]).stringify(), "{\"a\":\"\u{4e2d}\"}")
  assert_eq(load(b"\xef\xbb\xbfa: 1\n"[:]).stringify(), "{\"a\":1}")
  let mut out = false
  try {
    let _ = load(b"a: \xff\xfe\n"[:])
  } catch {
    BadUtf8(_) => out = true
    _ => ()
  }
  assert_eq(out, true)
}

///|
/// Whether a document is refused, for the cases where which refusal it is does not
/// matter — only that the reader did not guess.
fn refused(src : String) -> Bool {
  try {
    let _ = loads(src[:])
    false
  } catch {
    _ => true
  }
}

///|
test "every refusal says where, without the caller matching all of them" {
  let cases = [
    "a: [1, 2", "a: !!wat 1", "a: *nope", "a: {x: 1", "%NOPE 1\n---\na: 1",
  ]
  for src in cases {
    let at = try {
      let _ = loads(src[:])
      { at: -1, line: -1, column: -1, }
    } catch {
      e => e.at()
    }
    // A position a person can act on: a real line, a real column.
    assert_eq(at.line >= 1, true)
    assert_eq(at.column >= 1, true)
  }
}
