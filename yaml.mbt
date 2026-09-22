// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Where in the source something is: the offset in code units, and the line and
/// column a person counts from one.
///
/// Every refusal carries one, because a configuration file that will not load is
/// read by a person who needs to know which line to look at.
pub(all) struct At {
  at : Int
  line : Int
  column : Int
} derive(Eq, Debug)

///|
pub impl Show for At with fn output(self, logger) {
  logger.write_string("\{self.line}:\{self.column}")
}

///|
pub extend At with Debug::{to_repr}

///|
pub extend At with Show::{to_string, output}

///|
pub extend At with Eq::{not_equal, equal}

///|
/// Why a document was refused.
///
/// YAML's own answer to ambiguity is to be permissive, which is how a configuration
/// file comes to mean something other than what it looks like. This reader refuses
/// instead: anything it cannot resolve to one reading is an error with a position,
/// never a guess.
pub(all) suberror Refused {
  Unexpected(At, Char)
  Truncated(At)
  BadEscape(At)
  BadIndent(At)
  BadTag(At, String)
  BadAnchor(At, String)
  Repeated(At, String)
  Trailing(At)
  TooDeep(At)
  Exceeded(at~ : At, limit~ : Int, got~ : Int)
  BadUtf8(At)
} derive(Eq, Debug)

///|
/// A refusal prints as the fault and the line it is on.
pub impl Show for Refused with fn output(self, logger) {
  match self {
    Unexpected(at, c) => logger.write_string("\{at}: unexpected '\{c}'")
    Truncated(at) => logger.write_string("\{at}: ends mid-document")
    BadEscape(at) => logger.write_string("\{at}: not an escape")
    BadIndent(at) => logger.write_string("\{at}: indentation does not line up")
    BadTag(at, t) => logger.write_string("\{at}: unknown tag \{t}")
    BadAnchor(at, a) => logger.write_string("\{at}: no anchor named \{a}")
    Repeated(at, k) => logger.write_string("\{at}: repeated key \{k}")
    Trailing(at) => logger.write_string("\{at}: trailing content")
    TooDeep(at) => logger.write_string("\{at}: nested too deep")
    Exceeded(at~, limit~, got~) =>
      logger.write_string("\{at}: expands to \{got} nodes, over \{limit}")
    BadUtf8(at) => logger.write_string("\{at}: not UTF-8")
  }
}

///|
pub extend Refused with Debug::{to_repr}

///|
pub extend Refused with Show::{to_string, output}

///|
pub extend Refused with Eq::{not_equal, equal}

///|
/// What to do when a mapping names the same key twice.
///
/// YAML 1.2.2 §3.2.1.1 says the keys of a mapping are unique and leaves the handling
/// of a duplicate to the processor. Every loader in reach takes the last one, which
/// is what `Last` does; `First` and `Reject` are here because a configuration file
/// with a key written twice is usually a mistake someone would rather be told about.
pub(all) enum Duplicates {
  Last
  First
  Reject
} derive(Eq, Debug)

///|
pub extend Duplicates with Debug::{to_repr}

///|
pub extend Duplicates with Eq::{not_equal, equal}

///|
/// How a document is read: the limits, and what to do with a duplicate key.
///
/// The preset is [`strict`]. Build another with [`Flavor::new`], or update one in
/// place with `{ ..strict, depth: 64 }`.
pub(all) struct Flavor {
  depth : Int
  duplicates : Duplicates
  aliases : Bool
  budget : Int
} derive(Eq, Debug)

///|
pub extend Flavor with Debug::{to_repr}

///|
pub extend Flavor with Eq::{not_equal, equal}

///|
/// How deep a document may nest.
///
/// 500 is what this family uses for JSON, between Jackson's 1000 and serde_json's
/// 128, and a YAML document that nests deeper than a JSON one would is not a
/// configuration file.
pub let depth : Int = 500

///|
/// How many nodes the aliases in one document may expand to.
///
/// An alias can name a node that itself contains aliases, so a dozen lines can
/// expand to billions — the "billion laughs" of YAML, which libyaml and PyYAML's
/// `safe_load` both still perform faithfully. There is no common value to follow
/// here, so this takes the safe side: enough for any real document, far short of
/// exhausting memory. `Flavor::new(budget=...)` raises it, and `aliases=false`
/// refuses them outright.
pub let budget : Int = 10_000_000

///|
/// The preset: refuse what is ambiguous, take the last of a repeated key, expand
/// aliases within the budget.
pub let strict : Flavor = { depth, duplicates: Last, aliases: true, budget, }

///|
/// A flavor by name, every knob with the preset's value.
pub fn Flavor::new(
  depth? : Int = depth,
  duplicates? : Duplicates = Last,
  aliases? : Bool = true,
  budget? : Int = budget,
) -> Flavor {
  { depth, duplicates, aliases, budget, }
}

///|
/// The one document in `src`.
///
/// Raises [`Refused::Trailing`] if a second document follows, which is what tells a
/// caller expecting one file's worth of configuration that it got a stream.
pub fn loads(src : StringView, flavor? : Flavor = strict) -> Json raise Refused {
  let docs = loads_all(src, flavor~)
  match docs.length() {
    0 => Json::null()
    1 => docs[0]
    _ => raise Trailing(here(src, docs.length()))
  }
}

///|
/// Every document in `src`, in order.
///
/// A stream with no documents at all is an empty array, not a null: nothing is not
/// the same as one document containing nothing.
pub fn loads_all(
  src : StringView,
  flavor? : Flavor = strict,
) -> Array[Json] raise Refused {
  Reader::new(src, flavor).stream()
}

///|
/// The one document in `src`, decoded as UTF-8.
///
/// `bom` skips a leading byte-order mark, which YAML 1.2.2 §5.2 allows at the start
/// of a stream and which an editor on Windows will happily write.
pub fn load(
  src : BytesView,
  flavor? : Flavor = strict,
  bom? : Bool = true,
) -> Json raise Refused {
  loads(text(src, bom), flavor~)
}

///|
/// Every document in `src`, decoded as UTF-8.
pub fn load_all(
  src : BytesView,
  flavor? : Flavor = strict,
  bom? : Bool = true,
) -> Array[Json] raise Refused {
  loads_all(text(src, bom), flavor~)
}

///|
/// The source as text.
fn text(src : BytesView, bom : Bool) -> String raise Refused {
  @utf8.decode(src, ignore_bom=bom) catch {
    _ => raise BadUtf8({ at: 0, line: 1, column: 1, })
  }
}

///|
/// A position at the end of `src`, for a fault that is about the stream as a whole
/// rather than about one character in it.
fn here(src : StringView, line : Int) -> At {
  { at: src.length(), line, column: 1, }
}

///|
/// Where the refusal happened.
///
/// Every variant carries a position, so a caller that wants to report the line and
/// column does not have to match all eleven of them to get at it.
pub fn Refused::at(self : Refused) -> At {
  match self {
    Unexpected(at, _)
    | Truncated(at)
    | BadEscape(at)
    | BadIndent(at)
    | BadTag(at, _)
    | BadAnchor(at, _)
    | Repeated(at, _)
    | Trailing(at)
    | TooDeep(at)
    | BadUtf8(at) => at
    Exceeded(at~, ..) => at
  }
}
