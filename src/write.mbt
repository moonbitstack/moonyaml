// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// How a collection is laid out.
///
/// `Block` is the style a configuration file is written in: one entry per line, a
/// person can read it and a diff shows one change per line. `Flow` is the brace and
/// bracket form, which JSON shares and which a machine-generated file often wants.
/// `Auto` picks per collection: flow when it holds nothing but scalars and the
/// whole of it fits in [`Style::width`], block otherwise. A collection of
/// collections stays block, because that is the shape of a configuration file.
pub(all) enum Layout {
  Block
  Flow
  Auto
} derive(Eq, Debug)

///|
pub extend Layout with Debug::{to_repr}

///|
pub extend Layout with Eq::{not_equal, equal}

///|
/// Which quote a string gets when it needs one.
///
/// `Minimal` quotes only what would otherwise read as something else, which is what
/// makes the output look written rather than generated. `Single` and `Double` are
/// for a caller whose output feeds a second reader that is happier with one form.
pub(all) enum Quotes {
  Minimal
  Single
  Double
} derive(Eq, Debug)

///|
pub extend Quotes with Debug::{to_repr}

///|
pub extend Quotes with Eq::{not_equal, equal}

///|
/// How a document is written: the indentation, the line width, the layout, the
/// quotes, and whether a repeated subtree is written once and referred to after.
///
/// The preset is [`style`]. Build another with [`Style::new`], or update one in
/// place with `{ ..style, width: 120 }`.
pub(all) struct Style {
  /// Spaces per level.
  indent : Int32
  /// The column past which a collection is no longer written on one line, and at
  /// which a long plain scalar is folded.
  width : Int32
  layout : Layout
  quotes : Quotes
  /// Whether a subtree written twice is written once with `&a1` and referred to by
  /// `*a1` after. Off for output that a person will edit by hand, because an anchor
  /// is a thing to read around; on by default for files a program writes, where it
  /// turns a repeated block into one line.
  anchors : Bool
  /// Whether mapping keys are written in sorted order.
  sort : Bool
} derive(Eq, Debug)

///|
pub extend Style with Debug::{to_repr}

///|
pub extend Style with Eq::{not_equal, equal}

///|
/// How much a nested level is indented.
///
/// Two spaces: what Kubernetes manifests, Compose files and every configuration
/// example in the wild use, and what a reader's eye is trained on.
pub let indent : Int32 = 2

///|
/// The column a writer folds at.
///
/// 80: the width `yamllint` defaults to, which is itself the width of a terminal and
/// of the Python PEP 8 convention the tooling around YAML grew up beside.
pub let width : Int32 = 80

///|
/// The preset: two-space block style, folded at 80 columns, quoting only what has
/// to be quoted, anchors for what repeats.
///
/// Block, not `Auto`: what this writes is a configuration file, and a configuration
/// file is read one entry to a line. `Auto` is a knob for output whose reader is a
/// machine.
pub let style : Style = {
  indent,
  width,
  layout: Block,
  quotes: Minimal,
  anchors: true,
  sort: false,
}

///|
/// The same document, all in flow style — the form JSON shares.
pub let flow : Style = { ..style, layout: Flow, anchors: false, }

///|
/// A style by name, every knob with the preset's value.
pub fn Style::new(
  indent~ : Int32 = indent,
  width~ : Int32 = width,
  layout~ : Layout = Auto,
  quotes~ : Quotes = Minimal,
  anchors~ : Bool = true,
  sort~ : Bool = false,
) -> Style {
  { indent, width, layout, quotes, anchors, sort, }
}

