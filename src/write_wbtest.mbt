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

///|
test "a document that is one scalar is a document" {
  // Nothing owns the scalar, so it cannot lean on a key for its quoting: the
  // same rules have to hold at the left margin.
  assert_eq(dumps(Json::string("hello")), "hello\n")
  assert_eq(dumps(Json::string("true")), "\"true\"\n")
  assert_eq(dumps(Json::string("True")), "\"True\"\n")
  assert_eq(dumps(Json::string("NULL")), "\"NULL\"\n")
  assert_eq(dumps(Json::string("")), "\"\"\n")
  assert_eq(dumps(Json::string("#lead")), "\"#lead\"\n")
  assert_eq(dumps(Json::string("x: y")), "\"x: y\"\n")
  // At the left margin a bare `...` would end the document instead of being one.
  assert_eq(dumps(Json::string("...")), "\"...\"\n")
  assert_eq(loads(dumps(Json::string("..."))[:]).stringify(), "\"...\"")
}

///|
test "a document that is one long scalar folds, and one with a break is a block" {
  let long = "The settings below are read at start-up and never again, which is why they are written on one line."
  assert_eq(
    dumps(Json::string(long)),
    "The settings below are read at start-up and never again, which is why they are\n  written on one line.\n",
  )
  assert_eq(dumps(Json::string("one\ntwo\n")), "|\n  one\n  two\n")
  assert_eq(dumps(Json::string("one\ntwo")), "|-\n  one\n  two\n")
  for s in [long, "one\ntwo\n", "one\ntwo"] {
    assert_eq(
      loads(dumps(Json::string(s))[:]).stringify(),
      Json::string(s).stringify(),
    )
  }
}

///|
test "a character some readers fold into a space is written as an escape" {
  // 1.2 lists these as characters, and a reader with 1.1's scanner folds them
  // into a space; escaped, both read the character that was written.
  assert_eq(dumps(Json::string("a\u{85}b")), "\"a\\Nb\"\n")
  assert_eq(dumps(Json::string("a\u{2028}b")), "\"a\\Lb\"\n")
  assert_eq(dumps(Json::string("a\u{2029}b")), "\"a\\Pb\"\n")
  assert_eq(dumps(Json::string("a\u{9f}b")), "\"a\\x9fb\"\n")
  assert_eq(
    loads(dumps(Json::string("a\u{85}b"))[:]).stringify(),
    Json::string("a\u{85}b").stringify(),
  )
}

///|
test "the writer quotes what the rules it was given would resolve" {
  // A file written for a 1.1 reader: the words and the digits 1.1 gives a type to
  // are quoted, at the left margin and under a key alike.
  assert_eq(dumps(Json::string("yes"), rules=legacy_rules), "\"yes\"\n")
  assert_eq(dumps(Json::string("1_000"), rules=legacy_rules), "\"1_000\"\n")
  assert_eq(dumps(Json::string("1:30"), rules=legacy_rules), "\"1:30\"\n")
  assert_eq(
    dumps(
      { "a": Json::string("yes"), "b": Json::string("014") },
      rules=legacy_rules,
    ),
    "a: \"yes\"\nb: \"014\"\n",
  )
  // The same strings are plain in 1.2, which resolves neither of them — and
  // `014` is fourteen there, so it stays quoted for the other reason.
  assert_eq(dumps(Json::string("yes")), "yes\n")
  assert_eq(dumps({ "b": Json::string("yes") }), "b: yes\n")
  assert_eq(dumps({ "b": Json::string("014") }), "b: \"014\"\n")
}

///|
test "a number wider than a double keeps the digits it was written with" {
  // The tree holds a double, which rounds this one; the text is kept beside it so
  // that writing it back is not where an identifier loses its last digits.
  let n = loads("a: 12345678901234567890\n"[:])
  assert_eq(n.stringify(), "{\"a\":12345678901234567890}")
  assert_eq(dumps(n), "a: 12345678901234567890\n")
  assert_eq(loads("9007199254740993"[:]).stringify(), "9007199254740993")
  assert_eq(dumps(loads("9007199254740993"[:])), "9007199254740993\n")
  // A number a double holds exactly is written as its value, not as its text.
  assert_eq(dumps(loads("a: 8080\n"[:])), "a: 8080\n")
}
