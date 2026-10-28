// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Where in the source something is: the offset in code units, and the line and
/// column a person counts from one.
///
/// Every refusal carries one, because a configuration file that will not load is
/// read by a person who needs to know which line to look at.
pub(all) struct At {
  /// The offset in code units from the start of the text.
  at : Int32
  /// The line, counting from one.
  line : Int32
  /// The column, counting from one.
  column : Int32
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
  /// A character that cannot stand where it was written.
  Unexpected(At, Char)
  /// The text ends inside a document: a quote, a bracket or a block scalar that
  /// was never closed.
  Truncated(At)
  /// A double-quoted escape that is not one of §5.7's.
  BadEscape(At)
  /// A line indented to a column that lines up with nothing.
  BadIndent(At)
  /// A tag nobody has, or a node tagged as something it cannot be.
  BadTag(At, String)
  /// An alias naming an anchor that was not written before it.
  BadAnchor(At, String)
  /// A key written twice, under `duplicates: Reject`.
  Repeated(At, String)
  /// A second document where one was asked for.
  Trailing(At)
  /// Nesting past [`Flavor::depth`].
  TooDeep(At)
  /// Aliases expanding past [`Flavor::budget`], with the limit and what it reached.
  Exceeded(at~ : At, limit~ : Int32, got~ : Int32)
  /// Not UTF-8, from the byte entry points.
  BadUtf8(At)
  /// A construct this version does not have: a flow collection under the strict
  /// dialect, a tag or an anchor under a schema that has none, a key that is a
  /// collection where the value tree has only string keys.
  Disallowed(At, String)
} derive(Eq, Debug)

