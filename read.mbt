// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Where the reader is, and what the stream has told it so far.
///
/// The cursor is a character offset rather than a line index because YAML's block
/// scalars, multi-line flow collections and folded plain scalars all cross line
/// boundaries: a reader that splits into lines first cannot express them.
priv struct Reader {
  src : StringView
  mut pos : Int
  mut line : Int
  // Offset of the first character of the current line, so a column is a subtraction.
  mut bol : Int
  flavor : Flavor
  anchors : Map[String, Json]
  // `%TAG` handle to prefix, per document (YAML 1.2.2 §6.8.2).
  handles : Map[String, String]
  // Nodes produced so far, against the alias budget.
  mut spent : Int
}

///|
fn Reader::new(src : StringView, flavor : Flavor) -> Reader {
  {
    src,
    pos: 0,
    line: 1,
    bol: 0,
    flavor,
    anchors: Map([]),
    handles: Map([]),
    spent: 0,
  }
}

// -- the cursor ---------------------------------------------------------------

///|
fn Reader::at(self : Reader) -> At {
  { at: self.pos, line: self.line, column: self.pos - self.bol + 1, }
}

///|
fn Reader::eof(self : Reader) -> Bool {
  self.pos >= self.src.length()
}

///|
/// The code unit at the cursor, or `-1` at end of stream.
fn Reader::cur(self : Reader) -> Int {
  if self.pos < self.src.length() {
    self.src[self.pos].to_int()
  } else {
    -1
  }
}

///|
/// The code unit `k` past the cursor, or `-1`.
fn Reader::ahead(self : Reader, k : Int) -> Int {
  if self.pos + k < self.src.length() {
    self.src[self.pos + k].to_int()
  } else {
    -1
  }
}

///|
/// The column the cursor is in, counting from zero, which is what indentation is
/// compared against.
fn Reader::column(self : Reader) -> Int {
  self.pos - self.bol
}

///|
/// Advance one character, keeping the line count right.
fn Reader::bump(self : Reader) -> Unit {
  if self.pos >= self.src.length() {
    return
  }
  let c = self.src[self.pos].to_int()
  self.pos = self.pos + 1
  if c == 0x0a {
    self.line = self.line + 1
    self.bol = self.pos
  } else if c == 0x0d {
    // A lone CR ends a line too (§5.4); CRLF counts once.
    if self.cur() != 0x0a {
      self.line = self.line + 1
      self.bol = self.pos
    }
  }
}

///|
/// Consume one line break, if the cursor is on one.
fn Reader::brk(self : Reader) -> Bool {
  match self.cur() {
    0x0d => {
      self.bump()
      if self.cur() == 0x0a {
        self.bump()
      }
      true
    }
    0x0a => {
      self.bump()
      true
    }
    _ => false
  }
}

///|
/// Skip spaces and tabs, which separate tokens but never carry structure — only a
/// space counts as indentation (§5.5), and a tab where indentation is expected is
/// caught by the caller comparing columns.
fn Reader::gap(self : Reader) -> Unit {
  while self.cur() == 0x20 || self.cur() == 0x09 {
    self.bump()
  }
}

///|
/// Skip a comment, if one starts here, up to but not including the line break.
fn Reader::note(self : Reader) -> Unit {
  if self.cur() == 0x23 {
    while !self.eof() && self.cur() != 0x0a && self.cur() != 0x0d {
      self.bump()
    }
  }
}

///|
/// Skip to the first character of the next line that carries content, passing over
/// blank lines and comment-only lines. Leaves the cursor on that line's
/// indentation, so the caller reads a column.
fn Reader::skip(self : Reader) -> Unit {
  for ;; {
    self.gap()
    self.note()
    if !self.brk() {
      return
    }
  }
}

///|
/// Whether the rest of this line is blank or a comment.
fn Reader::spent_line(self : Reader) -> Bool {
  let save = (self.pos, self.line, self.bol)
  self.gap()
  let done = self.eof() ||
    self.cur() == 0x23 ||
    self.cur() == 0x0a ||
    self.cur() == 0x0d
  self.pos = save.0
  self.line = save.1
  self.bol = save.2
  done
}

// -- the stream ---------------------------------------------------------------

///|
/// Every document in the stream (§9.1), in order.
fn Reader::stream(self : Reader) -> Array[Json] raise Refused {
  let out : Array[Json] = []
  for ;; {
    self.skip()
    if self.eof() {
      break
    }
    out.push(self.document())
  }
  out
}

///|
/// One document: its directives, an optional `---`, its root node, and an optional
/// `...` (§9.1.2, §9.1.3).
fn Reader::document(self : Reader) -> Json raise Refused {
  self.handles.clear()
  self.anchors.clear()
  let mut marked = false
  for ;; {
    self.skip()
    if self.cur() == 0x25 {
      self.directive()
      continue
    }
    if self.marker("---") {
      marked = true
      self.gap()
      self.note()
      let _ = self.brk()
    }
    break
  }
  self.skip()
  // A document that is only a marker, or only directives, holds nothing.
  let root = if self.eof() ||
    self.at_end_marker() ||
    (marked && self.at_marker()) {
    Json::null()
  } else {
    self.node(-1, 0)
  }
  self.skip()
  if self.marker("...") {
    self.gap()
    self.note()
    let _ = self.brk()
  }
  root
}

