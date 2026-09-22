// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The YAML a compact JSON document is written as.
fn y(src : String) -> String raise Refused {
  dumps(loads(src[:]))
}

///|
/// One key holding `s`, written out.
fn one(s : String) -> String {
  dumps({ "a": Json::string(s) })
}

///|
test "a mapping and a sequence are written in block style" {
  assert_eq(y("{a: 1, b: two}"), "a: 1\nb: two\n")
  assert_eq(y("[1, 2]"), "- 1\n- 2\n")
  assert_eq(y("{a: {b: {c: 1}}}"), "a:\n  b:\n    c: 1\n")
  assert_eq(y("{a: [1, 2]}"), "a:\n  - 1\n  - 2\n")
  assert_eq(y("[{a: 1, b: 2}]"), "- a: 1\n  b: 2\n")
}

///|
test "a scalar is quoted exactly when it would read back as something else" {
  // A word is a word.
  assert_eq(y("{a: hello}"), "a: hello\n")
  // But one that would resolve to a number, a boolean or null is quoted.
  assert_eq(one("1"), "a: \"1\"\n")
  assert_eq(one("true"), "a: \"true\"\n")
  assert_eq(one("null"), "a: \"null\"\n")
  assert_eq(one(""), "a: \"\"\n")
  // As is one carrying something YAML gives a meaning to.
  assert_eq(one("x: y"), "a: \"x: y\"\n")
  assert_eq(one("- x"), "a: \"- x\"\n")
  assert_eq(one(" x"), "a: \" x\"\n")
}

///|
test "a number is written as the value it is, not as a double" {
  assert_eq(y("{a: 8080}"), "a: 8080\n")
  assert_eq(y("{a: 1.5}"), "a: 1.5\n")
  assert_eq(y("{a: -2}"), "a: -2\n")
  assert_eq(y("{a: 0}"), "a: 0\n")
}

///|
test "a multi-line string is written as the block scalar a person would write" {
  assert_eq(one("one\ntwo\n"), "a: |\n  one\n  two\n")
  // A string with no break in it stays on the key's line.
  assert_eq(one("one"), "a: one\n")
  // The chomping indicator carries the trailing breaks exactly.
  assert_eq(one("one\ntwo"), "a: |-\n  one\n  two\n")
  assert_eq(one("one\n\n"), "a: |+\n  one\n\n")
  // A blank line inside is a blank line, with no trailing spaces on it.
  assert_eq(one("one\n\ntwo\n"), "a: |\n  one\n\n  two\n")
  // Nested, and under a sequence dash.
  assert_eq(
    dumps({ "a": { "b": Json::string("x\ny\n") } }),
    "a:\n  b: |\n    x\n    y\n",
  )
  assert_eq(dumps([Json::string("x\ny\n")]), "- |\n  x\n  y\n")
  // A string a literal block cannot hold stays quoted: a carriage return, or a
  // line that begins with space, which would need an indentation indicator.
  assert_eq(one("one\r\ntwo"), "a: \"one\\r\\ntwo\"\n")
  assert_eq(one("one\n  two"), "a: \"one\\n  two\"\n")
}

///|
test "every block scalar this writes, it reads back to the same string" {
  let cases = [
    "one\ntwo\n", "one\ntwo", "one\n\n\n", "one\n\ntwo\n", "x\n", "a b\nc d\n", "#!/bin/sh\nset -e\necho hi\n",
  ]
  for s in cases {
    let doc : Json = { "k": Json::string(s) }
    let back = loads(dumps(doc)[:])
    guard back is Object(m) && m.get("k") is Some(String(got)) else {
      fail("a block scalar should read back as a string")
    }
    assert_eq(got, s)
  }
}

///|
test "every document this reads, it writes back to the same value" {
  let cases = [
    "a: 1\nb: [1, 2]\nc: {d: e}\n", "- 1\n- two\n- [3, 4]\n- {five: 5}\n", "a: |\n  one\n  two\n",
    "a: >\n  one\n  two\n", "a: &x {p: 1}\nb: *x\n", "empty: {}\nseq: []\nnothing: ~\n",
    "deep:\n  a:\n    b:\n      - 1\n      - c: 2\n",
  ]
  for src in cases {
    let once = loads(src[:])
    let twice = loads(dumps(once)[:])
    // The second reading of what the first was written as is the first.
    assert_eq(twice.stringify(), once.stringify())
  }
}

///|
test "a stream is written as one, and reads back as one" {
  let docs = loads_all("a: 1\n---\nb: 2\n"[:])
  let text = dumps_all(docs[:])
  // Each document is opened by its own marker, so joining two streams still reads
  // as four documents rather than as a syntax error.
  assert_eq(text, "---\na: 1\n---\nb: 2\n")
  assert_eq(loads_all(text[:]).length(), 2)
  assert_eq(loads_all((text + text)[:]).length(), 4)
  // And the other convention, which PyYAML and Go write, reads the same.
  assert_eq(loads_all("a: 1\n---\nb: 2\n"[:]).length(), 2)
}

///|
test "the indent is a knob, and two spaces is the preset" {
  assert_eq(indent, 2)
  assert_eq(y("{a: {b: 1}}"), dumps(loads("{a: {b: 1}}"[:]), indent=2))
  assert_eq(dumps(loads("{a: {b: 1}}"[:]), indent=4), "a:\n    b: 1\n")
  // And sorting is a knob too, off by default so a document keeps its order.
  assert_eq(dumps(loads("{b: 1, a: 2}"[:])), "b: 1\na: 2\n")
  assert_eq(dumps(loads("{b: 1, a: 2}"[:]), sort=true), "a: 2\nb: 1\n")
}

///|
test "bytes in and bytes out" {
  assert_eq(dump(loads("{a: 1}"[:])), b"a: 1\n")
  assert_eq(load(b"a: 1\n"[:]).stringify(), "{\"a\":1}")
}