///|
/// Whether a string can be written without quotes.
///
/// It cannot if it is empty, if it would read back as something other than a
/// string, if it begins with a character YAML gives a meaning to, if it carries
/// a `: ` or a ` #` that would be read as structure or a comment, or if it has
/// space at either end where the reader would trim it.
fn bare(s : String, rules : Rules) -> Bool {
  if s.length() == 0 {
    return false
  }
  if s == "true" || s == "false" || s == "null" || s == "~" {
    return false
  }
  if rules.yes_no &&
    (
      s == "yes" ||
      s == "no" ||
      s == "on" ||
      s == "off" ||
      s == "Yes" ||
      s == "No" ||
      s == "On" ||
      s == "Off" ||
      s == "YES" ||
      s == "NO" ||
      s == "ON" ||
      s == "OFF"
    ) {
    return false
  }
  if rules.letters && (s == "y" || s == "n" || s == "Y" || s == "N") {
    return false
  }
  // Anything the core schema would read back as a number has to be quoted, or the
  // reader would hand the caller a number where a string was written.
  if number(s, rules) is Some(_) {
    return false
  }
  if is_blank(s[0].to_int()) || is_blank(s[s.length() - 1].to_int()) {
    return false
  }
  // The characters YAML reserves at the start of a scalar.
  for c in "-?:,[]{}#&*!|>'\"%@`" {
    if s[0].to_int() == c.to_int() {
      return false
    }
  }
  for i = 0; i < s.length(); i = i + 1 {
    let c = s[i].to_int()
    if c < 0x20 || c == 0x7f {
      return false
    }
    if c == ':'.to_int() && (i + 1 == s.length() || is_blank(s[i + 1].to_int())) {
      return false
    }
    if c == '#'.to_int() && i > 0 && is_blank(s[i - 1].to_int()) {
      return false
    }
  }
  true
}

///|
/// A string in double quotes, with the escapes YAML defines.
fn quoted(out : StringBuilder, s : String) -> Unit {
  out.write_char('"')
  for i = 0; i < s.length(); i = i + 1 {
    let c = s[i].to_int()
    match c {
      0x22 => out.write_string("\\\"")
      0x5c => out.write_string("\\\\")
      0x0a => out.write_string("\\n")
      0x0d => out.write_string("\\r")
      0x09 => out.write_string("\\t")
      _ =>
        if c < 0x20 || c == 0x7f {
          out.write_string("\\x")
          two_hex(out, c)
        } else {
          out.write_char(s[i].unsafe_to_char())
        }
    }
  }
  out.write_char('"')
}

///|
/// A string in single quotes, where the only thing to escape is a quote.
fn single_quoted(out : StringBuilder, s : String) -> Unit {
  out.write_char('\'')
  for i = 0; i < s.length(); i = i + 1 {
    let c = s[i].to_int()
    if c == 0x27 {
      out.write_string("''")
    } else {
      out.write_char(s[i].unsafe_to_char())
    }
  }
  out.write_char('\'')
}

///|
/// A byte as two hex digits.
fn two_hex(out : StringBuilder, c : Int32) -> Unit {
  let digits = "0123456789abcdef"
  out.write_char(digits[(c >> 4) & 0xf].unsafe_to_char())
  out.write_char(digits[c & 0xf].unsafe_to_char())
}

///|
/// A number as YAML writes it: a whole value without a fractional part, so a
/// port is `8080` rather than `8080.0`.
fn write_number(out : StringBuilder, n : Double) -> Unit {
  if n == n.floor() && n.abs() < 1.0e15 {
    out.write_string(n.to_int64().to_string())
  } else {
    out.write_string(n.to_string())
  }
}

///|
/// A string with the quotes the style asks for, given whether plain would do.
fn write_text(
  out : StringBuilder,
  s : String,
  style : Style,
  rules : Rules,
) -> Unit {
  let plain = bare(s, rules)
  match style.quotes {
    Minimal => if plain { out.write_string(s) } else { quoted(out, s) }
    Double => quoted(out, s)
    Single =>
      if plain {
        out.write_string(s)
      } else if has_control(s) || index_of_unit(s, 0x0a) >= 0 {
        // A single-quoted scalar cannot hold a control character, and a block is
        // the only form that keeps a line break readable.
        quoted(out, s)
      } else {
        single_quoted(out, s)
      }
  }
}