///|
/// Whether a document marker — `---` or `...` — starts at the cursor, which is only
/// a marker at the start of a line and followed by a space or a line break.
fn Reader::marker(self : Reader, want : String) -> Bool {
  if self.column() != 0 {
    return false
  }
  for i = 0; i < 3; i = i + 1 {
    if self.ahead(i) != want[i].to_int() {
      return false
    }
  }
  let after = self.ahead(3)
  if after != -1 &&
    after != 0x20 &&
    after != 0x09 &&
    after != 0x0a &&
    after != 0x0d {
    return false
  }
  for i = 0; i < 3; i = i + 1 {
    self.bump()
  }
  true
}

///|
/// Whether a `---` starts here, without consuming it.
fn Reader::at_marker(self : Reader) -> Bool {
  self.column() == 0 &&
  self.ahead(0) == 0x2d &&
  self.ahead(1) == 0x2d &&
  self.ahead(2) == 0x2d &&
  self.ahead(3) is (-1 | 0x20 | 0x09 | 0x0a | 0x0d)
}

///|
/// Whether a `...` starts here, without consuming it.
fn Reader::at_end_marker(self : Reader) -> Bool {
  self.column() == 0 &&
  self.ahead(0) == 0x2e &&
  self.ahead(1) == 0x2e &&
  self.ahead(2) == 0x2e &&
  self.ahead(3) is (-1 | 0x20 | 0x09 | 0x0a | 0x0d)
}

///|
/// A `%YAML` or `%TAG` directive (§6.8).
///
/// `%YAML` is read and checked for a major version this reader speaks; a minor
/// version it does not know is allowed, as §6.8.1 requires. Any other directive is
/// refused rather than ignored: a document that asks for something unimplemented
/// should say so, not load as if it had not asked.
fn Reader::directive(self : Reader) -> Unit raise Refused {
  let at = self.at()
  self.bump()
  let name = self.until_gap()
  match name {
    "YAML" => {
      self.gap()
      let version = self.until_gap()
      if version.length() < 2 || version[0].to_int() != 0x31 {
        raise BadTag(at, "%YAML " + version)
      }
    }
    "TAG" => {
      self.gap()
      let handle = self.until_gap()
      self.gap()
      let prefix = self.until_gap()
      if handle.length() == 0 || prefix.length() == 0 {
        raise Truncated(at)
      }
      self.handles[handle] = prefix
    }
    _ => raise BadTag(at, "%" + name)
  }
  self.gap()
  self.note()
  let _ = self.brk()
}

///|
/// The run of non-space, non-break characters at the cursor.
fn Reader::until_gap(self : Reader) -> String {
  let start = self.pos
  while !self.eof() &&
        self.cur() != 0x20 &&
        self.cur() != 0x09 &&
        self.cur() != 0x0a &&
        self.cur() != 0x0d {
    self.bump()
  }
  self.src[start:self.pos].to_owned()
}

// -- nodes --------------------------------------------------------------------

///|
/// The properties a node may carry in front of it: an anchor, a tag, or both in
/// either order (§6.9).
priv struct Props {
  anchor : String?
  tag : String?
}

///|
/// Read whatever anchor and tag sit at the cursor.
fn Reader::props(self : Reader) -> Props raise Refused {
  let mut anchor = None
  let mut tag = None
  for ;; {
    if self.cur() == 0x26 {
      let at = self.at()
      self.bump()
      let name = self.until_anchor()
      if name.length() == 0 {
        raise BadAnchor(at, "")
      }
      anchor = Some(name)
    } else if self.cur() == 0x21 {
      tag = Some(self.tag())
    } else {
      break
    }
    // A property may be followed by the node on the same line or the next one.
    let save = (self.pos, self.line, self.bol)
    self.gap()
    self.note()
    if self.brk() {
      self.skip()
      if self.cur() != 0x26 && self.cur() != 0x21 {
        // The node is on a following line; hand the cursor back to the caller
        // positioned on it.
        break
      }
    } else if self.pos == save.0 {
      break
    }
  }
  { anchor, tag, }
}

///|
/// An anchor or alias name: anything up to whitespace or a flow indicator (§6.9.2).
fn Reader::until_anchor(self : Reader) -> String {
  let start = self.pos
  while !self.eof() {
    let c = self.cur()
    if c == 0x20 ||
      c == 0x09 ||
      c == 0x0a ||
      c == 0x0d ||
      c == 0x2c ||
      c == 0x5b ||
      c == 0x5d ||
      c == 0x7b ||
      c == 0x7d {
      break
    }
    self.bump()
  }
  self.src[start:self.pos].to_owned()
}

