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
/// The cases this reader answers differently, each by the suite's own id and with
/// the reason it does. Kept in step with the run: a new entry here is a decision,
/// and the test fails when the run disagrees with it in either direction.
///
/// The id is the file the case came from — `4ABK` — because a name is not unique
/// in the suite: two cases may share one and mean two different documents.
pub let diverged : Array[(String, String)] = [
  ("DK95/2", "read a document the suite says must be refused"),
  ("Y79Y/4", "read a document the suite says must be refused"),
]