///|
/// Whether a string holds a character no single-quoted scalar may carry.
fn has_control(s : String) -> Bool {
  for i = 0; i < s.length(); i = i + 1 {
    let c = s[i].to_int()
    if c < 0x20 || c == 0x7f {
      return true
    }
  }
  false
}

///|
/// A scalar, quoted only when plain would read back as something else.
fn write_scalar(
  out : StringBuilder,
  value : Json,
  style : Style,
  rules : Rules,
) -> Unit {
  match value {
    Null => out.write_string("null")
    True => out.write_string("true")
    False => out.write_string("false")
    Number(n, ..) => write_number(out, n)
    String(s) => write_text(out, s, style, rules)
    _ => out.write_string("null")
  }
}

///|
/// A plain scalar folded at spaces so that no line runs past `width`.
///
/// A plain scalar's line breaks read back as spaces (§6.5), so folding one at a
/// space is the one place a writer can wrap a long line without changing it. It is
/// done only where that is exactly true: single spaces inside, none at either end.
fn write_folded(
  out : StringBuilder,
  s : String,
  column : Int32,
  width : Int32,
) -> Unit {
  if width <= 0 || column + s.length() <= width || !foldable(s) {
    out.write_string(s)
    return
  }
  let mut col = column
  let mut start = 0
  for i = 0; i <= s.length(); i = i + 1 {
    if i == s.length() || (s[i].to_int() == 0x20 && i > start) {
      let piece = s[start:i].to_owned()
      if col > column && col + 1 + piece.length() > width {
        out.write_char('\n')
        pad(out, column)
        col = column
      } else if col > column {
        out.write_char(' ')
        col = col + 1
      }
      out.write_string(piece)
      col = col + piece.length()
      start = i + 1
    }
  }
}

///|
/// Whether a scalar can be folded without changing what it says.
fn foldable(s : String) -> Bool {
  if !bare(s, core_rules) || s.length() == 0 {
    return false
  }
  if is_blank(s[0].to_int()) || is_blank(s[s.length() - 1].to_int()) {
    return false
  }
  let mut i = 0
  while i < s.length() {
    if s[i].to_int() == 0x20 {
      if i + 1 < s.length() && s[i + 1].to_int() == 0x20 {
        return false
      }
    }
    i = i + 1
  }
  true
}

///|
/// A string that is better written as a literal block scalar than escaped into
/// one quoted line: the shell script, the PEM key, the message of the day.
///
/// It has to have a line break to be worth it, and it has to carry nothing a
/// literal block cannot hold — a carriage return, a control character, or a line
/// that begins with space, which would need an explicit indentation indicator to
/// survive the round trip.
fn literal_of(value : Json) -> String? {
  guard value is String(s) else { return None }
  if index_of_unit(s, 0x0a) < 0 {
    return None
  }
  let mut bol = true
  for i = 0; i < s.length(); i = i + 1 {
    let c = s[i].to_int()
    if c == 0x0a {
      bol = true
      continue
    }
    if c < 0x20 || c == 0x7f {
      return None
    }
    if bol && is_blank(c) {
      return None
    }
    bol = false
  }
  Some(s)
}

///|
/// A literal block scalar: the header on the current line, then the content on the
/// lines under it at `column`.
///
/// The chomping indicator carries the trailing breaks exactly — `-` for none, none
/// for one, `+` for more — so what is read back is what was written.
fn write_literal(out : StringBuilder, s : String, column : Int32) -> Unit {
  let mut end = s.length()
  let mut trailing = 0
  while end > 0 && s[end - 1].to_int() == 0x0a {
    end = end - 1
    trailing = trailing + 1
  }
  out.write_string(
    match trailing {
      0 => "|-"
      1 => "|"
      _ => "|+"
    },
  )
  let body = s[0:end].to_owned()
  let mut start = 0
  for i = 0; i <= body.length(); i = i + 1 {
    if i == body.length() || body[i].to_int() == 0x0a {
      out.write_char('\n')
      if i > start {
        pad(out, column)
        out.write_string(body[start:i].to_owned())
      }
      start = i + 1
    }
  }
  for i = 1; i < trailing; i = i + 1 {
    out.write_char('\n')
  }
}

