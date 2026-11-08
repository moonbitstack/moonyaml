// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// `src`, read and written again with `style`.
fn w(src : String, style : Style) -> String raise Refused {
  dumps(loads(src[:]), style~)
}

///|
/// One key holding `s`, written with `style`.
fn k(s : String, style : Style) -> String {
  dumps({ "a": Json::string(s) }, style~)
}

///|
test "Style::new is the preset, field for field" {
  // A record built by name and the preset have to be the same style, or a caller
  // who passes `Style::new()` would get a document written some other way.
  assert_eq(Style::new(), style)
  assert_eq(Style::new(indent=2), style)
  assert_eq(w("{a: {b: 1}}", Style::new()), "a:\n  b: 1\n")
}

///|
test "Auto writes a collection of scalars on one line, and a block once it will not fit" {
  let auto = Style::new(layout=Auto)
  assert_eq(w("{a: [1, 2]}", auto), "a: [1, 2]\n")
  assert_eq(w("{a: {b: 1}}", auto), "a: {b: 1}\n")
  // A collection holding a collection stays block: that is the shape of a file.
  assert_eq(w("{a: {b: {c: 1}}}", auto), "a:\n  b: {c: 1}\n")
  // The width is what decides the rest.
  let narrow = Style::new(layout=Auto, width=12)
  assert_eq(
    w("{a: [one, two, three]}", narrow),
    "a:\n  - one\n  - two\n  - three\n",
  )
}

///|
test "Flow writes every collection as JSON does" {
  assert_eq(w("{a: [1, 2], b: {c: d}}", flow), "{a: [1, 2], b: {c: d}}\n")
  assert_eq(w("- {a: 1}\n- [2, 3]\n", flow), "[{a: 1}, [2, 3]]\n")
}

///|
test "the quote a string is given is a knob, and the escape comes with it" {
  // Minimal quotes only what would read back as something else.
  assert_eq(k("1", style), "a: \"1\"\n")
  assert_eq(k("hello", style), "a: hello\n")
  // Single and Double are for output that feeds a second reader.
  assert_eq(k("1", Style::new(quotes=Single)), "a: '1'\n")
  assert_eq(k("1", Style::new(quotes=Double)), "a: \"1\"\n")
  // A single quote inside a single-quoted scalar is doubled, which is the one
  // escape that style has. A quote alone does not force quoting: `it's` is plain.
  assert_eq(k("it's 1", Style::new(quotes=Single)), "a: it's 1\n")
  assert_eq(k("it's: 1", Style::new(quotes=Single)), "a: 'it''s: 1'\n")
  assert_eq(k("it's: 1", Style::new(quotes=Double)), "a: \"it's: 1\"\n")
  // A string a quoted style cannot hold plain still gets the escapes it needs.
  assert_eq(k("a\tb", Style::new(quotes=Double)), "a: \"a\\tb\"\n")
}

///|
test "a subtree written twice is a reference, and turning that off writes it twice" {
  let repeated = "{a: {x: 1}, b: {x: 1}}"
  assert_eq(w(repeated, style), "a: &a0\n  x: 1\nb: *a0\n")
  assert_eq(w(repeated, Style::new(anchors=false)), "a:\n  x: 1\nb:\n  x: 1\n")
  // Three copies share one name, and the name is the writer's, not the file's.
  assert_eq(
    w("{a: {x: 1}, b: {x: 1}, c: {x: 1}}", style),
    "a: &a0\n  x: 1\nb: *a0\nc: *a0\n",
  )
}

///|
test "what fits in the width stays on the line, and a long plain scalar folds at a space" {
  let long = "one two three four five six seven"
  let narrow = Style::new(width=20)
  assert_eq(k(long, narrow), "a: one two three\n  four five six\n  seven\n")
  // What is read back is the string that was written, spaces and all.
  let back = loads(k(long, narrow)[:])
  guard back is Object(m) && m.get("a") is Some(String(got)) else {
    fail("a folded scalar is still a string")
  }
  assert_eq(got, long)
  // A scalar with nothing to fold at is written on one line however long it is.
  assert_eq(
    k("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", narrow),
    "a: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n",
  )
}

///|
test "every style writes a document it reads back as the same value" {
  let src = "a:\n  b:\n    c: [1, 2]\nd: {e: f}\n"
  let once = loads(src[:])
  for
    style in [
      style,
      flow,
      Style::new(layout=Auto),
      Style::new(indent=4),
      Style::new(quotes=Double),
    ] {
    let text = dumps(once, style~)
    assert_eq(loads(text[:]).stringify(), once.stringify())
  }
}