///|
/// A tag: `!`, `!local`, `!!core`, `!handle!suffix` or `!<verbatim>` (§6.8.2, §6.9.1),
/// resolved through the document's `%TAG` handles to the full tag it names.
fn Reader::tag(self : Reader) -> String raise Refused {
  let at = self.at()
  self.bump()
  if self.cur() == 0x3c {
    self.bump()
    let start = self.pos
    while !self.eof() && self.cur() != 0x3e {
      self.bump()
    }
    if self.eof() {
      raise Truncated(at)
    }
    let verbatim = self.src[start:self.pos].to_owned()
    self.bump()
    return verbatim
  }
  let start = self.pos
  while !self.eof() {
    let c = self.cur()
    if c == 0x20 ||
      c == 0x09 ||
      c == 0x0a ||
      c == 0x0d ||
      c == 0x2c ||
      c == 0x5b ||
      c == 0x5d ||
      c == 0x7b ||
      c == 0x7d {
      break
    }
    self.bump()
  }
  let body = self.src[start:self.pos].to_owned()
  // `!!x` is the secondary handle; `!h!x` a named one; `!x` the primary.
  if body.length() > 0 && body[0].to_int() == 0x21 {
    let suffix = body[1:].to_owned()
    return prefix_of(self.handles, "!!", "tag:yaml.org,2002:") + suffix
  }
  let bang = index_of_unit(body, 0x21)
  if bang >= 0 {
    let handle = "!" + body[0:bang].to_owned() + "!"
    let suffix = body[bang + 1:].to_owned()
    match self.handles.get(handle) {
      Some(p) => return p + suffix
      None => raise BadTag(at, handle)
    }
  }
  prefix_of(self.handles, "!", "!") + body
}

///|
/// The prefix a handle names, or the default when the document did not redefine it.
fn prefix_of(
  handles : Map[String, String],
  handle : String,
  fallback : String,
) -> String {
  match handles.get(handle) {
    Some(p) => p
    None => fallback
  }
}

///|
/// The index of the code unit `u` in `s`, or `-1`.
fn index_of_unit(s : String, u : Int) -> Int {
  for i = 0; i < s.length(); i = i + 1 {
    if s[i].to_int() == u {
      return i
    }
  }
  -1
}

///|
/// A node in block context, everything on it indented further than `indent`.
///
/// `depth` bounds nesting; a document that nests past the flavor's limit is refused
/// rather than driving the reader's own recursion into the ground.
fn Reader::node(self : Reader, indent : Int, depth : Int) -> Json raise Refused {
  if depth > self.flavor.depth {
    raise TooDeep(self.at())
  }
  self.spend(self.at())
  self.gap()
  if self.cur() == 0x2a {
    return self.refer()
  }
  let props = self.props()
  self.gap()
  let value = self.body(indent, depth, props.tag)
  match props.anchor {
    Some(name) => self.anchors[name] = value
    None => ()
  }
  value
}

///|
/// What a node is made of, once its properties are off.
fn Reader::body(
  self : Reader,
  indent : Int,
  depth : Int,
  tag : String?,
) -> Json raise Refused {
  match self.cur() {
    0x5b => self.flow_seq(depth)
    0x7b => self.flow_map(depth)
    0x7c => self.block_scalar(indent, false, tag)
    0x3e => self.block_scalar(indent, true, tag)
    _ => {
      // A `- ` here opens a block sequence; a plain or quoted token followed by
      // `: ` opens a block mapping; anything else is one scalar.
      if self.at_item() {
        return self.block_seq(self.column(), depth)
      }
      if self.at_explicit_key() {
        return self.block_map(self.column(), depth)
      }
      let at = self.at()
      let start = (self.pos, self.line, self.bol)
      let (text, quoted) = self.scalar_text(indent, false)
      if self.at_value_sep() {
        self.pos = start.0
        self.line = start.1
        self.bol = start.2
        return self.block_map(self.column(), depth)
      }
      if self.eof() && !quoted && text.length() == 0 {
        return Json::null()
      }
      resolve(text, quoted, tag, at)
    }
  }
}

///|
/// Whether a block sequence entry starts at the cursor: a `-` that is on its own or
/// followed by a space, rather than the start of a number like `-1`.
fn Reader::at_item(self : Reader) -> Bool {
  self.cur() == 0x2d && self.ahead(1) is (-1 | 0x20 | 0x09 | 0x0a | 0x0d)
}

///|
/// Whether an explicit key indicator `? ` starts at the cursor (§8.2.2).
fn Reader::at_explicit_key(self : Reader) -> Bool {
  self.cur() == 0x3f && self.ahead(1) is (-1 | 0x20 | 0x09 | 0x0a | 0x0d)
}

///|
/// Whether the cursor sits on the `: ` that separates a key from its value.
fn Reader::at_value_sep(self : Reader) -> Bool {
  self.cur() == 0x3a && self.ahead(1) is (-1 | 0x20 | 0x09 | 0x0a | 0x0d)
}

///|
/// An alias `*name`, which is the node its anchor named (§7.1).
///
/// The expansion is counted against the flavor's budget, because an alias may name
/// a node that itself holds aliases and a dozen lines can otherwise expand to
/// billions of them.
fn Reader::refer(self : Reader) -> Json raise Refused {
  let at = self.at()
  self.bump()
  let name = self.until_anchor()
  if !self.flavor.aliases {
    raise BadAnchor(at, name)
  }
  guard self.anchors.get(name) is Some(node) else { raise BadAnchor(at, name) }
  let n = weight(node)
  self.spent = self.spent + n
  if self.spent > self.flavor.budget {
    raise Exceeded(at~, limit=self.flavor.budget, got=self.spent)
  }
  node
}

