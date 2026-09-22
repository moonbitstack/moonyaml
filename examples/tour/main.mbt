///|
/// Everything moonyaml reads, in one file.
///
///     moon run examples/tour
#coverage.skip
fn main {
  run() catch {
    e => println("refused: \{e}")
  }
}

///|
fn run() -> Unit raise {
  // A configuration file, of the shape one is actually written in: block
  // collections, a literal scalar that keeps its line breaks, and an anchor
  // reused further down.
  let config =
    #|server:
    #|  host: 0.0.0.0
    #|  port: 12000
    #|  motd: |
    #|    welcome
    #|    to the party
    #|limits: &shared {files: 1000, bytes: 1048576}
    #|upload: *shared
    #|tags: [http, native]
    #|
  let tree = @moonyaml.loads(config)
  println("read as JSON:")
  println("  \{tree.stringify()}")
  println("written back:")
  for line in @moonyaml.dumps(tree).split("\n") {
    if line.length() > 0 {
      println("  \{line}")
    }
  }

  // The core schema decides what an unquoted scalar is; quoting it makes it a
  // string whatever it looks like.
  println("resolution:")
  println(
    "  \{@moonyaml.loads("[1, 1.5, 0x1f, true, ~, yes, \"1\"]").stringify()}",
  )

  // A stream is several documents, and each is read in its own right.
  let stream =
    #|---
    #|first: 1
    #|---
    #|second: 2
    #|...
    #|
  let docs = @moonyaml.loads_all(stream)
  println("stream of \{docs.length()} documents:")
  for d in docs {
    println("  \{d.stringify()}")
  }

  // Ambiguity is refused with a position rather than guessed at.
  show_refusal("a: [1, 2")
  show_refusal("a: !!nope 1")
  show_refusal("a: 1\na: 2", flavor=@moonyaml.Flavor::new(duplicates=Reject))

  // And an alias that expands past its budget is refused too, which is what
  // stops a dozen lines from becoming billions of nodes.
  show_refusal(
    "a: &a [x, x]\nb: &b [*a, *a]\nc: &c [*b, *b]\nd: [*c, *c]\n",
    flavor=@moonyaml.Flavor::new(budget=8),
  )
}

///|
/// Read a document that will not load, and print why.
fn show_refusal(
  src : String,
  flavor? : @moonyaml.Flavor = @moonyaml.strict,
) -> Unit {
  let one_line = src.replace_all(old="\n", new=" ⏎ ")
  let said = @moonyaml.loads(src, flavor~).stringify() catch {
    e => e.to_string()
  }
  println("  \{one_line} => \{said}")
}
