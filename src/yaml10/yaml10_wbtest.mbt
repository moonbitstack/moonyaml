// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
fn j(src : String) -> String raise @moonyaml.Refused {
  loads(src[:]).stringify()
}

///|
test "1.0 reads the single letters as booleans, which 1.1 dropped" {
  assert_eq(j("a: y\nb: n\n"), "{\"a\":true,\"b\":false}")
  assert_eq(j("a: Y\nb: N\n"), "{\"a\":true,\"b\":false}")
  // 1.1 and 1.2 read them as the letters they are; `tests/versions` holds that
  // comparison, because a package cannot import its own siblings' tests otherwise.
  assert_eq(@moonyaml.loads("a: y\n"[:]).stringify(), "{\"a\":\"y\"}")
  // Everything 1.1 has, 1.0 has too.
  assert_eq(j("a: yes\nb: 014\nc: 1:30\n"), "{\"a\":true,\"b\":12,\"c\":90}")
}