///|
/// Charge one node against the alias budget, so a document without aliases is
/// bounded too.
fn Reader::spend(self : Reader, at : At) -> Unit raise Refused {
  self.spent = self.spent + 1
  if self.spent > self.flavor.budget {
    raise Exceeded(at~, limit=self.flavor.budget, got=self.spent)
  }
}

///|
/// How many nodes a value holds, counting itself.
fn weight(v : Json) -> Int {
  match v {
    Array(items) => {
      let mut n = 1
      for it in items {
        n = n + weight(it)
      }
      n
    }
    Object(fields) => {
      let mut n = 1
      for _, it in fields {
        n = n + weight(it)
      }
      n
    }
    _ => 1
  }
}

// -- block collections --------------------------------------------------------

///|
/// A block sequence whose `-` indicators sit in column `indent` (§8.2.1).
fn Reader::block_seq(
  self : Reader,
  indent : Int,
  depth : Int,
) -> Json raise Refused {
  if depth > self.flavor.depth {
    raise TooDeep(self.at())
  }
  let out : Array[Json] = []
  for ;; {
    self.skip()
    if self.eof() || self.at_marker() || self.at_end_marker() {
      break
    }
    if self.column() != indent || !self.at_item() {
      break
    }
    self.bump()
    // The entry's value may sit on this line, compactly nested, or on the lines
    // under it. Either way it is bounded by this sequence's own indentation.
    self.gap()
    if self.spent_line() {
      self.gap()
      self.note()
      let _ = self.brk()

      self.skip()
      if self.eof() || self.column() <= indent {
        out.push(Json::null())
        continue
      }
      out.push(self.node(indent, depth + 1))
    } else {
      out.push(self.node(indent, depth + 1))
    }
  }
  Json::array(out)
}

///|
/// A block mapping whose keys sit in column `indent` (§8.2.2).
fn Reader::block_map(
  self : Reader,
  indent : Int,
  depth : Int,
) -> Json raise Refused {
  if depth > self.flavor.depth {
    raise TooDeep(self.at())
  }
  let out : Map[String, Json] = Map([])
  for ;; {
    self.skip()
    if self.eof() || self.at_marker() || self.at_end_marker() {
      break
    }
    if self.column() != indent {
      break
    }
    let at = self.at()
    let key = if self.at_explicit_key() {
      self.bump()
      self.gap()
      let k = self.node(indent, depth + 1)
      self.skip()
      // The `:` of an explicit pair may be on a line of its own, in column `indent`.
      if self.column() == indent && self.at_value_sep() {
        self.bump()
      }
      key_of(k, at)
    } else {
      if self.at_item() {
        break
      }
      let (text, quoted) = self.scalar_text(indent, true)
      guard self.at_value_sep() else {
        if text.length() == 0 && !quoted {
          break
        }
        raise Unexpected(at, self.printable())
      }
      self.bump()
      key_of(resolve(text, quoted, None, at), at)
    }
    self.gap()
    let value = if self.spent_line() {
      self.gap()
      self.note()
      let _ = self.brk()

      self.skip()
      if self.eof() || self.at_marker() || self.at_end_marker() {
        Json::null()
      } else if self.column() > indent {
        self.node(indent, depth + 1)
      } else if self.column() == indent && self.at_item() {
        // A block sequence may sit in its parent key's own column (§8.2.1), which
        // is how most configuration files in the wild are written.
        self.block_seq(indent, depth + 1)
      } else {
        Json::null()
      }
    } else {
      self.node(indent, depth + 1)
    }
    match (out.get(key), self.flavor.duplicates) {
      (Some(_), First) => ()
      (Some(_), Reject) => raise Repeated(at, key)
      _ => out[key] = value
    }
  }
  Json::object(out)
}

///|
/// A mapping key as the string it keys by.
///
/// YAML allows any node to be a key; `Json` has only string keys, so a collection
/// used as one is refused rather than silently stringified into something no
/// caller could look up.
fn key_of(v : Json, at : At) -> String raise Refused {
  match v {
    String(s) => s
    Number(n, ..) => n.to_string()
    True => "true"
    False => "false"
    Null => "null"
    _ => raise Unexpected(at, '?')
  }
}

///|
/// The character at the cursor, for an error message.
fn Reader::printable(self : Reader) -> Char {
  if self.eof() {
    ' '
  } else {
    self.src[self.pos].unsafe_to_char()
  }
}

// -- flow collections ---------------------------------------------------------

///|
/// A flow sequence `[a, b, c]` (§7.4.1), which may span lines.
fn Reader::flow_seq(self : Reader, depth : Int) -> Json raise Refused {
  if depth > self.flavor.depth {
    raise TooDeep(self.at())
  }
  let at = self.at()
  self.bump()
  let out : Array[Json] = []
  for ;; {
    self.skip()
    if self.eof() {
      raise Truncated(at)
    }
    if self.cur() == 0x5d {
      self.bump()
      break
    }
    out.push(self.flow_node(depth + 1))
    self.skip()
    if self.eof() {
      raise Truncated(at)
    }
    if self.cur() == 0x2c {
      self.bump()
    } else if self.cur() != 0x5d {
      raise Unexpected(self.at(), self.printable())
    }
  }
  Json::array(out)
}

