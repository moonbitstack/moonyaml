// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// The corpus, and which of its cases belong to which version.
//
// One corpus serves both lanes of the exchange. A value whose two readings
// differ between the versions — the string `1_000` is a thousand to a 1.1
// resolver and a string to a 1.2 one — is exchanged on the lane that agrees
// with it, so a case is skipped rather than reported as a disagreement that is
// really a difference between two schemas.

///|
/// One value both implementations have to read the same way, and the id it is
/// logged under.
struct Case {
  /// The name the case is reported under, and the stem of its file.
  id : String
  /// The value, as the corpus writes it in JSON.
  value : Json
  /// The versions the case is exchanged under. Empty means every one.
  lanes : Array[String]
}

///|
fn Case::in_lane(self : Case, lane : String) -> Bool {
  self.lanes.length() == 0 || self.lanes.contains(lane)
}

///|
/// The cases of `path` that `lane` covers, in the order the corpus lists them.
fn cases_for(path : String, lane : String) -> Array[Case] {
  let text = read_text(path)
  let root = parse_json(text, path)
  let items = match root {
    Array(items) => items
    _ => {
      println("interop: \{path} is not a JSON array of cases")
      @env.exit(2)
    }
  }
  let cases : Array[Case] = []
  for i = 0; i < items.length(); i = i + 1 {
    let item = items[i]
    let fields = match item {
      Object(fields) => fields
      _ => {
        println("interop: case \{i} of \{path} is not an object")
        @env.exit(2)
      }
    }
    let id = match fields.get("id") {
      Some(String(id)) => id
      _ => {
        println("interop: case \{i} of \{path} has no id")
        @env.exit(2)
      }
    }
    let value = match fields.get("value") {
      Some(value) => value
      None => {
        println("interop: case `\{id}` of \{path} has no value")
        @env.exit(2)
      }
    }
    let lanes : Array[String] = match fields.get("lanes") {
      None => []
      Some(Array(names)) =>
        names.map(fn(name : Json) -> String {
          match name {
            String(name) => name
            _ => {
              println("interop: case `\{id}` names a lane that is not a string")
              @env.exit(2)
            }
          }
        })
      Some(_) => {
        println("interop: case `\{id}` gives lanes that are not an array")
        @env.exit(2)
      }
    }
    let case_ = { id, value, lanes, }
    if case_.in_lane(lane) {
      cases.push(case_)
    }
  }
  cases
}
