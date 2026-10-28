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
/// The name of the suite case with this id, for a line of output a person reads.
pub fn case_name(id : String) -> String {
  for c in @data.cases {
    if c.id == id {
      return c.name
    }
  }
  id
}
