// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
fn j(src : String) -> String raise @moonyaml.Refused {
  loads(src[:]).stringify()
}

///|
test "a document that names a version is read with that version's rules" {
  assert_eq(j("%YAML 1.1\n---\na: yes\nb: 014\n"), "{\"a\":true,\"b\":12}")
  assert_eq(j("%YAML 1.0\n---\na: y\n"), "{\"a\":true}")
  assert_eq(j("%YAML 1.2\n---\na: yes\nb: 014\n"), "{\"a\":\"yes\",\"b\":14}")
}

///|
test "no directive means 1.2, which is what a file without one means now" {
  assert_eq(j("a: yes\n"), "{\"a\":\"yes\"}")
  assert_eq(j("a: 014\n"), "{\"a\":14}")
}

///|
test "a version this library does not have is refused, not guessed at" {
  let mut bad = false
  try {
    let _ = loads("%YAML 2.0\n---\na: 1\n"[:])
  } catch {
    _ => bad = true
  }
  assert_eq(bad, true)
  // The reader itself refuses it too, so `any` is not the only one that would.
  assert_eq(@moonyaml.declared_version("%YAML 1.1\n---\n"[:]), Some((1, 1)))
  assert_eq(@moonyaml.declared_version("a: 1\n"[:]), None)
}
