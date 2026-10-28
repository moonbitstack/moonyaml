// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// The YAML Test Suite, run against every version this library implements.
//
// The suite is written for YAML 1.2, so running it against 1.1 and 1.0 answers a
// different question: not "is this right?" but "where does this version differ,
// and is that where the version says it should?". The counts are pinned in the
// harness that asserts them, so a version that starts reading something new, or
// stops, fails the run rather than quietly moving a number.

///|
/// What one version made of the suite, read beside YAML 1.2.2.
///
/// Every version here shares one scanner, so a difference is a difference of
/// meaning, never of grammar: `stricter` and `looser` are the columns that would
/// show a grammar change, and they are zero for every version that is YAML.
pub(all) struct Score {
  /// Read by both, as the same value.
  same : Int32
  /// Read by both, as different values — `yes` is a boolean in 1.1 and a string
  /// in 1.2, and this is where that shows.
  differs : Int32
  /// Refused by both.
  refused : Int32
  /// Read as 1.2 and refused here: a grammar this version does not have.
  stricter : Int32
  /// Refused as 1.2 and read here.
  looser : Int32
}

///|
/// The same, with the cases behind each column listed by id.
pub(all) struct Report {
  score : Score
  differs : Array[String]
  stricter : Array[String]
  looser : Array[String]
}

///|
/// Read a stream, or nothing where it is refused.
pub fn probe(
  read : (StringView) -> Array[Json] raise @moonyaml.Refused,
  src : String,
) -> Array[Json]? {
  Some(read(src[:])) catch {
    _ => None
  }
}

///|
/// One version's run over the suite, measured against YAML 1.2.2.
pub fn compare(version : Version) -> Report {
  let mut same = 0
  let mut differs = 0
  let mut refused = 0
  let mut stricter = 0
  let mut looser = 0
  let differs_list : Array[String] = []
  let stricter_list : Array[String] = []
  let looser_list : Array[String] = []
  for c in @data.cases {
    let core = probe(src => @moonyaml.loads_all(src), c.src)
    let mine = probe(version.read_all, c.src)
    match (core, mine) {
      (None, None) => refused = refused + 1
      (None, Some(_)) => {
        looser = looser + 1
        looser_list.push("\{c.id} (\{c.name})")
      }
      (Some(_), None) => {
        stricter = stricter + 1
        stricter_list.push("\{c.id} (\{c.name})")
      }
      (Some(a), Some(b)) =>
        if same_docs(a, b) {
          same = same + 1
        } else {
          differs = differs + 1
          differs_list.push("\{c.id}: \{short(show_docs(b))} (\{c.name})")
        }
    }
  }
  {
    score: { same, differs, refused, stricter, looser, },
    differs: differs_list,
    stricter: stricter_list,
    looser: looser_list,
  }
}

///|
/// Whether two runs read the same documents.
fn same_docs(a : Array[Json], b : Array[Json]) -> Bool {
  if a.length() != b.length() {
    return false
  }
  for i in 0..<a.length() {
    if !@data.same(a[i], b[i]) {
      return false
    }
  }
  true
}

///|
fn show_docs(docs : Array[Json]) -> String {
  let parts : Array[String] = []
  for doc in docs {
    parts.push(doc.stringify())
  }
  parts.join(" ")
}

///|
/// `text`, cut to something a report line can hold.
fn short(text : String) -> String {
  if text.length() <= 60 {
    text
  } else {
    text[:57].to_owned() + "..."
  }
}

///|
/// One line of the table the README carries.
pub fn row(name : String, report : Report) -> String {
  let s = report.score
  "\{name}: \{s.same} the same as 1.2.2, \{s.differs} read differently, \{s.refused} refused by both, \{s.stricter} refused only here, \{s.looser} read only here"
}
