// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// One YAML version, as something a program can hold a list of.
///
/// A version in this library is a schema — a resolver and a set of behaviour
/// flags — so a list of versions is a list of schemas, and a corpus can be swept
/// with one loop instead of one branch per caller. The test suite harness and the
/// examples both use this; it is public because a caller who has to read a
/// directory of files written over twenty years wants the same list.
pub struct Version {
  /// The name to print in a report, e.g. `1.2.2`.
  name : String
  /// Where the definition lives.
  spec : String
  /// One document.
  read : (StringView) -> Json raise @moonyaml.Refused
  /// Every document in a stream.
  read_all : (StringView) -> Array[Json] raise @moonyaml.Refused
  /// A value, written the way this version reads it back.
  write : (Json) -> String
}

///|
/// The four versions this library implements, plus the reader that picks one
/// from the document's own `%YAML` directive.
pub let versions : Array[Version] = [
  {
    name: "1.2.2",
    spec: "https://yaml.org/spec/1.2.2/",
    read: src => @moonyaml.loads(src),
    read_all: src => @moonyaml.loads_all(src),
    write: value => @moonyaml.dumps(value),
  },
  {
    name: "1.1",
    spec: "https://yaml.org/spec/1.1/",
    read: src => @yaml11.loads(src),
    read_all: src => @yaml11.loads_all(src),
    write: value => @yaml11.dumps(value),
  },
  {
    name: "1.0",
    spec: "https://yaml.org/spec/1.0/",
    read: src => @yaml10.loads(src),
    read_all: src => @yaml10.loads_all(src),
    write: value => @yaml10.dumps(value),
  },
  {
    name: "strict",
    spec: "https://hitchdev.com/strictyaml/",
    read: src => @strict.loads(src),
    read_all: src => @strict.loads_all(src),
    write: value => @strict.dumps(value),
  },
  {
    name: "any",
    spec: "%YAML directive",
    read: src => @any.loads(src),
    read_all: src => @any.loads_all(src),
    // `any` has no writer of its own: what it would write depends on which
    // version it would read it back with, which is not a property of a value.
    write: value => @moonyaml.dumps(value),
  },
]

///|
/// The version with this name, if there is one.
pub fn find(name : String) -> Version? {
  for version in versions {
    if version.name == name {
      return Some(version)
    }
  }
  None
}

///|
/// Read `src` as every version, in the order above, keeping the ones that read
/// it. A document that is legal in one version and not in another says which
/// version it was written for, and this is how a caller finds out which.
pub fn readings(src : StringView) -> Array[(String, Json)] {
  let out = []
  for version in versions {
    if version.name != "any" {
      out.push((version.name, (version.read)(src))) catch {
        _ => ()
      }
    }
  }
  out
}
