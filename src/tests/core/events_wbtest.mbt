// The YAML Test Suite, read as a parse: the events of every case, compared line
// for line with the ones the suite says a parser produces.
//
// A value comparison cannot see the cases that carry no JSON — a key that is a
// collection, a key written twice — and it cannot see the difference between a
// plain scalar and a quoted one, or between a block collection and a flow one.
// The event stream sees all of it, so this is where the document model is held to
// the suite: it has to produce the same parse, event for event, for every case.

///|
/// The cases whose events differ, each with the line where they part.
fn event_divergences() -> Array[(String, String)] {
  let wrong : Array[(String, String)] = []
  let mut passed = 0
  for c in @data.cases {
    if c.fail {
      // A case that must be refused has a tree in the suite, but nothing this
      // reader is allowed to produce: `suite_wbtest.mbt` is where it is checked.
      continue
    }
    if c.tree.length() == 0 {
      // A case the suite records without a parse at all.
      continue
    }
    let docs = @moonyaml.parse_all(c.src) catch {
      _ => {
        wrong.push((c.id, "refused"))
        continue
      }
    }
    match @data.same_events(@moonyaml.events_all(docs), c.tree) {
      None => passed += 1
      Some(why) => wrong.push((c.id, why))
    }
  }
  println(
    "suite(events): \{passed} of \{passed + wrong.length()} parsed as the suite says",
  )
  wrong
}

///|
test "the suite: every case parses to the events it should" {
  let wrong = event_divergences()
  for (id, why) in wrong {
    println("  \{id}: \{why}  (\{case_name(id)})")
  }
  assert_eq(wrong.length(), 0)
}