///|
/// Whether a value is written on the same line as the key or item that owns it.
fn inline(value : Json) -> Bool {
  match value {
    Array(items) => items.length() == 0
    Object(members) => members.length() == 0
    _ => true
  }
}

///|
/// A value that fits on one line: a scalar, or the flow form of an empty
/// collection — which is the only way block style can express one.
fn write_inline(
  out : StringBuilder,
  value : Json,
  style : Style,
  rules : Rules,
) -> Unit {
  match value {
    Array(_) => out.write_string("[]")
    Object(_) => out.write_string("{}")
    _ => write_scalar(out, value, style, rules)
  }
}

///|
fn pad(out : StringBuilder, n : Int32) -> Unit {
  for _ in 0..<n {
    out.write_char(' ')
  }
}

// -- anchors -------------------------------------------------------------------

///|
/// What the writer knows about the tree it is writing, beyond the text so far.
priv struct Out {
  buf : StringBuilder
  style : Style
  rules : Rules
  // A subtree's text to the anchor that names it, and the anchors already written.
  counts : Map[String, Int32]
  bound : Map[String, String]
  mut next : Int32
}

///|
fn Out::new(style : Style, value : Json, rules : Rules) -> Out {
  let counts : Map[String, Int32] = Map([])
  tally(counts, value)
  { buf: StringBuilder(), style, rules, counts, bound: Map([]), next: 0, }
}

///|
/// Count the collection subtrees a document holds, by their text, so the writer
/// knows which ones repeat.
fn tally(counts : Map[String, Int32], value : Json) -> Unit {
  match value {
    Array(items) =>
      if items.length() > 0 {
        let k = value.stringify()
        counts[k] = match counts.get(k) {
          Some(n) => n + 1
          None => 1
        }
        for item in items {
          tally(counts, item)
        }
      }
    Object(members) =>
      if members.length() > 0 {
        let k = value.stringify()
        counts[k] = match counts.get(k) {
          Some(n) => n + 1
          None => 1
        }
        for _, item in members {
          tally(counts, item)
        }
      }
    _ => ()
  }
}

///|
/// The reference to write in front of a repeated subtree: `*a1` where it has been
/// written, `&a1` where it has not, or nothing at all.
fn Out::anchor(self : Out, value : Json) -> String {
  let style = self.style
  if !style.anchors {
    return ""
  }
  let k = value.stringify()
  let repeats = match self.counts.get(k) {
    Some(n) => n > 1
    None => false
  }
  if !repeats {
    return ""
  }
  match self.bound.get(k) {
    Some(name) => "*" + name
    None => {
      let name = "a" + self.next.to_string()
      self.next = self.next + 1
      self.bound[k] = name
      "&" + name
    }
  }
}

// -- writing -------------------------------------------------------------------