///|
/// A flow mapping `{a: 1, b: 2}` (§7.4.2), which may span lines.
fn Reader::flow_map(self : Reader, depth : Int) -> Json raise Refused {
  if depth > self.flavor.depth {
    raise TooDeep(self.at())
  }
  let at = self.at()
  self.bump()
  let out : Map[String, Json] = Map([])
  for ;; {
    self.skip()
    if self.eof() {
      raise Truncated(at)
    }
    if self.cur() == 0x7d {
      self.bump()
      break
    }
    let kat = self.at()
    if self.at_explicit_key() {
      self.bump()
      self.gap()
    }
    let key = key_of(self.flow_node(depth + 1), kat)
    self.skip()
    let value = if self.cur() == 0x3a {
      self.bump()
      self.skip()
      if self.cur() == 0x2c || self.cur() == 0x7d {
        Json::null()
      } else {
        self.flow_node(depth + 1)
      }
    } else {
      // `{a, b}` is a set: keys with null values (§7.4.2).
      Json::null()
    }
    match (out.get(key), self.flavor.duplicates) {
      (Some(_), First) => ()
      (Some(_), Reject) => raise Repeated(kat, key)
      _ => out[key] = value
    }
    self.skip()
    if self.eof() {
      raise Truncated(at)
    }
    if self.cur() == 0x2c {
      self.bump()
    } else if self.cur() != 0x7d {
      raise Unexpected(self.at(), self.printable())
    }
  }
  Json::object(out)
}

///|
/// One node inside a flow collection, where indentation carries no meaning and the
/// terminators are the flow indicators.
fn Reader::flow_node(self : Reader, depth : Int) -> Json raise Refused {
  if depth > self.flavor.depth {
    raise TooDeep(self.at())
  }
  self.spend(self.at())
  self.skip()
  if self.cur() == 0x2a {
    return self.refer()
  }
  let props = self.props()
  self.skip()
  let at = self.at()
  let value = match self.cur() {
    0x5b => self.flow_seq(depth)
    0x7b => self.flow_map(depth)
    _ => {
      let (text, quoted) = self.scalar_text(-1, true)
      resolve(text, quoted, props.tag, at)
    }
  }
  match props.anchor {
    Some(name) => self.anchors[name] = value
    None => ()
  }
  value
}

// -- scalars ------------------------------------------------------------------

///|
/// The text of a scalar at the cursor and whether it was quoted, which is what
/// decides between the string `"1"` and the number `1`.
///
/// `flow` says the scalar is being read where a comma or a bracket ends it, which
/// is true inside a flow collection and also of a block mapping's key.
fn Reader::scalar_text(
  self : Reader,
  indent : Int,
  flow : Bool,
) -> (String, Bool) raise Refused {
  match self.cur() {
    0x27 => (self.single(), true)
    0x22 => (self.double(), true)
    _ => (self.plain(indent, flow), false)
  }
}

///|
/// A single-quoted scalar (§7.3.2): the only thing it spells is a quote, doubled.
///
/// This is the form a Windows path or a regular expression is written in, because
/// a backslash in it is a backslash.
fn Reader::single(self : Reader) -> String raise Refused {
  let at = self.at()
  self.bump()
  let out = StringBuilder()
  for ;; {
    if self.eof() {
      raise Truncated(at)
    }
    let c = self.cur()
    if c == 0x27 {
      self.bump()
      if self.cur() == 0x27 {
        out.write_char('\'')
        self.bump()
        continue
      }
      break
    }
    if c == 0x0a || c == 0x0d {
      out.write_string(self.fold(at))
      continue
    }
    out.write_char(self.src[self.pos].unsafe_to_char())
    self.bump()
  }
  out.to_string()
}

///|
/// A double-quoted scalar (§7.3.1): the only form with escapes, and the only one
/// that can spell a character no other form can.
fn Reader::double(self : Reader) -> String raise Refused {
  let at = self.at()
  self.bump()
  let out = StringBuilder()
  for ;; {
    if self.eof() {
      raise Truncated(at)
    }
    let c = self.cur()
    if c == 0x22 {
      self.bump()
      break
    }
    if c == 0x5c {
      let eat = self.at()
      self.bump()
      // A backslash at end of line joins the two lines with no space at all,
      // which is the only way to write a long line with no break in it (§7.3.1).
      if self.cur() == 0x0a || self.cur() == 0x0d {
        let _ = self.brk()

        self.gap()
        continue
      }
      self.escape(out, eat)
      continue
    }
    if c == 0x0a || c == 0x0d {
      out.write_string(self.fold(at))
      continue
    }
    out.write_char(self.src[self.pos].unsafe_to_char())
    self.bump()
  }
  out.to_string()
}

///|
/// One escape past the backslash (§5.7).
fn Reader::escape(
  self : Reader,
  out : StringBuilder,
  at : At,
) -> Unit raise Refused {
  if self.eof() {
    raise Truncated(at)
  }
  let e = self.cur()
  self.bump()
  match e {
    0x30 => out.write_char('\u{00}')
    0x61 => out.write_char('\u{07}')
    0x62 => out.write_char('\u{08}')
    0x74 | 0x09 => out.write_char('\t')
    0x6e => out.write_char('\n')
    0x76 => out.write_char('\u{0b}')
    0x66 => out.write_char('\u{0c}')
    0x72 => out.write_char('\r')
    0x65 => out.write_char('\u{1b}')
    0x20 => out.write_char(' ')
    0x22 => out.write_char('"')
    0x2f => out.write_char('/')
    0x5c => out.write_char('\\')
    0x4e => out.write_char('\u{85}')
    0x5f => out.write_char('\u{a0}')
    0x4c => out.write_char('\u{2028}')
    0x50 => out.write_char('\u{2029}')
    0x78 => self.hex(out, 2, at)
    0x75 => self.hex(out, 4, at)
    0x55 => self.hex(out, 8, at)
    _ => raise BadEscape(at)
  }
}

