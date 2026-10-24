// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
fn j(src : String) -> String raise @moonyaml.Refused {
  loads(src[:]).stringify()
}

///|
fn refused(src : String) -> Bool {
  try {
    let _ = loads(src[:])
    false
  } catch {
    _ => true
  }
}

///|
test "every scalar is text, whatever it spells" {
  assert_eq(j("port: 8080\n"), "{\"port\":\"8080\"}")
  assert_eq(j("enabled: yes\n"), "{\"enabled\":\"yes\"}")
  assert_eq(j("port: '8080'\n"), "{\"port\":\"8080\"}")
  assert_eq(j("a: ~\n"), "{\"a\":\"~\"}")
}

///|
test "what StrictYAML removes is refused, and says so" {
  // A tag asks for a type the reader may not have.
  assert_eq(refused("a: !!int 1\n"), true)
  // An anchor makes one node appear twice.
  assert_eq(refused("a: &x 1\nb: *x\n"), true)
  // Flow style packs structure onto a line.
  assert_eq(refused("a: [1, 2]\n"), true)
  assert_eq(refused("a: {b: 1}\n"), true)
  // A repeated key has no reading a person would have predicted.
  assert_eq(refused("a: 1\na: 2\n"), true)
}

///|
test "a document is a document, and plain block YAML reads as it looks" {
  assert_eq(
    j("a:\n  b: c\n  d:\n    - one\n    - two\n"),
    "{\"a\":{\"b\":\"c\",\"d\":[\"one\",\"two\"]}}",
  )
}
