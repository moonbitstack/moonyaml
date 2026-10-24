// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The schema a stream asks for.
///
/// A document that opens with `%YAML 1.1` says how it wants to be read, and 1.1's
/// rules are not 1.2's: `yes` is a boolean there and a string here, `014` is twelve
/// there and fourteen here. Reading it as 1.2 would silently give the caller a
/// different value from the one the file's author wrote, which is the one failure
/// mode a configuration loader must not have.
///
/// No directive means 1.2, which is the current release and what a file written
/// without a version marker means today. A directive naming a major version this
/// library does not have is refused, rather than read with the wrong rules.
pub fn of(src : StringView) -> @moonyaml.Schema raise @moonyaml.Refused {
  match @moonyaml.declared_version(src) {
    None => @moonyaml.core
    Some((1, 0)) => @yaml10.schema
    Some((1, 1)) => @yaml11.schema
    Some((1, _)) => @moonyaml.core
    Some((major, minor)) =>
      raise @moonyaml.Refused::BadTag(
        { at: 0, line: 1, column: 1, },
        "%YAML \{major}.\{minor}",
      )
  }
}

///|
/// The one document in `src`, read with the rules it asks for.
pub fn loads(
  src : StringView,
  flavor~ : @moonyaml.Flavor = @moonyaml.strict,
) -> Json raise @moonyaml.Refused {
  @moonyaml.loads(src, flavor~, schema=of(src))
}

///|
/// Every document in `src`, read with the rules the first of them asks for.
pub fn loads_all(
  src : StringView,
  flavor~ : @moonyaml.Flavor = @moonyaml.strict,
) -> Array[Json] raise @moonyaml.Refused {
  @moonyaml.loads_all(src, flavor~, schema=of(src))
}

///|
/// The one document in `src`, decoded as UTF-8 and read with the rules it asks for.
pub fn load(
  src : BytesView,
  flavor~ : @moonyaml.Flavor = @moonyaml.strict,
  bom~ : Bool = true,
) -> Json raise @moonyaml.Refused {
  let decoded = @utf8.decode(src, ignore_bom=bom) catch {
    _ => raise @moonyaml.Refused::BadUtf8({ at: 0, line: 1, column: 1, })
  }
  @moonyaml.loads(decoded, flavor~, schema=of(decoded))
}