///|
/// `n` hexadecimal digits as the character they name.
fn Reader::hex(
  self : Reader,
  out : StringBuilder,
  n : Int,
  at : At,
) -> Unit raise Refused {
  let mut v = 0
  for i = 0; i < n; i = i + 1 {
    guard nibble(self.cur()) is Some(d) else { raise BadEscape(at) }
    v = (v << 4) | d
    self.bump()
  }
  // A scalar escape names a code point; anything past the Unicode range, or a lone
  // surrogate, names nothing.
  if v > 0x10ffff || (v >= 0xd800 && v <= 0xdfff) {
    raise BadEscape(at)
  }
  out.write_char(v.unsafe_to_char())
}

///|
/// A hexadecimal digit's value.
fn nibble(c : Int) -> Int? {
  if c >= 0x30 && c <= 0x39 {
    Some(c - 0x30)
  } else if c >= 0x61 && c <= 0x66 {
    Some(c - 0x61 + 10)
  } else if c >= 0x41 && c <= 0x46 {
    Some(c - 0x41 + 10)
  } else {
    None
  }
}

///|
/// The line break inside a quoted or plain scalar, folded (§6.5): one break becomes
/// a space, and each break after the first stays a break.
fn Reader::fold(self : Reader, at : At) -> String raise Refused {
  let mut breaks = 0
  for ;; {
    self.gap()
    if self.brk() {
      breaks = breaks + 1
      continue
    }
    break
  }
  if self.eof() {
    raise Truncated(at)
  }
  if breaks <= 1 {
    " "
  } else {
    let out = StringBuilder()
    for i = 1; i < breaks; i = i + 1 {
      out.write_char('\n')
    }
    out.to_string()
  }
}

///|
/// A plain scalar (§7.3.3): no quotes, so no escapes, and it ends at the first
/// thing that means something else.
///
/// In block context it may run over several lines, each more indented than its
/// parent, and those breaks fold as they do in a quoted scalar. In flow context a
/// comma or a bracket ends it.
fn Reader::plain(self : Reader, indent : Int, flow : Bool) -> String {
  let out = StringBuilder()
  let mut first = true
  for ;; {
    let start = self.pos
    while !self.eof() {
      let c = self.cur()
      if c == 0x0a || c == 0x0d {
        break
      }
      // ` #` begins a comment; a `#` glued to a character is part of the value.
      if c == 0x23 && self.pos > start && is_blank(self.ahead(-1)) {
        break
      }
      if c == 0x23 && self.pos == start && !first {
        break
      }
      // `: ` ends a plain scalar wherever it appears, which is what makes
      // `a: b: c` a fault rather than a guess.
      if c == 0x3a && self.ahead(1) is (-1 | 0x20 | 0x09 | 0x0a | 0x0d) {
        break
      }
      if flow && (c == 0x2c || c == 0x5b || c == 0x5d || c == 0x7b || c == 0x7d) {
        break
      }
      if flow && c == 0x3a {
        break
      }
      self.bump()
    }
    let piece = trim_unit(self.src[start:self.pos].to_owned())
    if piece.length() > 0 {
      if !first {
        out.write_char(' ')
      }
      out.write_string(piece)
      first = false
    }
    // A plain scalar continues onto the next line only in block context, and only
    // while that line is indented past the block it belongs to.
    if flow {
      break
    }
    let save = (self.pos, self.line, self.bol)
    let mut breaks = 0
    for ;; {
      self.gap()
      self.note()
      if self.brk() {
        breaks = breaks + 1
        continue
      }
      break
    }
    if breaks == 0 ||
      self.eof() ||
      self.column() <= indent ||
      self.at_marker() ||
      self.at_end_marker() ||
      self.at_item() ||
      self.opens_pair(indent) {
      self.pos = save.0
      self.line = save.1
      self.bol = save.2
      break
    }
    if breaks > 1 {
      for i = 1; i < breaks; i = i + 1 {
        out.write_char('\n')
      }
      first = true
    }
  }
  out.to_string()
}

///|
/// Whether the line at the cursor is a `key:` line rather than the continuation of
/// a plain scalar, which is what stops a scalar from swallowing the rest of a
/// mapping.
fn Reader::opens_pair(self : Reader, indent : Int) -> Bool {
  let save = (self.pos, self.line, self.bol)
  let mut found = false
  while !self.eof() {
    let c = self.cur()
    if c == 0x0a || c == 0x0d {
      break
    }
    if c == 0x3a && self.ahead(1) is (-1 | 0x20 | 0x09 | 0x0a | 0x0d) {
      found = true
      break
    }
    self.bump()
  }
  self.pos = save.0
  self.line = save.1
  self.bol = save.2
  found && indent >= 0
}

