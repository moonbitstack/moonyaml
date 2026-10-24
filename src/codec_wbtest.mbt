// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A configuration record of the kind a program reads out of a file.
struct Server {
  mut host : String
  port : Double
  tags : Array[String]
} derive(Eq, Debug)

///|
pub extend Server with Eq::{equal, not_equal}

///|
pub extend Server with Debug::{to_repr}

///|
/// One member of an object, if the value is one.
fn field(json : Json, key : String) -> Json? {
  if json is Object(obj) {
    obj.get(key)
  } else {
    None
  }
}

///|
impl @json.FromJson for Server with fn from_json(
  json : Json,
  path : @json.JsonPath,
) -> Server raise @json.JsonDecodeError {
  let host = match field(json, "host") {
    Some(Json::String(s)) => s
    _ => raise @json.JsonDecodeError((path, "host is not a string"))
  }
  let port = match field(json, "port") {
    Some(Json::Number(n, ..)) => n
    _ => raise @json.JsonDecodeError((path, "port is not a number"))
  }
  let tags = match field(json, "tags") {
    Some(Json::Array(items)) =>
      items.map(fn(item) {
        match item {
          Json::String(s) => s
          _ => ""
        }
      })
    _ => []
  }
  { host, port, tags, }
}

///|
impl ToJson for Server with fn to_json(self) -> Json {
  Json::object(
    Map([
      ("host", Json::string(self.host)),
      ("port", Json::number(self.port)),
      ("tags", Json::array(self.tags.map(Json::string))),
    ]),
  )
}

///|
pub extend Server with ToJson::{to_json}

///|
test "a document becomes a value, through the same trait a JSON one does" {
  let src = "host: example.com\nport: 8080\ntags: [a, b]\n"
  let server : Server = loads_as(src[:])
  assert_eq(server.host, "example.com")
  assert_eq(server.port, 8080.0)
  assert_eq(server.tags, ["a", "b"])
}

///|
test "a value becomes a document, and reads back as itself" {
  let value : Server = { host: "example.com", port: 8080.0, tags: ["a", "b"], }
  assert_eq(
    dumps_of(value),
    "host: example.com\nport: 8080\ntags:\n  - a\n  - b\n",
  )
  // Read, let the caller fill in what the file left out, write it back.
  assert_eq(
    round_trip("host: example.com\nport: 8080\ntags: []\n"[:], adjust=fn(
      s : Server,
    ) {
      s.host = s.host + "!"
    }),
    "host: example.com!\nport: 8080\ntags: []\n",
  )
}

///|
test "a document that will not read, and one that reads and does not fit" {
  let mut refused = false
  try {
    let _ : Server = loads_as("host: [\n"[:])
  } catch {
    Malformed::Read(_) => refused = true
    _ => ()
  }
  assert_eq(refused, true)
  let mut shaped = false
  try {
    let _ : Server = loads_as("host: 1\nport: 2\n"[:])
  } catch {
    Malformed::Shape(e) =>
      shaped = match e {
        @json.JsonDecodeError((_, why)) => why == "host is not a string"
      }
    _ => ()
  }
  assert_eq(shaped, true)
}

///|
test "every version can write what it reads" {
  let doc = Json::object(Map([("a", Json::string("yes"))]))
  // 1.2 leaves `yes` alone, because it is a string there.
  assert_eq(dumps(doc), "a: yes\n")
  // 1.1 does not: bare, it would read back as a boolean.
  assert_eq(dumps(doc, rules=legacy_rules), "a: \"yes\"\n")
  assert_eq(dumps(doc, rules=ancient_rules), "a: \"yes\"\n")
}
