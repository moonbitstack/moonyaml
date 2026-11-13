// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Every spelling of a point in time in the reference vectors, and what a 1.1 reader
/// makes of it: the text the reference makes of it, or a refusal where the reference
/// refuses a date that never happened.
test "the timestamp tag makes the point in time the reference makes of it" {
  for pair in @data.timestamps {
    let (text, want) = pair
    let read = Some(@yaml11.loads("t: !!timestamp \{text}\n"[:])) catch {
      _ => None
    }
    match (read, want) {
      (None, None) => ()
      (Some(_), None) => fail("`\{text}` is not a point in time, and was read")
      (None, Some(_)) => fail("`\{text}` is a point in time, and was refused")
      (Some(value), Some(written)) =>
        match string_under(value, "t") {
          Some(read) =>
            if read != written {
              fail("`\{text}` reads as `\{read}` and not `\{written}`")
            }
          None => fail("`\{text}` did not read as a string")
        }
    }
  }
}

///|
/// A timestamp is not guessed at: a scalar that looks like one is the text it is
/// until a tag says otherwise, which is the difference between reading 1.1 and
/// reading a configuration file that happens to hold a date.
test "an untagged date stays the text it is" {
  assert_eq(
    string_under(@yaml11.loads("t: 2001-12-15\n"[:]), "t"),
    Some("2001-12-15"),
  )
  assert_eq(
    string_under(@yaml11.loads("t: 2001-12-14 21:59:43.10 -5\n"[:]), "t"),
    Some("2001-12-14 21:59:43.10 -5"),
  )
}

///|
/// 1.2 has no timestamp type, so the tag names a type this reader has none of and
/// the text is what the scalar would have been without it (§10.4).
test "1.2 has no timestamp type, so the tag leaves the text alone" {
  assert_eq(
    string_under(@moonyaml.loads("t: !!timestamp 2001-12-15\n"[:]), "t"),
    Some("2001-12-15"),
  )
  assert_eq(
    string_under(@moonyaml.loads("t: !!timestamp \"2001-12-15\"\n"[:]), "t"),
    Some("2001-12-15"),
  )
}

///|
/// A date the calendar does not have is refused, and the refusal says which
/// character cannot stand where it was written.
test "a date that never happened is refused where it goes wrong" {
  let said = fn(src : String) -> String {
    try {
      @yaml11.loads(src[:]) |> ignore
      "read"
    } catch {
      e => e.to_string()
    }
  }
  assert_eq(said("t: !!timestamp 2001-02-30\n"), "1:24: unexpected '3'")
  assert_eq(said("t: !!timestamp 2001-13-01\n"), "1:21: unexpected '1'")
  assert_eq(
    said("t: !!timestamp 2001-12-15T25:00:00Z\n"),
    "1:27: unexpected '2'",
  )
  assert_eq(said("t: !!timestamp 20011215\n"), "1:20: unexpected '1'")
}