///|
/// A refusal prints as the fault and the line it is on.
pub impl Show for Refused with fn output(self, logger) {
  match self {
    Unexpected(at, c) => logger.write_string("\{at}: unexpected '\{c}'")
    Truncated(at) => logger.write_string("\{at}: ends mid-document")
    BadEscape(at) => logger.write_string("\{at}: not an escape")
    BadIndent(at) => logger.write_string("\{at}: indentation does not line up")
    BadTag(at, t) => logger.write_string("\{at}: unknown tag `\{t}`")
    BadAnchor(at, a) => logger.write_string("\{at}: no anchor named `\{a}`")
    Repeated(at, k) =>
      logger.write_string("\{at}: the key `\{k}` is written twice")
    Trailing(at) => logger.write_string("\{at}: trailing content")
    TooDeep(at) => logger.write_string("\{at}: nested too deep")
    Exceeded(at~, limit~, got~) =>
      logger.write_string("\{at}: expands to \{got} nodes, over \{limit}")
    BadUtf8(at) => logger.write_string("\{at}: not UTF-8")
    Disallowed(at, what) =>
      logger.write_string("\{at}: \{what} is not allowed here")
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
  /// The last value written for a key is the one the mapping has.
  Last
  /// The first value written for a key is the one the mapping has.
  First
  /// A repeated key is refused, with the position of the second one.
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
  /// How deep a document may nest. See [`depth`].
  depth : Int32
  /// What a key written twice means. See [`Duplicates`].
  duplicates : Duplicates
  /// Whether an alias may be resolved at all: `false` refuses one outright, which
  /// is what a caller reading untrusted input may want.
  aliases : Bool
  /// How many nodes the aliases of one document may expand to. See [`budget`].
  budget : Int32
} derive(Eq, Debug)

///|
pub extend Flavor with Debug::{to_repr}

///|
pub extend Flavor with Eq::{not_equal, equal}

///|
/// How deep a document may nest.
///
/// 500 is deep enough for any configuration file ever written and shallow enough
/// that a reader which walks the tree cannot be driven off the stack by one that
/// was not. A document that nests deeper than this is not a configuration file, and
/// is refused rather than read.
pub let depth : Int32 = 500

///|
/// How many nodes the aliases in one document may expand to.
///
/// An alias can name a node that itself contains aliases, so a dozen lines can
/// expand to billions of nodes: the "billion laughs" shape, which is what YAML's
/// alias facility costs unless something counts. There is no published value to
/// follow, so this takes the safe side — enough for any document anyone meant to
/// write, far short of exhausting memory. `Flavor::new(budget=...)` raises it, and
/// `aliases=false` refuses an alias outright.
pub let budget : Int32 = 10_000_000

///|
/// The preset: refuse what is ambiguous, take the last of a repeated key, expand
/// aliases within the budget.
pub let strict : Flavor = { depth, duplicates: Last, aliases: true, budget, }

///|
/// A flavor by name, every knob with the preset's value.
pub fn Flavor::new(
  depth~ : Int32 = depth,
  duplicates~ : Duplicates = Last,
  aliases~ : Bool = true,
  budget~ : Int32 = budget,
) -> Flavor {
  { depth, duplicates, aliases, budget, }
}

///|
/// What a YAML version resolves an unquoted scalar to.
///
/// The three released versions disagree with each other, and the disagreements are
/// all here rather than in the scanner: 1.1 reads `yes` as a boolean, `014` as
/// twelve and `1:30` as ninety, 1.2 reads all three as strings, and StrictYAML
/// reads every scalar as a string whatever it looks like. A version is a set of
/// rules over one reader, which is why this library has one parser and not four.
///
/// A dialect nobody has published yet — a configuration language of your own, a
/// pre-1.0 variant — is a `Rules` of your own, passed through [`Schema`]. Nothing
/// here is closed.
pub(all) struct Rules {
  /// `yes`/`no`/`on`/`off` are booleans (YAML 1.1 §10.3).
  yes_no : Bool
  /// `y`/`n`, in either case, are booleans — YAML 1.0 only; 1.1 dropped them.
  letters : Bool
  /// A `0` prefix means octal: `014` is twelve (1.1 §10.3); 1.2 spells it `0o14`.
  octal : Bool
  /// `0b1010` is ten (1.1 §10.3).
  binary : Bool
  /// `1_000` is a thousand (1.1 §10.3).
  underscores : Bool
  /// `1:30` is ninety and `1:30.5` is ninety and a half (1.1 §10.3).
  sexagesimal : Bool
  /// Every scalar is a string, whatever it looks like — StrictYAML's first rule,
  /// and the reason a StrictYAML document never surprises a reader.
  strings : Bool
} derive(Eq, Debug)

///|
pub extend Rules with Debug::{to_repr}

///|
pub extend Rules with Eq::{not_equal, equal}

///|
/// YAML 1.2's core schema: nothing but `true`/`false`, `null`, and the decimal,
/// `0o` and `0x` numbers of §10.2.
pub let core_rules : Rules = {
  yes_no: false,
  letters: false,
  octal: false,
  binary: false,
  underscores: false,
  sexagesimal: false,
  strings: false,
}

///|
/// YAML 1.1's type resolution, §10.3 of the 1.1 specification: the booleans, the
/// octal and binary integers, the underscored numbers, and the base-60 form.
pub let legacy_rules : Rules = {
  yes_no: true,
  letters: false,
  octal: true,
  binary: true,
  underscores: true,
  sexagesimal: true,
  strings: false,
}

///|
/// YAML 1.0's, which is 1.1 plus the single letters `y` and `n`. The 1.1 revision
/// removed them because a lone `n` is more often a name than a no.
pub let ancient_rules : Rules = { ..legacy_rules, letters: true, }

///|
/// What a YAML version does that the scanner cannot decide for it.
///
/// The scanner in this package is shared; what a version resolves a scalar to, and
/// what it allows besides, is a `Schema`.
///
/// The one in this package is [`core`], the core schema of §10.2. The `v11`,
/// `v10`, `strict` and `any` packages beside it are each a schema over the same
/// scanner, which is why a version is a resolver rather than a fork of the reader.
pub(all) struct Schema {
  /// A scalar as the value it denotes: its text, whether it was quoted, the tag
  /// it carried if any, where it was, and the rules that decide.
  resolve : (String, Bool, String?, At, Rules) -> Json raise Refused
  /// How this version resolves a scalar.
  rules : Rules
  /// Whether a `<<` key merges its value into the mapping around it.
  merge : Bool
  /// Whether a node may carry a tag.
  tags : Bool
  /// Whether a node may be named by an anchor and referred to by an alias.
  anchors : Bool
  /// Whether a collection may be written in flow style.
  flow : Bool
  /// The prefix a `!!` handle names when the document did not redefine it.
  secondary : String
  /// The prefix a `!` handle names when the document did not redefine it.
  primary : String
}

///|
/// The core schema of YAML 1.2.2 §10.2: what this package reads.
pub let core : Schema = {
  resolve: resolve_rules,
  rules: core_rules,
  merge: false,
  tags: true,
  anchors: true,
  flow: true,
  secondary: "tag:yaml.org,2002:",
  primary: "!",
}

///|
/// The version a stream declares in its first `%YAML` directive, if it declares one.
///
/// A reader may pick its rules from the document itself rather than from the
/// caller, which is what [`any`] does. Only the first directive counts: §6.8.1
/// allows one per document, and the one that decides how the rest is read has to
/// come before the rest.
pub fn declared_version(src : StringView) -> (Int32, Int32)? {
  let mut i = 0
  let mut col = 0
  while i < src.length() {
    let c = src[i].to_int()
    if c == 0x0a || c == 0x0d {
      col = 0
      i = i + 1
      continue
    }
    if col == 0 {
      // A document marker ends the header, and a directive after it belongs to
      // another document.
      if c == 0x2d &&
        i + 2 < src.length() &&
        src[i + 1].to_int() == 0x2d &&
        src[i + 2].to_int() == 0x2d {
        return None
      }
      if c == 0x25 && i + 4 < src.length() {
        let word = src[i:i + 5].to_owned()
        if word == "%YAML" {
          let mut j = i + 5
          while j < src.length() &&
                (src[j].to_int() == 0x20 || src[j].to_int() == 0x09) {
            j = j + 1
          }
          let start = j
          while j < src.length() &&
                src[j].to_int() != 0x20 &&
                src[j].to_int() != 0x09 &&
                src[j].to_int() != 0x0a &&
                src[j].to_int() != 0x0d {
            j = j + 1
          }
          return version_of(src[start:j].to_owned())
        }
      }
    }
    col = col + 1
    i = i + 1
  }
  None
}

///|
/// `1.2` as the pair of numbers it spells, or `None`.
fn version_of(version : String) -> (Int32, Int32)? {
  let dot = index_of_unit(version, 0x2e)
  if dot < 1 || dot == version.length() - 1 {
    return None
  }
  match
    (digits_of(version[0:dot]), digits_of(version[dot + 1:version.length()])) {
    (Some(a), Some(b)) => Some((a, b))
    _ => None
  }
}

///|
/// A run of decimal digits as a number, or `None` if there is anything else in it.
fn digits_of(s : StringView) -> Int32? {
  if s.length() == 0 {
    return None
  }
  let mut n = 0
  for i = 0; i < s.length(); i = i + 1 {
    let c = s[i].to_int()
    if c < 0x30 || c > 0x39 {
      return None
    }
    n = n * 10 + (c - 0x30)
  }
  Some(n)
}

///|
/// The one document in `src`.
///
/// Raises [`Refused::Trailing`] if a second document follows, which is what tells a
/// caller expecting one file's worth of configuration that it got a stream.
///
/// `schema` says which YAML version reads it; the default is [`core`]. A
/// document that opens with `%YAML 1.1` is not read as 1.2 by default — pick
/// the version, or let the `any` package pick it for you.
pub fn loads(
  src : StringView,
  flavor~ : Flavor = strict,
  schema~ : Schema = core,
) -> Json raise Refused {
  let docs = loads_all(src, flavor~, schema~)
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
  flavor~ : Flavor = strict,
  schema~ : Schema = core,
) -> Array[Json] raise Refused {
  Reader::new(src, flavor, schema).stream()
}

///|
/// The one document in `src`, decoded as UTF-8.
///
/// `bom` skips a leading byte-order mark, which YAML 1.2.2 §5.2 allows at the start
/// of a stream and which an editor on Windows will happily write.
pub fn load(
  src : BytesView,
  flavor~ : Flavor = strict,
  schema~ : Schema = core,
  bom~ : Bool = true,
) -> Json raise Refused {
  loads(text(src, bom), flavor~, schema~)
}

///|
/// Every document in `src`, decoded as UTF-8.
pub fn load_all(
  src : BytesView,
  flavor~ : Flavor = strict,
  schema~ : Schema = core,
  bom~ : Bool = true,
) -> Array[Json] raise Refused {
  loads_all(text(src, bom), flavor~, schema~)
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
fn here(src : StringView, line : Int32) -> At {
  { at: src.length(), line, column: 1, }
}

///|
/// Where the refusal happened.
///
/// Every variant carries a position, so a caller that wants to report the line and
/// column does not have to match all twelve of them to get at it.
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
    | BadUtf8(at)
    | Disallowed(at, _) => at
    Exceeded(at~, ..) => at
  }
}
