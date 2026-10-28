// The YAML Test Suite read as a value: YAML 1.2.2's core schema.
//
// The suite is the shared measure — https://github.com/yaml/yaml-test-suite —
// and every case in it is either read and compared with the JSON the suite says
// it denotes, or refused where the suite says it must be. The cases with no JSON
// (a key that is a collection, a key written twice) are not compared here at all:
// a `Json` has string keys and no room for a repeated one, so they are held to the
// suite's event stream instead, in `events_wbtest.mbt`.

///|
/// The cases this build answers differently, each with the reason it does.
fn value_divergences() -> Array[(String, String)] {
  let wrong : Array[(String, String)] = []
  let mut compared = 0
  let mut refused = 0
  let mut by_events = 0
  for c in @data.cases {
    let got = attempt(c.src)
    if c.fail {
      match got {
        None => refused += 1
        Some(_) =>
          wrong.push((c.id, "read a document the suite says must be refused"))
      }
    } else if !c.comparable {
      by_events += 1
    } else {
      match got {
        None => wrong.push((c.id, "refused"))
        Some(docs) =>
          match check(docs, c.docs) {
            None => compared += 1
            Some(why) => wrong.push((c.id, why))
          }
      }
    }
  }
  println(
    "suite(1.2.2 core): \{compared + refused + by_events} of \{@data.cases.length()} — \{compared} read as the suite's JSON, \{refused} refused where it says refuse, \{by_events} with no JSON, held to their events",
  )
  wrong
}

///|
test "the suite: YAML 1.2.2 core schema" {
  let wrong = value_divergences()
  for (id, why) in wrong {
    println("  \{id}: \{why}  (\{case_name(id)})")
  }
  assert_eq(wrong.length(), 0)
}
