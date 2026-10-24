// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// How YAML 1.0 resolves a scalar: everything 1.1 does, and `y`/`n` — in either
/// case — as booleans.
///
/// The 1.1 revision dropped the single letters, because a lone `n` is more often a
/// name than a no: `n: 1` in a table of columns is a heading, not a false. A file
/// that says `%YAML 1.0` means the older reading.
pub let rules : @moonyaml.Rules = @moonyaml.ancient_rules

///|
/// YAML 1.0's schema.
pub let schema : @moonyaml.Schema = { ..@moonyaml.core, rules, merge: true, }

///|
/// The one document in `src`, read as YAML 1.0.
pub fn loads(
  src : StringView,
  flavor~ : @moonyaml.Flavor = @moonyaml.strict,
) -> Json raise @moonyaml.Refused {
  @moonyaml.loads(src, flavor~, schema~)
}

///|
/// Every document in `src`, read as YAML 1.0.
pub fn loads_all(
  src : StringView,
  flavor~ : @moonyaml.Flavor = @moonyaml.strict,
) -> Array[Json] raise @moonyaml.Refused {
  @moonyaml.loads_all(src, flavor~, schema~)
}

///|
/// The one document in `src`, decoded as UTF-8 and read as YAML 1.0.
pub fn load(
  src : BytesView,
  flavor~ : @moonyaml.Flavor = @moonyaml.strict,
  bom~ : Bool = true,
) -> Json raise @moonyaml.Refused {
  @moonyaml.load(src, flavor~, schema~, bom~)
}

///|
/// Every document in `src`, decoded as UTF-8 and read as YAML 1.0.
pub fn load_all(
  src : BytesView,
  flavor~ : @moonyaml.Flavor = @moonyaml.strict,
  bom~ : Bool = true,
) -> Array[Json] raise @moonyaml.Refused {
  @moonyaml.load_all(src, flavor~, schema~, bom~)
}

///|
/// Write a value as YAML 1.0.
pub fn dumps(
  value : Json,
  style~ : @moonyaml.Style = @moonyaml.style,
  indent? : Int32,
  sort? : Bool,
) -> String {
  @moonyaml.dumps(value, style~, rules~, indent?, sort?)
}

///|
/// Every document, each opened by its own `---`.
pub fn dumps_all(
  values : ArrayView[Json],
  style~ : @moonyaml.Style = @moonyaml.style,
  indent? : Int32,
  sort? : Bool,
) -> String {
  @moonyaml.dumps_all(values, style~, rules~, indent?, sort?)
}
