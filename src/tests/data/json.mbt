// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// One of the suite's JSON values, or `None` where the text is not one.
///
/// The suite's `json` field is written by hand in places and by the reference
/// parsers in others, so it is read strictly: a value that will not parse is a
/// fault in the data, and the harness should say so rather than quietly compare
/// nothing.
pub fn expected(text : String) -> Json? {
  let value = @moonjson.loads(text, @moonjson.strict) catch { _ => return None }
  Some(value)
}
