// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
fn j(src : String) -> String raise @moonyaml.Refused {
  loads(src[:]).stringify()
}

///|
test "1.1 reads the words 1.2 made strings as booleans" {
  assert_eq(
    j("a: yes\nb: no\nc: on\nd: off\n"),
    "{\"a\":true,\"b\":false,\"c\":true,\"d\":false}",
  )
  assert_eq(j("a: Yes\nb: NO\n"), "{\"a\":true,\"b\":false}")
  // The words 1.2 reads the other way round are still the words they are.
  assert_eq(j("a: true\n"), "{\"a\":true}")
  assert_eq(j("a: y\n"), "{\"a\":\"y\"}")
}

///|
test "1.1's numbers: octal, binary, underscores and base sixty" {
  assert_eq(j("a: 014\n"), "{\"a\":12}")
  assert_eq(j("a: 0b1010\n"), "{\"a\":10}")
  assert_eq(j("a: 1_000\n"), "{\"a\":1000}")
  assert_eq(j("a: 1:30\n"), "{\"a\":90}")
  assert_eq(j("a: 1:30:30\n"), "{\"a\":5430}")
  // A decimal with a leading zero is octal in 1.1 and a number in 1.2, which is
  // exactly the difference 1.2 changed.
  assert_eq(@moonyaml.loads("a: 014\n"[:]).stringify(), "{\"a\":14}")
}

///|
test "the merge key folds a mapping into the one that names it" {
  assert_eq(
    j("base: &b {x: 1}\nderived:\n  <<: *b\n  y: 2\n"),
    "{\"base\":{\"x\":1},\"derived\":{\"x\":1,\"y\":2}}",
  )
  // An explicit key wins over the merge that names it.
  assert_eq(
    j("base: &b {x: 1}\nderived:\n  <<: *b\n  x: 9\n"),
    "{\"base\":{\"x\":1},\"derived\":{\"x\":9}}",
  )
}

///|
test "a string 1.1 would read back as a boolean is quoted when written" {
  let doc = Json::object(
    Map([("a", Json::string("no")), ("b", Json::string("014"))]),
  )
  assert_eq(dumps(doc), "a: \"no\"\nb: \"014\"\n")
  // And what is written reads back as what was written.
  assert_eq(loads(dumps(doc)[:]).stringify(), doc.stringify())
}
