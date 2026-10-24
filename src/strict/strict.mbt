// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// How StrictYAML resolves a scalar: as text, always.
///
/// This is the whole of StrictYAML's first promise. `port: 8080` and
/// `port: "8080"` are the same string, `enabled: yes` is the word, and the caller
/// says what a value means by reading it through a schema of its own. Nothing in a
/// document is a number, a boolean or a null because of how it is spelled.
pub let rules : @moonyaml.Rules = { ..@moonyaml.core_rules, strings: true, }

///|
/// StrictYAML's schema: text scalars, no tags, no anchors, no flow style.
///
/// Each of those is a feature StrictYAML removes, and each is removed for the same
/// reason — it makes what a document says depend on something other than the text
/// in front of the reader:
///
/// - a tag asks for a type the reader may not have;
/// - an anchor makes one node appear in two places, so the document is no longer a
///   tree you can read top to bottom;
/// - flow style packs structure onto a line, which is where the bracket-matching
///   mistakes come from.
pub let schema : @moonyaml.Schema = {
  ..@moonyaml.core,
  rules,
  merge: false,
  tags: false,
  anchors: false,
  flow: false,
}

///|
/// The preset for reading StrictYAML: a repeated key is a fault.
///
/// StrictYAML rejects duplicate keys, and it is right to: a mapping that names the
/// same key twice has no reading that a person could have predicted.
pub let flavor : @moonyaml.Flavor = @moonyaml.Flavor::new(duplicates=Reject)

///|
/// The one document in `src`, read as StrictYAML.
pub fn loads(
  src : StringView,
  flavor~ : @moonyaml.Flavor = flavor,
) -> Json raise @moonyaml.Refused {
  @moonyaml.loads(src, flavor~, schema~)
}

///|
/// Every document in `src`, read as StrictYAML.
///
/// StrictYAML has no multi-document streams — a file is a document — so this is the
/// same as [`loads`] and exists to keep call sites that do not care about the
/// difference working across versions.
pub fn loads_all(
  src : StringView,
  flavor~ : @moonyaml.Flavor = flavor,
) -> Array[Json] raise @moonyaml.Refused {
  @moonyaml.loads_all(src, flavor~, schema~)
}

///|
/// The one document in `src`, decoded as UTF-8 and read as StrictYAML.
pub fn load(
  src : BytesView,
  flavor~ : @moonyaml.Flavor = flavor,
  bom~ : Bool = true,
) -> Json raise @moonyaml.Refused {
  @moonyaml.load(src, flavor~, schema~, bom~)
}

///|
/// Write a value as StrictYAML: every scalar is quoted unless it reads back as
/// itself, because in StrictYAML there is nothing else it could be.
pub fn dumps(
  value : Json,
  style~ : @moonyaml.Style = @moonyaml.style,
  indent? : Int32,
  sort? : Bool,
) -> String {
  @moonyaml.dumps(value, style~, rules~, indent?, sort?)
}
