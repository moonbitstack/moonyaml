// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Why a document did not become the value the caller asked for.
///
/// Two things can go wrong, and they are different things: the YAML may not have
/// been read at all, or it may have been read and not be the shape a type needs.
/// Both carry where — the reader's position, or the path into the document — so a
/// caller can say which line to look at.
pub(all) suberror Malformed {
  Read(Refused)
  /// The document read fine and is not the shape the type asked for. The path is
  /// a JSON Pointer into what was read, `/servers/2/port`.
  Shape(@json.JsonDecodeError)
} derive(Debug)

///|
/// A refusal prints as itself; a shape error prints as the path and the reason.
pub impl Show for Malformed with fn output(self, logger) {
  match self {
    Read(e) => e.output(logger)
    Shape(@json.JsonDecodeError((path, why))) =>
      logger.write_string("\{path}: \{why}")
  }
}

///|
pub extend Malformed with Debug::{to_repr}

///|
pub extend Malformed with Show::{to_string, output}

///|
/// The one document in `src`, as a value of type `T`.
///
/// ```mbt nocheck
/// let config : Config = @moonyaml.loads_as(src)
/// ```
///
/// `T` is anything that implements core's `FromJson`, which is the same trait a
/// JSON document is read through: a type written for `moonjson` needs no second
/// implementation to be read from YAML. That is the point of reading into the same
/// `Json` tree — the shape of a value is one question, and which text it arrived in
/// is another.
///
/// The default schema is 1.2's core. Read a 1.1 file with
/// `@moonyaml/v11`'s schema, or let `@moonyaml/any` pick it from the document.
pub fn[T : @json.FromJson] loads_as(
  src : StringView,
  flavor~ : Flavor = strict,
  schema~ : Schema = core,
) -> T raise Malformed {
  let json = loads(src, flavor~, schema~) catch { e => raise Read(e) }
  @json.from_json(json) catch {
    e => raise Shape(e)
  }
}

///|
/// The one document in `src`, decoded as UTF-8, as a value of type `T`.
pub fn[T : @json.FromJson] load_as(
  src : BytesView,
  flavor~ : Flavor = strict,
  schema~ : Schema = core,
  bom~ : Bool = true,
) -> T raise Malformed {
  let json = load(src, flavor~, schema~, bom~) catch { e => raise Read(e) }
  @json.from_json(json) catch {
    e => raise Shape(e)
  }
}

///|
/// A value of type `T`, written as a YAML document.
///
/// The other direction of [`loads_as`], through the same `ToJson` trait, so a type
/// that writes itself as JSON writes itself as YAML without knowing it.
pub fn[T : ToJson] dumps_of(
  value : T,
  style~ : Style = style,
  indent? : Int32,
  sort? : Bool,
) -> String {
  dumps(ToJson::to_json(value), style~, indent?, sort?)
}

///|
/// A stream of values, each written as its own document.
pub fn[T : ToJson] dumps_of_all(
  values : ArrayView[T],
  style~ : Style = style,
  indent? : Int32,
  sort? : Bool,
) -> String {
  let docs : Array[Json] = []
  for value in values {
    docs.push(ToJson::to_json(value))
  }
  dumps_all(docs, style~, indent?, sort?)
}

///|
/// Read a document as `T`, let `adjust` change it, and write it back.
///
/// The three steps a configuration loader actually takes: read what the user wrote,
/// fill in what they left out, write the whole of it back. `adjust` is where the
/// defaults go, and it is also what says which type this is — a call with no
/// `adjust` cannot tell.
pub fn[T : @json.FromJson + ToJson] round_trip(
  src : StringView,
  adjust~ : (T) -> Unit = fn(_) { () },
  flavor~ : Flavor = strict,
  schema~ : Schema = core,
) -> String raise Malformed {
  let value : T = loads_as(src, flavor~, schema~)
  adjust(value)
  dumps_of(value)
}
