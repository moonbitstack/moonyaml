// The YAML Test Suite run against this package: YAML 1.2.2's core schema.
//
// The suite is the shared measure — https://github.com/yaml/yaml-test-suite —
// and every case in it is either read and compared with the JSON the suite
// says it denotes, or refused where the suite says it must be. A case this
// reader answers differently is listed in `diverged` by its id with its reason;
// the test fails on any divergence that is not on that list, and on a listed one
// that starts passing, so the list cannot rot.

///|
/// The cases this build answers differently, each with the reason it does.
pub fn divergences() -> Array[(String, String)] {
  let wrong : Array[(String, String)] = []
  let mut passed = 0
  let mut skipped = 0
  for c in @data.cases {
    let got = attempt(c.src)
    if c.fail {
      match got {
        None => passed += 1
        Some(_) =>
          wrong.push((c.id, "read a document the suite says must be refused"))
      }
    } else if !c.comparable {
      // The suite gives no JSON for it — a complex key, a duplicate key — which
      // is a value this tree cannot hold.
      skipped += 1
    } else {
      match got {
        None => wrong.push((c.id, "refused"))
        Some(docs) =>
          match check(docs, c.docs) {
            None => passed += 1
            Some(why) => wrong.push((c.id, why))
          }
      }
    }
  }
  println(
    "suite(1.2.2 core): \{passed} of \{@data.cases.length()} passed, \{wrong.length()} diverged, \{skipped} not comparable",
  )
  wrong
}

///|
test "the suite: YAML 1.2.2 core schema" {
  let wrong = divergences()
  for (id, why) in wrong {
    println("  \{id}: \{why}  (\{case_name(id)})")
  }
  let seen = wrong.map(fn(pair) { pair.0 })
  seen.sort()
  let known = diverged.map(fn(pair) { pair.0 })
  known.sort()
  assert_eq(seen, known)
}
