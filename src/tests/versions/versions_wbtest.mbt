// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The same source read as each version, as compact JSON, so a difference between
/// two versions is one line of a test rather than a paragraph of prose.
fn j12(src : String) -> String raise @moonyaml.Refused {
  @moonyaml.loads(src[:]).stringify()
}

///|
fn j11(src : String) -> String raise @moonyaml.Refused {
  @yaml11.loads(src[:]).stringify()
}

///|
fn j10(src : String) -> String raise @moonyaml.Refused {
  @yaml10.loads(src[:]).stringify()
}

///|
fn jany(src : String) -> String raise @moonyaml.Refused {
  @any.loads(src[:]).stringify()
}

///|
fn jstrict(src : String) -> String raise @moonyaml.Refused {
  @strict.loads(src[:]).stringify()
}

///|
test "the words for true and false narrowed at 1.2" {
  // 1.1 has the long words; 1.2 dropped them to `true`/`false`, which is the one
  // change that has bitten more configuration files than any other.
  assert_eq(
    j11("a: yes\nb: no\nc: on\nd: off\n"),
    "{\"a\":true,\"b\":false,\"c\":true,\"d\":false}",
  )
  assert_eq(
    j12("a: yes\nb: no\nc: on\nd: off\n"),
    "{\"a\":\"yes\",\"b\":\"no\",\"c\":\"on\",\"d\":\"off\"}",
  )
  // Capitalisation never mattered (§10.3.2).
  assert_eq(j11("a: YES\nb: Off\n"), "{\"a\":true,\"b\":false}")
  assert_eq(j12("a: YES\nb: Off\n"), "{\"a\":\"YES\",\"b\":\"Off\"}")
}

///|
test "the single letters are booleans only in 1.0" {
  assert_eq(j10("a: y\nb: N\n"), "{\"a\":true,\"b\":false}")
  // 1.1 removed them, and a file that relied on them became a file of strings.
  assert_eq(j11("a: y\nb: N\n"), "{\"a\":\"y\",\"b\":\"N\"}")
  assert_eq(j12("a: y\nb: N\n"), "{\"a\":\"y\",\"b\":\"N\"}")
}

///|
test "an integer with a leading zero is octal in 1.1 and decimal in 1.2" {
  assert_eq(j10("a: 014\n"), "{\"a\":12}")
  assert_eq(j11("a: 014\n"), "{\"a\":12}")
  // 1.2 spells octal `0o14` and reads `014` as ten plus four.
  assert_eq(j12("a: 014\nb: 0o14\n"), "{\"a\":14,\"b\":12}")
  // Which is the same number, so a writer for 1.1 has to be careful.
  assert_eq(j12("a: 0o14\n"), "{\"a\":12}")
  // 1.1 never had the `0o` spelling, so there it is the string it looks like —
  // which is what PyYAML makes of it too.
  assert_eq(j11("a: 0o14\n"), "{\"a\":\"0o14\"}")
}

///|
test "base sixty, which 1.2 does not have" {
  assert_eq(j11("a: 1:30\nb: 1:30:30\n"), "{\"a\":90,\"b\":5430}")
  assert_eq(j12("a: 1:30\n"), "{\"a\":\"1:30\"}")
  // 1.0 has it too — it is where 1.1 inherited it from.
  assert_eq(j10("a: 1:30\n"), "{\"a\":90}")
}

///|
test "the merge key is 1.1's, and 1.2 reads `<<` as the key it looks like" {
  let doc = "base: &b\n  x: 1\n  y: 2\nchild:\n  <<: *b\n  y: 3\n"
  assert_eq(
    j11(doc),
    "{\"base\":{\"x\":1,\"y\":2},\"child\":{\"x\":1,\"y\":3}}",
  )
  assert_eq(
    j12(doc),
    "{\"base\":{\"x\":1,\"y\":2},\"child\":{\"<<\":{\"x\":1,\"y\":2},\"y\":3}}",
  )
}

///|
test "a directive picks the version, and nothing else means 1.2" {
  assert_eq(
    jany("%YAML 1.1\n---\na: yes\nb: 014\nc: 1:30\n"),
    "{\"a\":true,\"b\":12,\"c\":90}",
  )
  assert_eq(jany("%YAML 1.0\n---\na: y\n"), "{\"a\":true}")
  assert_eq(jany("%YAML 1.2\n---\na: yes\n"), "{\"a\":\"yes\"}")
  assert_eq(jany("a: yes\n"), "{\"a\":\"yes\"}")
  // The same file read as 1.1 without the directive would lose the `yes`.
  assert_eq(j11("a: yes\n"), "{\"a\":true}")
}

///|
test "StrictYAML keeps every scalar as the text it was written as" {
  assert_eq(
    jstrict("port: 8080\nenabled: yes\n"),
    "{\"port\":\"8080\",\"enabled\":\"yes\"}",
  )
  assert_eq(
    j12("port: 8080\nenabled: yes\n"),
    "{\"port\":8080,\"enabled\":\"yes\"}",
  )
}

///|
test "what one version writes, the same version reads back" {
  // `014` is the case that makes this a test rather than a truism: a naive writer
  // would emit the digits it was handed, and 1.1 would read them as eight.
  let value = @moonyaml.loads("a: 12\n"[:])
  assert_eq(j12(@moonyaml.dumps(value)), "{\"a\":12}")
  assert_eq(j11(@yaml11.dumps(value)), "{\"a\":12}")
  // A string that 1.1 would take for a boolean comes back quoted.
  let words = @moonyaml.loads("a: yes\n"[:])
  assert_eq(j11(@yaml11.dumps(words)), "{\"a\":\"yes\"}")
  assert_eq(j12(@moonyaml.dumps(words)), "{\"a\":\"yes\"}")
  // And the letters, which only 1.0 misreads.
  let letters = @moonyaml.loads("a: y\n"[:])
  assert_eq(j10(@yaml10.dumps(letters)), "{\"a\":\"y\"}")
  assert_eq(j11(@yaml11.dumps(letters)), "{\"a\":\"y\"}")
}
