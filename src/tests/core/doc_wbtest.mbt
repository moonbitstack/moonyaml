// The document model against the value model, on the suite.
//
// A document read as a document has to carry every value the same document read
// as a value carries — that is the whole claim of `doc.mbt` — so every suite case
// this reader reads is read both ways and the two are compared. A round trip
// alone would not catch a document that is quietly truncated on the way in: it
// would truncate it the same way twice.
//
// The cases where the two readings differ anyway are listed with the reason, so
// the number in the README is checked by this test rather than claimed by it.

///|
/// The cases the two models read differently, and why.
///
/// Every one of them is a place where the value reader understands a construct
/// that the document reader does not yet spell out as a tree — an implicit key in
/// a flow collection, an alias where a key belongs — so the document reader
/// refuses a document rather than guessing at it.
pub let known : Array[(String, String)] = [
  ("26DV", "refused: a key and its `:` split across lines"),
  ("7BUB", "a comment after an alias ends the sequence"),
  ("87E4", "refused: a single-quoted implicit key"),
  ("8UDB", "refused: a flow entry with no value"),
  ("CN3R", "refused: an anchor in a flow sequence"),
  ("CT4Q", "refused: an explicit pair in flow style"),
  ("DBG4", "a plain scalar that starts with a tab"),
  ("E76Z", "refused: an alias as an implicit key"),
  ("L9U5", "refused: a plain implicit key"),
  ("LQZ7", "refused: a double-quoted implicit key"),
  ("QF4Y", "refused: a single pair in flow style"),
  ("UT92", "an explicit document that holds nothing"),
  ("W4TN", "refused: a directive before a document"),
  ("WZ62", "refused: a node with no content"),
]

///|
/// Whether the two readings differ only in whether an empty stream is a document:
/// a stream of comments is nothing to a value reader, and one empty document to a
/// document reader, which is where the comments live.
fn only_comments(values : Array[Json], docs : Array[@moonyaml.Node]) -> Bool {
  if docs.length() == 1 && values.length() == 0 {
    return docs[0].before.length() > 0 || docs[0].kind is Null
  }
  false
}

///|
test "the suite: the document model agrees with the value model" {
  let wrong : Array[(String, String)] = []
  let mut compared = 0
  for c in @data.cases {
    match attempt(c.src) {
      None => ()
      Some(values) => {
        let docs = @moonyaml.parse_all(c.src) catch {
          _ => {
            wrong.push((c.id, "refused"))
            continue
          }
        }
        if docs.length() != values.length() {
          if only_comments(values, docs) {
            compared = compared + 1
          } else {
            wrong.push(
              (
                c.id,
                "\{docs.length()} documents, the value model read \{values.length()}",
              ),
            )
          }
          continue
        }
        let mut ok = true
        for i in 0..<docs.length() {
          if !@data.same(docs[i].to_json(), values[i]) {
            ok = false
          }
        }
        if ok {
          compared = compared + 1
        } else {
          let parts : Array[String] = []
          for doc in docs {
            parts.push(doc.to_json().stringify())
          }
          wrong.push((c.id, parts.join(" ")))
        }
      }
    }
  }
  println(
    "doc/suite: \{compared} of \{compared + wrong.length()} documents read both ways agree",
  )
  for (id, why) in wrong {
    println("  \{id}: \{why}  (\{case_name(id)})")
  }
  let seen = wrong.map(fn(pair) { pair.0 })
  seen.sort()
  let expected = known.map(fn(pair) { pair.0 })
  expected.sort()
  assert_eq(seen, expected)
}
