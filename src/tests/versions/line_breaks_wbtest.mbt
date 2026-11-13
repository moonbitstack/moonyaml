// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// What a mapping holds under `key`, or nothing where the value is not a mapping or
/// has no such member.
fn under(value : Json, key : String) -> Json? {
  let mut found : Json? = None
  guard value is Object(members) else { return None }
  for k, v in members {
    if k == key {
      found = Some(v)
    }
  }
  found
}

///|
/// The string a mapping holds under `key`.
///
/// A scalar's text is compared as text rather than through its JSON form: NEL, LS
/// and PS are exactly the characters a JSON writer is free to escape or not.
fn string_under(value : Json, key : String) -> String? {
  match under(value, key) {
    Some(String(s)) => Some(s)
    _ => None
  }
}

///|
/// The number a mapping holds under `key`.
fn number_under(value : Json, key : String) -> Double? {
  match under(value, key) {
    Some(Number(n, ..)) => Some(n)
    _ => None
  }
}

///|
/// Every document in the reference vectors — a line ended by NEL, LS or PS in each
/// place one can stand — reads as the value the reference implementation reads it as.
test "the 1.1 line breaks read as the reference reads them" {
  for pair in @data.breaks {
    let (document, want) = pair
    let got = @yaml11.loads(document[:]) catch {
      e => fail("\{e}: \{document}")
    }
    match @data.expected(want) {
      None => fail("the reference's JSON does not parse: \{want}")
      Some(value) =>
        if !@data.same(got, value) {
          fail("\{got.stringify()} is not \{want}")
        }
    }
  }
}

///|
/// 1.0 is 1.1's line breaks and more, so the same documents read the same way.
test "1.0 reads the three characters as breaks too" {
  assert_eq(
    number_under(@yaml10.loads("a: 1\u{85}b: 2\u{85}"[:]), "b"),
    Some(2.0),
  )
  assert_eq(
    string_under(@yaml10.loads("a: |\u{2028}  one\u{2028}"[:]), "a"),
    Some("one\u{2028}"),
  )
}

///|
/// 1.2's line break is a line feed or a carriage return, so the three are ordinary
/// characters: they neither end a line nor split an entry.
test "1.2 keeps the three characters inside the scalar they were written in" {
  assert_eq(
    string_under(@moonyaml.loads("a: 1\u{85}b\n"[:]), "a"),
    Some("1\u{85}b"),
  )
  assert_eq(under(@moonyaml.loads("a: 1\u{85}b\n"[:]), "b"), None)
  assert_eq(
    string_under(@moonyaml.loads("a: x\u{2028}y\n"[:]), "a"),
    Some("x\u{2028}y"),
  )
  // A break is still a break where it is one of the two 1.2 has.
  assert_eq(
    number_under(@moonyaml.loads("a: 1\r\nb: 2\r\n"[:]), "b"),
    Some(2.0),
  )
}

///|
/// The break a scalar is written back with: what a 1.1 reader kept as content is
/// content, and a line feed is a line feed.
test "a value keeps the breaks it was written with" {
  let text = "a: |\u{2028}  one\u{2028}  two\u{2028}"
  assert_eq(@moonyaml.dumps(@yaml11.loads(text[:])), "a: \"one\\Ltwo\\L\"\n")
}

///|
/// A scalar spelled with the three characters is quoted on the way out: a 1.1 reader
/// would fold a bare one into a space and hand back something else.
test "a string with a line break character is not written bare" {
  assert_eq(@moonyaml.dumps(Json::string("a\u{85}b")), "\"a\\Nb\"\n")
  assert_eq(@moonyaml.dumps(Json::string("a\u{2028}b")), "\"a\\Lb\"\n")
}