///|
/// Whether a code unit is a space or a tab.
fn is_blank(c : Int) -> Bool {
  c == 0x20 || c == 0x09
}

///|
/// Strip leading and trailing spaces and tabs.
fn trim_unit(s : String) -> String {
  let mut a = 0
  let mut b = s.length()
  while a < b && is_blank(s[a].to_int()) {
    a = a + 1
  }
  while b > a && is_blank(s[b - 1].to_int()) {
    b = b - 1
  }
  s[a:b].to_owned()
}

// -- block scalars ------------------------------------------------------------

///|
/// A literal `|` or folded `>` block scalar (§8.1), with its chomping indicator and
/// optional explicit indentation.
///
/// This is how a shell script or a PEM certificate goes into a configuration file
/// with its line breaks intact, and it is the reason this reader works on
/// characters: the content is defined by exact leading whitespace, which a reader
/// that trimmed lines first has already thrown away.
fn Reader::block_scalar(
  self : Reader,
  indent : Int,
  folded : Bool,
  tag : String?,
) -> Json raise Refused {
  self.bump()
  // `-` strips the trailing breaks, `+` keeps them all, neither keeps one (§8.1.1.2).
  let mut chomp = 0
  let mut explicit = 0
  for ;; {
    let c = self.cur()
    if c == 0x2d {
      chomp = -1
      self.bump()
    } else if c == 0x2b {
      chomp = 1
      self.bump()
    } else if c >= 0x31 && c <= 0x39 {
      explicit = c - 0x30
      self.bump()
    } else {
      break
    }
  }
  self.gap()
  self.note()
  if !self.brk() && !self.eof() {
    raise Unexpected(self.at(), self.printable())
  }
  // The content's indentation is the first non-empty line's, unless the header said
  // otherwise; empty lines before it may be wider and do not set it.
  let mut width = if explicit > 0 { indent + explicit } else { -1 }
  let lines : Array[String] = []
  let mut leading = 0
  for ;; {
    if self.eof() {
      break
    }
    let bol = self.pos
    let mut col = 0
    while self.cur() == 0x20 && (width < 0 || col < width) {
      self.bump()
      col = col + 1
    }
    if self.cur() == 0x0a || self.cur() == 0x0d {
      // An empty line: it belongs to the scalar whatever its width.
      let _ = self.brk()

      if width < 0 {
        leading = leading + 1
      } else {
        lines.push("")
      }
      continue
    }
    if self.eof() {
      break
    }
    if width < 0 {
      if col <= indent {
        self.pos = bol
        break
      }
      width = col
      for i = 0; i < leading; i = i + 1 {
        lines.push("")
      }
      leading = 0
    } else if col < width {
      self.pos = bol
      break
    }
    let start = self.pos
    while !self.eof() && self.cur() != 0x0a && self.cur() != 0x0d {
      self.bump()
    }
    lines.push(self.src[start:self.pos].to_owned())
    let _ = self.brk()
  }
  if width < 0 {
    // Nothing but empty lines: the scalar is however many breaks chomping keeps.
    return Json::string(chomped("", leading, chomp))
  }
  let out = StringBuilder()
  let mut trailing = 0
  for i = 0; i < lines.length(); i = i + 1 {
    if lines[i].length() == 0 {
      trailing = trailing + 1
      continue
    }
    // Everything before this line's content is a break that survived.
    if i > 0 {
      if folded && trailing == 0 {
        // Folding joins two content lines with a space, unless the following one
        // is itself indented further — then it is kept as written (§8.1.3).
        if is_blank(lines[i][0].to_int()) {
          out.write_char('\n')
        } else {
          out.write_char(' ')
        }
      } else {
        for k = 0; k < (if folded { trailing } else { trailing + 1 }); k = k + 1 {
          out.write_char('\n')
        }
        if folded && trailing > 0 {
          // A folded scalar's blank lines are breaks, and the break that ended the
          // previous content line is folded away into them.
          ()
        }
      }
    }
    out.write_string(lines[i])
    trailing = 0
  }
  let body = out.to_string()
  let breaks = if body.length() == 0 { 0 } else { trailing + 1 }
  let _ = tag
  Json::string(chomped(body, breaks, chomp))
}

///|
/// The body with its trailing line breaks as the chomping indicator asks: `-` none,
/// `+` all of them, and neither exactly one (§8.1.1.2).
fn chomped(body : String, breaks : Int, chomp : Int) -> String {
  let keep = match chomp {
    -1 => 0
    1 => breaks
    _ => if breaks > 0 { 1 } else { 0 }
  }
  let out = StringBuilder()
  out.write_string(body)
  for i = 0; i < keep; i = i + 1 {
    out.write_char('\n')
  }
  out.to_string()
}

// -- resolution ---------------------------------------------------------------

///|
/// A scalar as the value it denotes, under the core schema (§10.2) and whatever tag
/// it carried.
///
/// A quoted scalar is always a string: that is the whole point of quoting it, and
/// it is what makes `version: 1.0` a number and `version: "1.0"` a string.
fn resolve(
  text : String,
  quoted : Bool,
  tag : String?,
  at : At,
) -> Json raise Refused {
  match tag {
    Some(t) => return tagged(text, t, at)
    None => ()
  }
  if quoted {
    return Json::string(text)
  }
  untagged(text)
}

