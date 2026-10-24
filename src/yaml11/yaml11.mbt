// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// How YAML 1.1 resolves a scalar: `yes`/`no`/`on`/`off` are booleans, `014` is
/// twelve, `0b1010` is ten, `1_000` is a thousand, and `1:30` is ninety.
pub let rules : @moonyaml.Rules = @moonyaml.legacy_rules

///|
/// YAML 1.1's schema: the 1.1 types, and the merge key.
///
/// The merge key is 1.1's own (§7.1) — a `<<` key whose value is a mapping, or a
/// sequence of mappings, is folded into the mapping around it. It is not in 1.2,
/// which is why this is a schema and not a default.
pub let schema : @moonyaml.Schema = { ..@moonyaml.core, rules, merge: true, }

///|
/// The one document in `src`, read as YAML 1.1.
pub fn loads(
  src : StringView,
  flavor~ : @moonyaml.Flavor = @moonyaml.strict,
) -> Json raise @moonyaml.Refused {
  @moonyaml.loads(src, flavor~, schema~)
}

///|
/// Every document in `src`, read as YAML 1.1.
pub fn loads_all(
  src : StringView,
  flavor~ : @moonyaml.Flavor = @moonyaml.strict,
) -> Array[Json] raise @moonyaml.Refused {
  @moonyaml.loads_all(src, flavor~, schema~)
}

///|
/// The one document in `src`, decoded as UTF-8 and read as YAML 1.1.
pub fn load(
  src : BytesView,
  flavor~ : @moonyaml.Flavor = @moonyaml.strict,
  bom~ : Bool = true,
) -> Json raise @moonyaml.Refused {
  @moonyaml.load(src, flavor~, schema~, bom~)
}

///|
/// Every document in `src`, decoded as UTF-8 and read as YAML 1.1.
pub fn load_all(
  src : BytesView,
  flavor~ : @moonyaml.Flavor = @moonyaml.strict,
  bom~ : Bool = true,
) -> Array[Json] raise @moonyaml.Refused {
  @moonyaml.load_all(src, flavor~, schema~, bom~)
}

///|
/// Write a value as YAML 1.1: a string that 1.1 would read back as a boolean or a
/// number is quoted, so what is written is what is read.
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
