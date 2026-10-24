// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Read a stream, or nothing where it is refused.
pub fn attempt(src : String) -> Array[Json]? {
  Some(@moonyaml.loads_all(src[:])) catch {
    _ => None
  }
}

///|
/// Whether the documents read are the ones the suite expected, and what went
/// wrong where they are not.
pub fn check(got : Array[Json], want : Array[String]) -> String? {
  if got.length() != want.length() {
    return Some("\{got.length()} documents, expected \{want.length()}")
  }
  for i in 0..<got.length() {
    match @data.expected(want[i]) {
      None => return Some("the suite's expected JSON does not parse")
      Some(w) =>
        if !@data.same(got[i], w) {
          return Some("\{got[i].stringify()} is not \{w.stringify()}")
        }
    }
  }
  None
}

///|
/// The cases this reader is known to answer differently, each with the reason it
/// does. Kept in step with the run: a new entry here is a decision, and the test
/// fails when the run disagrees with it in either direction.
///
/// Every entry is a place where the suite's reading of §7, §8 or §9 is finer than
/// this reader's. The README lists them by category, and the number that matters —
/// how many cases are read as the suite says — is printed by the test.
pub let diverged : Array[(String, String)] = [
  ("Spec Example 7.20. Single Pair Explicit Entry", "refused"),
  ("Tabs in various contexts", "read a document the suite says must be refused"),
  (
    "Tabs that look like indentation", "read a document the suite says must be refused",
  ),
  ("Whitespace around colon in mappings", "refused"),
]