///|
/// A scalar with no tag, resolved by what it looks like.
fn untagged(text : String) -> Json {
  if text.length() == 0 || text == "~" {
    return Json::null()
  }
  match text {
    "null" | "Null" | "NULL" => return Json::null()
    "true" | "True" | "TRUE" => return Json::boolean(true)
    "false" | "False" | "FALSE" => return Json::boolean(false)
    _ => ()
  }
  match number(text) {
    Some(n) => Json::number(n)
    None => Json::string(text)
  }
}

///|
/// A scalar under an explicit tag.
///
/// The core schema's tags are honoured; a tag this reader does not know is refused
/// rather than dropped, because a document that asked for a type it did not get has
/// not been read.
fn tagged(text : String, tag : String, at : At) -> Json raise Refused {
  match tag {
    "tag:yaml.org,2002:str" => Json::string(text)
    "tag:yaml.org,2002:null" =>
      if text.length() == 0 ||
        text == "~" ||
        text == "null" ||
        text == "Null" ||
        text == "NULL" {
        Json::null()
      } else {
        raise Unexpected(at, '~')
      }
    "tag:yaml.org,2002:bool" =>
      match text {
        "true" | "True" | "TRUE" | "yes" | "Yes" | "YES" | "on" | "On" | "ON" =>
          Json::boolean(true)
        "false"
        | "False"
        | "FALSE"
        | "no"
        | "No"
        | "NO"
        | "off"
        | "Off"
        | "OFF" => Json::boolean(false)
        _ => raise Unexpected(at, '?')
      }
    "tag:yaml.org,2002:int" | "tag:yaml.org,2002:float" =>
      match number(text) {
        Some(n) => Json::number(n)
        None => raise Unexpected(at, '?')
      }
    // The non-specific tags say "whatever this looks like" and "a string".
    "!" => Json::string(text)
    "?" => untagged(text)
    _ => raise BadTag(at, tag)
  }
}

///|
/// A numeric literal under the core schema (§10.2.1.2, §10.2.1.3), or `None` for
/// anything that is not wholly numeric so the caller falls back to a string.
///
/// The core schema's integers are decimal, `0o` octal and `0x` hexadecimal; its
/// floats carry an optional exponent, and `.inf` and `.nan` in either case.
fn number(s : String) -> Double? {
  if s.length() == 0 {
    return None
  }
  let mut i = 0
  let mut sign = 1.0
  if s[0].to_int() == 0x2d {
    sign = -1.0
    i = 1
  } else if s[0].to_int() == 0x2b {
    i = 1
  }
  if i >= s.length() {
    return None
  }
  let rest = s[i:].to_owned()
  match rest {
    ".inf" | ".Inf" | ".INF" => return Some(sign * @double.infinity)
    _ => ()
  }
  if i == 0 {
    match rest {
      ".nan" | ".NaN" | ".NAN" => return Some(@double.not_a_number)
      _ => ()
    }
  }
  // `0o` and `0x` are whole integers or nothing.
  if rest.length() > 2 && rest[0].to_int() == 0x30 {
    let radix = match rest[1].to_int() {
      0x6f => 8
      0x78 => 16
      _ => 0
    }
    if radix != 0 {
      let mut acc = 0.0
      for k = 2; k < rest.length(); k = k + 1 {
        guard nibble(rest[k].to_int()) is Some(d) else { return None }
        if d >= radix {
          return None
        }
        acc = acc * radix.to_double() + d.to_double()
      }
      return Some(sign * acc)
    }
  }
  let mut whole = 0.0
  let mut digits = false
  while i < s.length() && s[i].to_int() >= 0x30 && s[i].to_int() <= 0x39 {
    whole = whole * 10.0 + (s[i].to_int() - 0x30).to_double()
    digits = true
    i = i + 1
  }
  let mut value = whole
  if i < s.length() && s[i].to_int() == 0x2e {
    i = i + 1
    let mut frac = 0.0
    let mut scale = 1.0
    while i < s.length() && s[i].to_int() >= 0x30 && s[i].to_int() <= 0x39 {
      frac = frac * 10.0 + (s[i].to_int() - 0x30).to_double()
      scale = scale * 10.0
      digits = true
      i = i + 1
    }
    value = value + frac / scale
  }
  if !digits {
    return None
  }
  if i < s.length() && (s[i].to_int() == 0x65 || s[i].to_int() == 0x45) {
    i = i + 1
    let mut esign = 1
    if i < s.length() && (s[i].to_int() == 0x2b || s[i].to_int() == 0x2d) {
      if s[i].to_int() == 0x2d {
        esign = -1
      }
      i = i + 1
    }
    let mut exp = 0
    let mut any = false
    while i < s.length() && s[i].to_int() >= 0x30 && s[i].to_int() <= 0x39 {
      exp = exp * 10 + (s[i].to_int() - 0x30)
      any = true
      i = i + 1
    }
    if !any {
      return None
    }
    let mut factor = 1.0
    for k = 0; k < exp; k = k + 1 {
      factor = factor * 10.0
    }
    value = if esign < 0 { value / factor } else { value * factor }
  }
  if i != s.length() {
    return None
  }
  Some(sign * value)
}
