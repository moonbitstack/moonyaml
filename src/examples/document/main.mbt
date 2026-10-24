// A document read as a document: what it says, not only what it means.
//
//     moon run examples/document

///|
#coverage.skip
fn main raise {
  let src =
    #|# The deployment this file describes.
    #|name: web
    #|defaults: &defaults
    #|  replicas: 3
    #|  image: nginx:1.27
    #|front:
    #|  <<: *defaults
    #|  image: nginx:1.27-alpine   # the only difference
    #|ports: [80, 443]
    #|motd: |
    #|  one
    #|  two
    #|

  println("the document:")
  for line in src.split("\n") {
    if line.length() > 0 {
      println("  " + line.to_owned())
    }
  }

  // `parse` keeps the comments, the flow style of `ports`, the anchor on
  // `defaults` and the alias in place of its value — everything `loads` folds
  // into a `Json` tree on the way to being a value.
  let doc = @moonyaml.parse(src)

  println("")
  println("written back: is it the same document?")
  let written = @moonyaml.emit(doc)
  println(if written == src { "  yes, byte for byte" } else { "  no:" })
  if written != src {
    for line in written.split("\n") {
      println("  " + line.to_owned())
    }
  }

  // What it means, for a caller who wants the value: the merge key folded in, the
  // alias resolved, the tags gone.
  println("")
  println("and what it means:")
  println("  " + doc.to_json().stringify())

  // A tree built from a value is a document too, and it writes as one.
  println("")
  println("a document built from a value, with an indent of four:")
  let value = @moonyaml.loads(
    (
      #|a: 1
      #|b:
      #|  - x
      #|  - y: 2
      #|
    ),
  )
  let built = @moonyaml.Node::of_json(value)
  for line in @moonyaml.emit(built, indent=4).split("\n") {
    if line.length() > 0 {
      println("  " + line.to_owned())
    }
  }

  // The writer's other knob: how far a line may run before a collection is written
  // as a block instead.
  println("")
  println("written in flow style, ten deep:")
  let list = @moonyaml.loads(
    (
      #|- 1
      #|- 2
      #|- 3
      #|
    ),
  )
  println(
    "  " +
    @moonyaml.dumps(list, style=@moonyaml.flow).replace_all(old="\n", new=" "),
  )
}
