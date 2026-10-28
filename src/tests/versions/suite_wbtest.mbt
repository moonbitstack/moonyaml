// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// The table the README carries, printed by the run and asserted here: a version
// that reads something 1.2.2 does not, or refuses something it does, fails this
// test — the numbers and the prose cannot drift apart.

///|
/// What each version is expected to say beside YAML 1.2.2, its own name taken out
/// of the count: a version never disagrees with itself, so `same` here is the
/// number of cases it reads as 1.2.2 does.
fn expected(name : String) -> (Int32, Int32, Int32, Int32)? {
  match name {
    "1.1" => Some((291, 1, 110, 0))
    "1.0" => Some((290, 2, 110, 0))
    "strict" => Some((154, 25, 110, 113))
    _ => None
  }
}

///|
test "the suite: every version, beside 1.2.2" {
  let reports : Array[(String, Report)] = []
  for version in versions {
    if version.name == "any" {
      continue
    }
    let report = compare(version)
    println(row(version.name, report))
    reports.push((version.name, report))
  }
  // The reader that picks a version from the document's own directive answers
  // exactly as 1.2.2 does on a suite that carries no directive but one.
  let any = compare(find("1.2.2").unwrap())
  let picky = compare(find("any").unwrap())
  assert_eq([picky.score.same, picky.score.differs, picky.score.refused], [
    any.score.same,
    any.score.differs,
    any.score.refused,
  ])
  for version in versions {
    if version.name != "1.1" &&
      version.name != "1.0" &&
      version.name != "strict" {
      continue
    }
    let report = compare(version)
    // A grammar is shared: what 1.2.2 reads, every YAML version reads, and what it
    // refuses, they refuse. Only a schema without flow style, anchors, aliases or
    // tags may refuse more, which is what StrictYAML is.
    assert_eq(report.score.looser, 0)
    if version.name != "strict" {
      assert_eq(report.score.stricter, 0)
    }
    for line in report.stricter {
      if version.name == "strict" {
        continue
      }
      println("  stricter \{line}")
    }
    for line in report.looser {
      println("  looser \{line}")
    }
    match expected(version.name) {
      Some((same, differs, refused, stricter)) =>
        assert_eq(
          [
            report.score.same,
            report.score.differs,
            report.score.refused,
            report.score.stricter,
          ],
          [same, differs, refused, stricter],
        )
      None => ()
    }
  }
}
