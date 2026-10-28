// The writer against the suite: every case read, written back, and read again.
//
// The suite records, for most cases, the YAML a writer would most ordinarily
// produce (`dump`) and for a few the exact text an emitter should produce
// (`emit`). Neither can be a byte comparison here: how wide a line is, where a
// collection goes on several lines and whether a string ends up quoted are the
// writer's decisions, and two writers that disagree about them can both be right.
// What cannot differ is the document: so the text this writer produces is read
// back, and its events have to be the ones the suite recorded for the source.
//
// That is a stronger claim than it looks. It is the round trip through text, with
// the styles — plain against quoted, flow against block, which chomping indicator
// a block scalar carried — carried through it, and it covers the cases with no
// JSON as well as the ones with.

///|
/// Every document of the stream as text, each with the marker it needs: its own
/// `---` if it had one, and otherwise one only where the document before did not
/// close itself with `...` (§9.1.1).
fn write_stream(docs : Array[@moonyaml.Node]) -> String {
  let out = StringBuilder()
  for i = 0; i < docs.length(); i = i + 1 {
    if i > 0 && !docs[i].explicit && !docs[i - 1].closed {
      out.write_string("---\n")
    }
    out.write_string(@moonyaml.emit(docs[i]))
  }
  out.to_string()
}

///|
/// The cases whose written form does not read back as the document it came from.
fn write_divergences() -> Array[(String, String)] {
  let wrong : Array[(String, String)] = []
  let mut passed = 0
  for c in @data.cases {
    if c.fail || c.tree.length() == 0 {
      continue
    }
    let docs = @moonyaml.parse_all(c.src) catch {
      _ => {
        wrong.push((c.id, "refused"))
        continue
      }
    }
    let text = write_stream(docs)
    let again = @moonyaml.parse_all(text) catch {
      _ => {
        wrong.push((c.id, "the written text is not a document"))
        continue
      }
    }
    match @data.same_events(@moonyaml.events_all(again), c.tree) {
      None => passed += 1
      Some(why) => wrong.push((c.id, why))
    }
  }
  println(
    "suite(write): \{passed} of \{passed + wrong.length()} documents survived being written and read again",
  )
  wrong
}

///|
test "the suite: what the writer writes reads back as what it read" {
  let wrong = write_divergences()
  for (id, why) in wrong {
    println("  \{id}: \{why}  (\{case_name(id)})")
  }
  assert_eq(wrong.length(), 0)
}
