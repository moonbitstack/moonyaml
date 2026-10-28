// The document model against the value model, on the suite.
//
// A document read as a document has to carry every value the same document read
// as a value carries — that is the whole claim of `doc.mbt` — so every suite case
// the value model reads is read both ways and the two are compared. A round trip
// alone would not catch a document that is quietly truncated on the way in: it
// would truncate it the same way twice.
//
// The cases the value model refuses are not compared here: a `Json` has string
// keys, so a mapping keyed by a collection has no value to compare with. Those
// are held to the suite's events instead, in `events_wbtest.mbt`.

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
          wrong.push(
            (
              c.id,
              "\{docs.length()} documents, the value model read \{values.length()}",
            ),
          )
          continue
        }
        let mut ok = true
        for i = 0; i < docs.length(); i = i + 1 {
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
  assert_eq(wrong.length(), 0)
}