///|
/// A block at `column`, which is the number of spaces its own lines begin with.
fn block(out : Out, value : Json, column : Int32) -> Unit {
  let style = out.style
  let rules = out.rules
  let step = style.indent
  match value {
    Object(members) => {
      let names = members.keys().collect()
      if style.sort {
        names.sort()
      }
      let mut first = true
      for name in names {
        let held = members.get(name).unwrap()
        if !first {
          out.buf.write_char('\n')
          pad(out.buf, column)
        }
        first = false
        write_text(out.buf, name, { ..style, quotes: Minimal, }, rules)
        out.buf.write_char(':')
        let anchor = if held is Object(_) || held is Array(_) {
          out.anchor(held)
        } else {
          ""
        }
        if anchor.length() > 0 && anchor[0].to_int() == 0x2a {
          out.buf.write_char(' ')
          out.buf.write_string(anchor)
          continue
        }
        if anchor.length() > 0 {
          out.buf.write_char(' ')
          out.buf.write_string(anchor)
        }
        if literal_of(held) is Some(text) {
          if anchor.length() > 0 {
            out.buf.write_char('\n')
            pad(out.buf, column + step)
          } else {
            out.buf.write_char(' ')
          }
          write_literal(out.buf, text, column + step)
        } else if inline(held) {
          out.buf.write_char(' ')
          write_inline(out.buf, held, style, rules)
        } else if style.layout is Auto &&
          fits(held, style, column + step, rules) {
          out.buf.write_char(' ')
          out.buf.write_string(flow_text(held, style, rules))
        } else if style.layout is Flow {
          out.buf.write_char(' ')
          out.buf.write_string(flow_text(held, style, rules))
        } else {
          out.buf.write_char('\n')
          pad(out.buf, column + step)
          block(out, held, column + step)
        }
      }
    }
    Array(items) => {
      let mut first = true
      for item in items {
        if !first {
          out.buf.write_char('\n')
          pad(out.buf, column)
        }
        first = false
        let anchor = if item is Object(_) || item is Array(_) {
          out.anchor(item)
        } else {
          ""
        }
        out.buf.write_string("- ")
        if anchor.length() > 0 && anchor[0].to_int() == 0x2a {
          out.buf.write_string(anchor)
          continue
        }
        if anchor.length() > 0 {
          out.buf.write_string(anchor)
          out.buf.write_char('\n')
          pad(out.buf, column + 2)
        }
        if literal_of(item) is Some(text) {
          write_literal(out.buf, text, column + 2)
        } else if inline(item) {
          write_inline(out.buf, item, style, rules)
        } else if style.layout is Auto && fits(item, style, column + 2, rules) {
          out.buf.write_string(flow_text(item, style, rules))
        } else if style.layout is Flow {
          out.buf.write_string(flow_text(item, style, rules))
        } else {
          // A nested block under a `-` begins on the same line, indented to
          // just past the dash, which is how every hand-written file does it.
          block(out, item, column + 2)
        }
      }
    }
    _ =>
      if literal_of(value) is Some(text) {
        write_literal(out.buf, text, column + step)
      } else if value is String(s) {
        write_folded(out.buf, s, column, style.width)
      } else {
        write_scalar(out.buf, value, style, rules)
      }
  }
}

///|
/// Whether a collection should be written in flow style under `Auto`: it holds
/// nothing but scalars, and the whole of it fits past `column`.
fn fits(value : Json, style : Style, column : Int32, rules : Rules) -> Bool {
  if !flat(value) {
    return false
  }
  flow_text(value, style, rules).length() + column <= style.width
}

///|
/// Whether a value is a collection of scalars, with no collection under it.
fn flat(value : Json) -> Bool {
  match value {
    Array(items) => {
      for item in items {
        if !(item is String(_) ||
          item is Number(_, ..) ||
          item is True ||
          item is False ||
          item is Null) {
          return false
        }
      }
      true
    }
    Object(members) => {
      for _, item in members {
        if !(item is String(_) ||
          item is Number(_, ..) ||
          item is True ||
          item is False ||
          item is Null) {
          return false
        }
      }
      true
    }
    _ => false
  }
}

///|
/// A value in flow style, on one line.
fn flow_text(value : Json, style : Style, rules : Rules) -> String {
  let out = StringBuilder()
  flow_into(out, value, style, rules)
  out.to_string()
}

///|
fn flow_into(
  out : StringBuilder,
  value : Json,
  style : Style,
  rules : Rules,
) -> Unit {
  match value {
    Array(items) => {
      out.write_char('[')
      let mut first = true
      for item in items {
        if !first {
          out.write_string(", ")
        }
        first = false
        flow_into(out, item, style, rules)
      }
      out.write_char(']')
    }
    Object(members) => {
      out.write_char('{')
      let names = members.keys().collect()
      if style.sort {
        names.sort()
      }
      let mut first = true
      for name in names {
        if !first {
          out.write_string(", ")
        }
        first = false
        write_text(out, name, style, rules)
        out.write_string(": ")
        flow_into(out, members.get(name).unwrap(), style, rules)
      }
      out.write_char('}')
    }
    _ => write_scalar(out, value, style, rules)
  }
}

