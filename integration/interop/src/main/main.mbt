// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// The program the interop check drives.
//
// It is not part of the library, and nothing imports it: it exists so that one
// corpus can be written here and read by another implementation, and written
// there and read here, with the values compared after each leg. Documents go
// through the filesystem because a document is text with breaks in it, and
// because both legs hand a whole document over at once.
//
//     write <corpus.json> <directory> <1.2|1.1>
//     read  <directory> <report.json> <1.2|1.1>

///|
fn main {
  let argv = arguments(@env.args())
  match argv {
    ["write", corpus, directory, lane] =>
      match Lane::parse(lane) {
        Some(lane) => write_all(corpus, directory, lane)
        None => refuse("no such version: \{lane}")
      }
    ["read", directory, report, lane] =>
      match Lane::parse(lane) {
        Some(lane) => read_all(directory, report, lane)
        None => refuse("no such version: \{lane}")
      }
    _ => refuse("usage: interop write|read <in> <out> <1.2|1.1>")
  }
}

///|
/// The arguments from the mode word on, which is how `moon run` hands them over:
/// the path of the program comes first and is not interesting.
fn arguments(argv : Array[String]) -> Array[String] {
  let rest : Array[String] = []
  let mut found = false
  for argument in argv {
    if found {
      rest.push(argument)
    } else if argument == "write" || argument == "read" {
      found = true
      rest.push(argument)
    }
  }
  rest
}

///|
fn refuse(why : String) -> Unit {
  println("interop: \{why}")
  @env.exit(2)
}

///|
/// The versions the corpus can be exchanged under, which are the two schemas
/// this library and the other implementation both have.
enum Lane {
  V12
  V11
}

///|
fn Lane::parse(name : String) -> Self? {
  match name {
    "1.2" => Some(V12)
    "1.1" => Some(V11)
    _ => None
  }
}

///|
fn Lane::name(self : Self) -> String {
  match self {
    V12 => "1.2"
    V11 => "1.1"
  }
}

///|
/// Every case of the corpus, written as the document this library makes of it.
fn write_all(corpus : String, directory : String, lane : Lane) -> Unit {
  let cases = cases_for(corpus, lane.name())
  for case_ in cases {
    let text = match lane {
      V12 => @moonyaml.dumps(case_.value)
      V11 => @yaml11.dumps(case_.value)
    }
    write_text(join(directory, case_.id + ".yaml"), text)
  }
  println(
    "interop: wrote \{cases.length()} documents with \{lane.name()} rules into \{directory}",
  )
}

///|
/// Every document in `directory` read under `lane`'s rules, as a report of the
/// values read and the ones refused, so that a document the other
/// implementation wrote and this one cannot read is a line rather than a crash.
fn read_all(directory : String, report : String, lane : Lane) -> Unit {
  let names = list_dir(directory)
  let values : Array[(String, Json)] = []
  let errors : Array[(String, Json)] = []
  for name in names {
    if !name.has_suffix(".yaml") {
      continue
    }
    let id = name.exact_view(start=0, end=name.length() - 5).to_owned()
    let text = read_text(join(directory, name))
    match load(text, lane) {
      Ok(value) => values.push((id, value))
      Err(why) => errors.push((id, Json::string(why)))
    }
  }
  let report_ = Json::object(
    Map([
      ("values", Json::object(Map(values))),
      ("errors", Json::object(Map(errors))),
    ]),
  )
  write_text(report, @moonjson.dumps(report_, indent=2) + "\n")
  println(
    "interop: read \{values.length()} documents with \{lane.name()} rules, \{errors.length()} refused",
  )
}

///|
/// A document read under `lane`'s rules, or the refusal as a line of the report.
fn load(text : String, lane : Lane) -> Result[Json, String] {
  match lane {
    V12 => Ok(@moonyaml.loads(text)) catch { e => Err(e.to_string()) }
    V11 => Ok(@yaml11.loads(text)) catch { e => Err(e.to_string()) }
  }
}

///|
/// A path in `directory`, with the separator the platform takes.
fn join(directory : String, name : String) -> String {
  if directory.has_suffix("/") || directory.has_suffix("\\") {
    directory + name
  } else {
    directory + "/" + name
  }
}

///|
/// A file, or a line saying which one could not be read.
fn read_text(path : String) -> String {
  @fs.read_file_to_string(path) catch {
    @fs.IOError(why) => {
      println("interop: cannot read \{path}: \{why}")
      @env.exit(2)
    }
  }
}

///|
/// Write a file, or say which one could not be written.
fn write_text(path : String, text : String) -> Unit {
  @fs.write_string_to_file(path, text) catch {
    @fs.IOError(why) => {
      println("interop: cannot write \{path}: \{why}")
      @env.exit(2)
    }
  }
}

///|
/// The names in a directory, sorted so that two runs report the same order.
fn list_dir(path : String) -> Array[String] {
  let names = @fs.read_dir(path) catch {
    @fs.IOError(why) => {
      println("interop: cannot list \{path}: \{why}")
      @env.exit(2)
    }
  }
  let names = names.to_owned()
  names.sort()
  names
}

///|
/// JSON as this program reads it, with the text of every number kept: a value
/// wider than a double has to survive being written, and a reader that kept only
/// the double would report a disagreement that is its own fault.
fn parse_json(text : String, what : String) -> Json {
  @moonjson.loads(text, @moonjson.strict) catch {
    e => {
      println("interop: \{what} is not JSON: \{e.message()}")
      @env.exit(2)
    }
  }
}
