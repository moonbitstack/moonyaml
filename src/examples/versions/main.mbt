// The same document, read by every version this library implements.
//
//     moon run src/examples/versions

///|
#coverage.skip
fn main {
  // A document written for no version in particular: a configuration file with a
  // word, an octal and a time in it. Which of those are what they look like is
  // the whole of the difference between the versions.
  let src =
    #|enabled: yes
    #|mask: 014
    #|starts: 12:30
    #|when: 2001-12-15 02:59:43
    #|

  println("the document:")
  for line in src.split("\n") {
    if line.length() > 0 {
      println("  " + line.to_owned())
    }
  }
  println("")
  println("read as:")
  each("1.2.2 (core schema)", src, text => @moonyaml.loads(text))
  each("1.1 (legacy types, merge key)", src, text => @yaml11.loads(text))
  each("1.0 (1.0 types)", src, text => @yaml10.loads(text))

  // StrictYAML is not a version of YAML with different scalars: it is a language
  // that keeps the shape of YAML and drops everything that is ambiguous. Every
  // scalar it reads is a string, and flow style, anchors, aliases, tags and a key
  // written twice are refused.
  println("")
  println("and as StrictYAML, where every scalar is a string:")
  each("strict", src, text => @strict.loads(text))
  each("strict, on flow style", "a: [1, 2]", text => @strict.loads(text))
  each("strict, on an anchor", "a: &x 1", text => @strict.loads(text))

  // A stream's first document may say which version the rest are written for,
  // which is what `any` reads to pick a schema; without a directive it is 1.2.2.
  println("")
  println("and by the version the document asks for:")
  each("any, no directive", src, text => @any.loads(text))
  each("any, %YAML 1.1", "%YAML 1.1\n---\nenabled: yes\nmask: 014\n", text => {
    @any.loads(text)
  })
  each("any, %YAML 1.2", "%YAML 1.2\n---\nenabled: yes\nmask: 014\n", text => {
    @any.loads(text)
  })
}

///|
/// Read `src` one way and print what came back, or the refusal.
fn each(
  name : String,
  src : String,
  read : (StringView) -> Json raise @moonyaml.Refused,
) -> Unit {
  let said = read(src[:]).stringify() catch {
    e => "refused — " + e.to_string()
  }
  println("  \{name}: \{said}")
}