///|
/// Write a `Json` tree as a YAML document.
///
/// Block style by default, which is what a configuration file is written in and
/// what a person reads. A string is quoted only when plain would read back as
/// something else — a number, a boolean, a null, or not at all — so the output
/// looks like a file someone wrote rather than one a program emitted.
///
/// This is the reason to have a writer at all: a generator that builds YAML by
/// joining strings gets the escaping wrong the first time a value contains a
/// colon, and gets the indentation wrong the first time a value is a list.
///
/// `style` says how; `indent` and `sort` override the two knobs that change from
/// call to call. A flat parameter wins over the record — see "Configuration" in
/// the README.
pub fn dumps(
  value : Json,
  style~ : Style = style,
  rules~ : Rules = core_rules,
  indent? : Int32,
  sort? : Bool,
) -> String {
  let style = with_flat(style, indent?, sort?)
  guard style.indent >= 1 else {
    abort("yaml: an indent of \{style.indent} would not nest anything")
  }
  let out = Out::new(style, value, rules)
  if style.layout is Flow {
    flow_into(out.buf, value, style, rules)
    out.buf.write_char('\n')
    return out.buf.to_string()
  }
  match value {
    Object(members) =>
      if members.length() == 0 {
        out.buf.write_string("{}")
      } else {
        block(out, value, 0)
      }
    Array(items) =>
      if items.length() == 0 {
        out.buf.write_string("[]")
      } else {
        block(out, value, 0)
      }
    _ =>
      if value is String(s) {
        write_folded(out.buf, s, 0, style.width)
      } else {
        write_scalar(out.buf, value, style, rules)
      }
  }
  out.buf.write_char('\n')
  out.buf.to_string()
}

///|
/// The style with the flat overrides applied.
fn with_flat(style : Style, indent? : Int32, sort? : Bool) -> Style {
  let mut out = style
  match indent {
    Some(n) => out = { ..out, indent: n, }
    None => ()
  }
  match sort {
    Some(b) => out = { ..out, sort: b, }
    None => ()
  }
  out
}

///|
/// The same, as UTF-8 bytes — the `s` on [`dumps`] is the one Python puts on
/// the form that answers a string.
pub fn dump(
  value : Json,
  style~ : Style = style,
  rules~ : Rules = core_rules,
  indent? : Int32,
  sort? : Bool,
) -> Bytes {
  @utf8.encode(dumps(value, style~, rules~, indent?, sort?)[:])
}

///|
/// A stream of documents, each opened by its own `---`.
///
/// The separator goes before each document rather than between them. The two
/// conventions are both in use — PyYAML and Go's `yaml.v3` write it only between,
/// `kubectl` writes it before each — and this takes the one that stays correct
/// under concatenation: two streams joined end to end still read as their
/// documents, and appending one is appending lines. The reader accepts either.
pub fn dumps_all(
  values : ArrayView[Json],
  style~ : Style = style,
  rules~ : Rules = core_rules,
  indent? : Int32,
  sort? : Bool,
) -> String {
  let out = StringBuilder()
  for value in values {
    out.write_string("---\n")
    out.write_string(dumps(value, style~, rules~, indent?, sort?))
  }
  out.to_string()
}

///|
/// The same, as UTF-8 bytes.
pub fn dump_all(
  values : ArrayView[Json],
  style~ : Style = style,
  rules~ : Rules = core_rules,
  indent? : Int32,
  sort? : Bool,
) -> Bytes {
  @utf8.encode(dumps_all(values, style~, rules~, indent?, sort?)[:])
}
