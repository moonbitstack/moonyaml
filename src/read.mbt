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
  mut pos : Int32
  mut line : Int32
  // Offset of the first character of the current line, so a column is a subtraction.
  mut bol : Int32
  flavor : Flavor
  // Which YAML version is reading: what a scalar resolves to, and what is
  // allowed besides. See `Schema`.
  schema : Schema
  anchors : Map[String, Json]
  // `%TAG` handle to prefix, per document (YAML 1.2.2 §6.8.2).
  handles : Map[String, String]
  // Nodes produced so far, against the alias budget.
  mut spent : Int32
  // Whether a document may begin here without a `---`. True at the start of the
  // stream and after a `...`; false once a root node has been read, which is what
  // makes a stray line after a document a fault rather than a second document.
  mut fresh : Bool
  // Whether this document has already carried a `%YAML` directive (§6.8.1 allows
  // one).
  mut versioned : Bool
}

///|
fn Reader::new(src : StringView, flavor : Flavor, schema : Schema) -> Reader {
  {
    src,
    pos: 0,
    line: 1,
    bol: 0,
    flavor,
    schema,
    anchors: Map([]),
    handles: Map([]),
    spent: 0,
    fresh: true,
    versioned: false,
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
fn Reader::cur(self : Reader) -> Int32 {
  if self.pos < self.src.length() {
    self.src[self.pos].to_int()
  } else {
    -1
  }
}

///|
/// The code unit `k` past the cursor, or `-1`.
fn Reader::ahead(self : Reader, k : Int32) -> Int32 {
  if self.pos + k < self.src.length() {
    self.src[self.pos + k].to_int()
  } else {
    -1
  }
}

///|
/// The column the cursor is in, counting from zero, which is what indentation is
/// compared against.
fn Reader::column(self : Reader) -> Int32 {
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
/// Whether a comment starts at the cursor.
///
/// A `#` only begins one at the start of a line or after a space (§6.2), so
/// `"value"#` is not a value with a comment after it but a fault — and a `#`
/// inside `foo#bar` is part of the scalar.
fn Reader::at_note(self : Reader) -> Bool {
  self.cur() == 0x23 && (self.pos == self.bol || is_blank(self.ahead(-1)))
}

///|
/// Skip a comment, if one starts here, up to but not including the line break.
fn Reader::note(self : Reader) -> Unit {
  if self.at_note() {
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
    self.at_note() ||
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
    // Content that is neither a marker nor a directive, where a document may not
    // begin, is a document that did not stop where it said it did.
    if !self.fresh && !self.at_marker() {
      raise Trailing(self.at())
    }
    match self.document() {
      Some(root) => out.push(root)
      None => ()
    }
  }
  out
}

///|
/// One document: its directives, an optional `---`, its root node, and an optional
/// `...` (§9.1.2, §9.1.3).
///
/// `None` where the stream held nothing to read — a `...` with no document before
/// it ends an empty stream, and an empty stream has no documents.
fn Reader::document(self : Reader) -> Json? raise Refused {
  self.handles.clear()
  self.anchors.clear()
  self.fresh = false
  self.versioned = false
  let mut marked = false
  let mut directed = false
  let mut inline_root = false
  for ;; {
    self.skip()
    if self.cur() == 0x25 {
      self.directive()
      directed = true
      continue
    }
    if self.marker("---") {
      marked = true
      // A node may follow on the same line — `--- |` opens a block scalar there,
      // but a block collection may not start there (§9.1.2): its keys would have
      // nowhere to line up.
      self.gap()
      inline_root = !(self.eof() || self.at_note() || self.at_break())
    }
    break
  }
  if self.cur() == 0x25 {
    // A directive may not follow the document it would belong to (§6.8.1).
    raise Trailing(self.at())
  }
  self.skip()
  if self.cur() == 0x25 {
    // A directive belongs before the document, not inside it (§6.8.1), and `%`
    // is a reserved indicator that may not begin a plain scalar (§5.3).
    raise Trailing(self.at())
  }
  if directed && !marked && (self.eof() || self.at_end_marker()) {
    // Directives without a document are a fault: a preamble to nothing.
    raise Truncated(self.at())
  }
  // Nothing at all to read: not a marker, not a directive, not a node.
  let empty = self.eof() || self.at_end_marker() || (marked && self.at_marker())
  let root = if empty {
    Json::null()
  } else {
    self.node(-1, 0, inline=inline_root)
  }
  self.skip()
  let mut ended = false
  if self.at_end_marker() {
    let _ = self.marker("...")
    // `...` ends the document and the line it is on (§9.1.1).
    self.gap()
    if !(self.eof() || self.at_note() || self.at_break()) {
      raise Unexpected(self.at(), self.printable())
    }
    self.note()
    let _ = self.brk()
    ended = true
  }
  if empty && !marked && !directed {
    // A `...` with no document before it ends an empty stream, and a stream may
    // begin again after it.
    self.fresh = ended
    return None
  }
  self.fresh = ended
  Some(root)
}

///|
/// Whether the cursor is on a line break.
fn Reader::at_break(self : Reader) -> Bool {
  self.cur() == 0x0a || self.cur() == 0x0d
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
/// version it does not know is allowed, as §6.8.1 requires. A directive name this
/// reader does not know is skipped, which §6.8.1 also requires — it is reserved for
/// a later revision, not a fault.
fn Reader::directive(self : Reader) -> Unit raise Refused {
  let at = self.at()
  self.bump()
  let name = self.until_gap()
  let mut known = true
  match name {
    "YAML" => {
      if self.versioned {
        raise Unexpected(at, '%')
      }
      self.versioned = true
      self.gap()
      let version = self.until_gap()
      match version_of(version) {
        Some((major, _)) =>
          if major != 1 {
            raise BadTag(at, "%YAML " + version)
          }
        None => raise BadTag(at, "%YAML " + version)
      }
    }
    "TAG" => {
      self.gap()
      let handle = self.until_gap()
      self.gap()
      let prefix = self.until_gap()
      if !is_handle(handle) || prefix.length() == 0 {
        raise BadTag(at, "%TAG " + handle)
      }
      self.handles[handle] = prefix
    }
    _ =>
      // A directive this reader does not know is ignored, with its parameters and
      // its comment, and the document is read as if it were not there (§6.8.1).
      known = false
  }
  if known {
    self.gap()
    if !(self.eof() || self.at_note() || self.at_break()) {
      raise Unexpected(self.at(), self.printable())
    }
  } else {
    // The rest of the line, whatever it says, is this directive's parameter.
    while !self.eof() && self.cur() != 0x0a && self.cur() != 0x0d {
      self.bump()
    }
  }
  self.note()
  let _ = self.brk()
}

///|
/// Whether a `%TAG` handle has the shape §6.8.2.2 gives it: `!`, `!!`, or `!name!`.
fn is_handle(handle : String) -> Bool {
  if handle.length() == 0 || handle[0].to_int() != 0x21 {
    return false
  }
  if handle == "!" || handle == "!!" {
    return true
  }
  handle[handle.length() - 1].to_int() == 0x21 &&
  index_of_unit(handle[1:handle.length() - 1].to_owned(), 0x21) < 0
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
fn Reader::props(
  self : Reader,
  indent : Int32,
  dedent~ : Bool = false,
) -> Props raise Refused {
  let mut anchor = None
  let mut tag = None
  let mut moved = false
  for ;; {
    if self.cur() == 0x26 {
      let at = self.at()
      if !self.schema.anchors {
        raise Disallowed(at, "an anchor")
      }
      if anchor is Some(_) {
        // A node has one anchor and one tag, at most (§6.9.1). A second one on a
        // line of its own is not this node's: it belongs to the node's content,
        // which in block context is a mapping whose first key is anchored.
        if moved {
          break
        }
        raise Unexpected(at, '&')
      }
      self.bump()
      let name = self.until_anchor()
      if name.length() == 0 {
        raise BadAnchor(at, "")
      }
      anchor = Some(name)
    } else if self.cur() == 0x21 {
      let at = self.at()
      if !self.schema.tags {
        raise Disallowed(at, "a tag")
      }
      if tag is Some(_) {
        if moved {
          break
        }
        raise Unexpected(at, '!')
      }
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
      // The node is on a following line. If that line is not indented past the
      // block this node belongs to, there is no node: the property stands for an
      // empty one, and the cursor goes back to the break so the caller can see
      // the rest of the line for what it is.
      //
      // The exception is a sequence entry in the column of the key that holds it:
      // `key: &a` then `- one` is legal (§8.2.1), and `dedent` is how the caller
      // that knows it is holding a value says so.
      let col = self.column()
      let stops = self.eof() ||
        self.at_marker() ||
        self.at_end_marker() ||
        col < indent ||
        (col == indent && !(dedent && self.at_item()))
      if stops {
        self.pos = save.0
        self.line = save.1
        self.bol = save.2
        break
      }
      moved = true
      // Another property, on its own line, is part of this node's properties.
      if self.cur() != 0x26 && self.cur() != 0x21 {
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
    return prefix_of(self.handles, "!!", self.schema.secondary) + suffix
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
  prefix_of(self.handles, "!", self.schema.primary) + body
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
fn index_of_unit(s : String, u : Int32) -> Int32 {
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
fn Reader::node(
  self : Reader,
  indent : Int32,
  depth : Int32,
  inline~ : Bool = false,
  dedent~ : Bool = false,
) -> Json raise Refused {
  if depth > self.flavor.depth {
    raise TooDeep(self.at())
  }
  self.spend(self.at())
  self.gap()
  // Where the node begins, properties included: a mapping keyed by this node
  // starts in the column the node starts in, not where its tag or anchor ended.
  let start = (self.pos, self.line, self.bol)
  let opened = self.column()
  if self.cur() == 0x2a {
    if !self.schema.anchors {
      raise Disallowed(self.at(), "an alias")
    }
    return self.refer()
  }
  let props = self.props(indent, dedent~)
  // A property may sit on a line of its own, but the node it belongs to still
  // has to be indented past the block that contains it (§6.9).
  let after = self.line
  let moved = after != start.1
  // A mapping keyed by this node starts in the column this node starts in: the
  // column of its first character, which is a property when one is written there.
  let col = if moved { self.column() } else { opened }
  // A node that moved to its own line is no longer inline: nothing on that line
  // came before it.
  let value = self.body(
    indent,
    depth,
    props.tag,
    col,
    start,
    inline && !moved,
    moved,
  )
  match props.anchor {
    Some(name) => self.anchors[name] = value
    None => ()
  }
  value
}

///|
/// A scalar as this version's schema says it is.
fn Reader::resolve(
  self : Reader,
  text : String,
  quoted : Bool,
  tag : String?,
  at : At,
) -> Json raise Refused {
  (self.schema.resolve)(text, quoted, tag, at, self.schema.rules)
}

///|
/// What a node is made of, once its properties are off.
///
/// `col` is the column the node started in, `start` where its first character was,
/// and `inline` says the node follows something else on its line — after a `key:`,
/// where a block collection may not begin.
fn Reader::body(
  self : Reader,
  indent : Int32,
  depth : Int32,
  tag : String?,
  col : Int32,
  start : (Int32, Int32, Int32),
  inline : Bool,
  moved : Bool,
) -> Json raise Refused {
  match self.cur() {
    0x2a =>
      // An alias names a node; it is not one, so it cannot be anchored or tagged.
      // It can still be the first key of the mapping this node is: `*a: 1`.
      if self.key_line() {
        return self.block_map(col, depth)
      } else {
        raise Unexpected(self.at(), '*')
      }
    0x26 | 0x21 =>
      // A property that is not this node's, on a line of its own: the mapping
      // whose first key carries it is the node.
      if self.key_line() {
        return self.block_map(col, depth)
      } else {
        raise Unexpected(self.at(), self.printable())
      }
    0x5b | 0x7b => {
      // Flow style is a YAML feature some versions do without: StrictYAML reads
      // a bracket as a plain scalar character and nothing else.
      if !self.schema.flow {
        raise Disallowed(self.at(), "flow style")
      }
      if self.cur() == 0x5b {
        self.flow_seq(indent, depth)
      } else {
        self.flow_map(indent, depth)
      }
    }
    0x7c => self.block_scalar(indent, false, tag)
    0x3e => self.block_scalar(indent, true, tag)
    _ => {
      // A `- ` here opens a block sequence; a plain or quoted token followed by
      // `: ` opens a block mapping; anything else is one scalar.
      if self.at_item() {
        if inline {
          // A block sequence may not begin on the line of the key that holds it.
          raise Unexpected(self.at(), '-')
        }
        return self.block_seq(col, depth)
      }
      if self.at_explicit_key() {
        if inline {
          raise Unexpected(self.at(), '?')
        }
        return self.block_map(col, depth)
      }
      let at = self.at()
      let own = (self.pos, self.line, self.bol)
      let own_col = self.column()
      let (text, quoted) = self.scalar_text(Mode::Block, indent)
      let tail = (self.pos, self.line, self.bol)
      self.gap()
      if self.at_value_sep() {
        if inline {
          // A block mapping may not begin on the line of the key that holds it.
          raise Unexpected(self.at(), ':')
        }
        // Back to where this pair began: a property written in front of a key is
        // part of the mapping, not part of the key.
        let back = if moved { own } else { start }
        self.pos = back.0
        self.line = back.1
        self.bol = back.2
        return self.block_map(if moved { own_col } else { col }, depth)
      }
      self.pos = tail.0
      self.line = tail.1
      self.bol = tail.2
      if self.eof() && !quoted && text.length() == 0 {
        return Json::null()
      }
      self.resolve(text, quoted, tag, at)
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
/// Whether a code unit separates tokens: a blank, a break, or a flow indicator.
fn ends_token(c : Int32) -> Bool {
  c is (0x20 | 0x09 | 0x0a | 0x0d | 0x2c | 0x5b | 0x5d | 0x7b | 0x7d | -1)
}

///|
/// Whether the cursor sits at the start of a line holding one `key: value` pair.
///
/// A lookahead, which does not move the cursor. The reader has to ask it when a
/// node turns out to carry properties that belong to its first key rather than to
/// itself: `&node` on one line and `&key k: v` on the next is a mapping whose key
/// is anchored, and nothing else.
fn Reader::key_line(self : Reader) -> Bool {
  let n = self.src.length()
  let mut i = self.pos
  // The properties a key may carry, if any.
  for ;; {
    while i < n &&
          (self.src[i].to_int() == 0x20 || self.src[i].to_int() == 0x09) {
      i = i + 1
    }
    if i < n && self.src[i].to_int() == 0x26 {
      i = i + 1
      while i < n && !ends_token(self.src[i].to_int()) {
        i = i + 1
      }
      continue
    }
    if i < n && self.src[i].to_int() == 0x21 {
      if i + 1 < n && self.src[i + 1].to_int() == 0x3c {
        i = i + 2
        while i < n &&
              self.src[i].to_int() != 0x3e &&
              self.src[i].to_int() != 0x0a {
          i = i + 1
        }
        if i < n && self.src[i].to_int() == 0x3e {
          i = i + 1
        }
      } else {
        i = i + 1
        while i < n && !ends_token(self.src[i].to_int()) {
          i = i + 1
        }
      }
      continue
    }
    break
  }
  // A quoted key is one line long, and may be followed by blanks and a `:`.
  if i < n && (self.src[i].to_int() == 0x22 || self.src[i].to_int() == 0x27) {
    let quote = self.src[i].to_int()
    i = i + 1
    let mut closed = false
    while i < n && !closed {
      let c = self.src[i].to_int()
      if c == 0x0a || c == 0x0d {
        return false
      }
      i = i + 1
      if c == 0x5c && quote == 0x22 {
        i = i + 1
      } else if c == quote {
        if quote == 0x27 && i < n && self.src[i].to_int() == 0x27 {
          i = i + 1
        } else {
          closed = true
        }
      }
    }
    if !closed {
      return false
    }
    while i < n &&
          (self.src[i].to_int() == 0x20 || self.src[i].to_int() == 0x09) {
      i = i + 1
    }
    return i < n && self.src[i].to_int() == 0x3a
  }
  // A plain key ends at a `:` that a blank or the end of the line follows. A
  // colon anywhere else is part of the key, which is how `http://a: 1` reads.
  let mut any = false
  while i < n {
    let c = self.src[i].to_int()
    if c == 0x0a || c == 0x0d {
      return false
    }
    let next = if i + 1 < n { self.src[i + 1].to_int() } else { -1 }
    if c == 0x3a && any && next is (0x20 | 0x09 | 0x0a | 0x0d | -1) {
      return true
    }
    if c == 0x23 && any && self.src[i - 1].to_int() is (0x20 | 0x09) {
      return false
    }
    any = true
    i = i + 1
  }
  false
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
fn weight(v : Json) -> Int32 {
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
  indent : Int32,
  depth : Int32,
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
      if self.column() > indent && self.tabbed() {
        raise BadIndent(self.at())
      }
      break
    }
    if self.tabbed() {
      raise BadIndent(self.at())
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
  indent : Int32,
  depth : Int32,
) -> Json raise Refused {
  if depth > self.flavor.depth {
    raise TooDeep(self.at())
  }
  let out : Map[String, Json] = Map([])
  // What a `<<` key named, and where, held until the mapping is complete: an
  // explicit key is written after the merge that names it and still wins over
  // it, so the merge cannot be applied where it is read (YAML 1.1 §7.1).
  let merges : Array[(At, Json)] = []
  for ;; {
    self.skip()
    if self.eof() || self.at_marker() || self.at_end_marker() {
      break
    }
    if self.column() != indent {
      if self.column() > indent && self.tabbed() {
        raise BadIndent(self.at())
      }
      break
    }
    if self.tabbed() {
      raise BadIndent(self.at())
    }
    let at = self.at()
    let mut key = ""
    let mut value = Json::null()
    if self.at_explicit_key() {
      self.bump()
      self.gap()
      // An explicit key may be empty: `?` alone names the null key (§8.2.2).
      let k = if self.spent_line() {
        Json::null()
      } else {
        self.node(indent, depth + 1)
      }
      self.skip()
      // The `:` of an explicit pair may be on a line of its own, in column `indent`.
      if self.column() == indent && self.at_value_sep() {
        self.bump()
        self.gap()
        // After an explicit `:` a block collection may begin on the same line —
        // `: - one` — which an implicit pair may not do (§8.2.2).
        value = if self.spent_line() {
          self.pair_value(indent, depth)
        } else {
          self.node(indent, depth + 1, dedent=true)
        }
      }
      key = key_of(k, at)
    } else {
      if self.at_item() {
        break
      }
      // A key may carry a tag or an anchor of its own (§6.9).
      let kp = self.props(indent)
      self.gap()
      if self.cur() == 0x2a {
        // An alias may name a key — it names a node, and a node may be one — but
        // it is not itself a node, so it cannot carry properties.
        if kp.anchor is Some(_) || kp.tag is Some(_) {
          raise Unexpected(self.at(), '*')
        }
        let k = self.refer()
        self.gap()
        guard self.at_value_sep() else {
          raise Unexpected(at, self.printable())
        }
        self.bump()
        key = key_of(k, at)
        value = self.pair_value(indent, depth)
      } else {
        let kline = self.line
        let (text, quoted) = self.scalar_text(Mode::Key, indent)
        if self.line != kline {
          // A key is one line; a quoted one that ran on is a fault (§7.4.2).
          raise Unexpected(self.at(), '\n')
        }
        // A quoted key keeps the space between it and its `:`, which a plain one
        // has already eaten as part of the token (§7.4.2).
        self.gap()
        guard self.at_value_sep() else {
          if text.length() == 0 &&
            !quoted &&
            kp.tag is None &&
            kp.anchor is None {
            break
          }
          raise Unexpected(at, self.printable())
        }
        self.bump()
        let k = self.resolve(text, quoted, kp.tag, at)
        match kp.anchor {
          Some(name) => self.anchors[name] = k
          None => ()
        }
        key = key_of(k, at)
        // A bare `<<` is the merge key in the versions that have one; in the
        // ones that do not, it is the string it looks like.
        if self.schema.merge && !quoted && text == "<<" {
          merges.push((at, self.pair_value(indent, depth)))
          continue
        }
        value = self.pair_value(indent, depth)
      }
    }
    match (out.get(key), self.flavor.duplicates) {
      (Some(_), First) => ()
      (Some(_), Reject) => raise Repeated(at, key)
      _ => out[key] = value
    }
  }
  Json::object(merged(out, merges))
}

///|
/// The value of a pair whose `:` is behind the cursor: on this line after the
/// gap, or on the lines under it, or nothing at all.
fn Reader::pair_value(
  self : Reader,
  indent : Int32,
  depth : Int32,
) -> Json raise Refused {
  self.gap()
  if self.spent_line() {
    self.gap()
    self.note()
    let _ = self.brk()

    self.skip()
    if self.eof() || self.at_marker() || self.at_end_marker() {
      Json::null()
    } else if self.column() > indent {
      self.node(indent, depth + 1, dedent=true)
    } else if self.column() == indent && self.at_item() {
      // A block sequence may sit in its parent key's own column (§8.2.1), which
      // is how most configuration files in the wild are written.
      self.block_seq(indent, depth + 1)
    } else {
      Json::null()
    }
  } else {
    self.node(indent, depth + 1, inline=true, dedent=true)
  }
}

///|
/// The mapping, with its merge sources folded in.
///
/// Order is part of a document: PyYAML and ruamel.yaml both put the merged keys
/// where the merge key was, with an explicit key that repeats one overriding the
/// value without moving it. Doing the same here means a document read and written
/// back keeps the shape its author wrote.
fn merged(
  out : Map[String, Json],
  merges : Array[(At, Json)],
) -> Map[String, Json] raise Refused {
  if merges.length() == 0 {
    return out
  }
  let folded = Map([])
  for (at, source) in merges {
    merge_into(folded, source, at)
  }
  let joined = Map([])
  for k, v in folded {
    joined[k] = match out.get(k) {
      Some(explicit) => explicit
      None => v
    }
  }
  for k, v in out {
    if !joined.contains(k) {
      joined[k] = v
    }
  }
  joined
}

///|
/// A merge source folded into the mapping around it (YAML 1.1 §7.1): a mapping's
/// pairs, or a sequence of mappings taken in order. A key already in the
/// mapping is left alone — that is what makes an explicit key win.
fn merge_into(
  out : Map[String, Json],
  source : Json,
  at : At,
) -> Unit raise Refused {
  match source {
    Object(fields) =>
      for k, v in fields {
        if !out.contains(k) {
          out[k] = v
        }
      }
    Array(items) =>
      for item in items {
        merge_into(out, item, at)
      }
    _ => raise Unexpected(at, '?')
  }
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
fn Reader::flow_seq(
  self : Reader,
  indent : Int32,
  depth : Int32,
) -> Json raise Refused {
  if depth > self.flavor.depth {
    raise TooDeep(self.at())
  }
  let at = self.at()
  self.bump()
  let out : Array[Json] = []
  for ;; {
    self.flow_gap(indent, 0x5d)
    if self.eof() {
      raise Truncated(at)
    }
    self.no_marker(at)
    if self.cur() == 0x5d {
      self.bump()
      break
    }
    if self.cur() == 0x2c {
      // An entry is never empty: `[, a]` and `[a, , b]` are both faults (§7.4.1).
      raise Unexpected(self.at(), ',')
    }
    if self.at_explicit_key() {
      // `? key : value` names its key explicitly, which is how a single pair may
      // have a key that runs over a line (§7.4.4).
      let kat = self.at()
      self.bump()
      self.flow_gap(indent, 0x5d)
      let key = if self.cur() is (0x3a | 0x2c | 0x5d) {
        Json::null()
      } else {
        self.flow_node(indent, depth + 1)
      }
      self.flow_gap(indent, 0x5d)
      let value = if self.cur() == 0x3a {
        self.bump()
        self.flow_gap(indent, 0x5d)
        if self.cur() is (0x2c | 0x5d) {
          Json::null()
        } else {
          self.flow_node(indent, depth + 1)
        }
      } else {
        Json::null()
      }
      let pair : Map[String, Json] = Map([(key_of(key, kat), value)])
      out.push(Json::object(pair))
    } else {
      let kline = self.line
      let mut entry = self.flow_node(indent, depth + 1)
      self.flow_gap(indent, 0x5d)
      if self.cur() == 0x3a {
        if self.line != kline {
          // An implicit key is one line long: a `:` on the line under one is a
          // fault, not a mapping the reader should guess at (§7.4.1).
          raise Unexpected(self.at(), ':')
        }
        // `[a: b]` is a one-pair mapping, which is where a block mapping would
        // have been if the sequence were not flow (§7.4.1).
        let kat = self.at()
        self.bump()
        self.flow_gap(indent, 0x5d)
        let value = if self.cur() == 0x2c || self.cur() == 0x5d {
          Json::null()
        } else {
          self.flow_node(indent, depth + 1)
        }
        let pair : Map[String, Json] = Map([(key_of(entry, kat), value)])
        entry = Json::object(pair)
        self.flow_gap(indent, 0x5d)
      }
      out.push(entry)
    }
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
/// A document marker where a flow collection is still open is a fault: `---` and
/// `...` only mean anything at the start of a line, in block context (§9.1.1).
fn Reader::no_marker(self : Reader, at : At) -> Unit raise Refused {
  if self.at_marker() || self.at_end_marker() {
    raise Unexpected(at, '-')
  }
}

///|
/// A flow mapping `{a: 1, b: 2}` (§7.4.2), which may span lines.
fn Reader::flow_map(
  self : Reader,
  indent : Int32,
  depth : Int32,
) -> Json raise Refused {
  if depth > self.flavor.depth {
    raise TooDeep(self.at())
  }
  let at = self.at()
  self.bump()
  let out : Map[String, Json] = Map([])
  let merges : Array[(At, Json)] = []
  for ;; {
    self.flow_gap(indent, 0x7d)
    if self.eof() {
      raise Truncated(at)
    }
    self.no_marker(at)
    if self.cur() == 0x7d {
      self.bump()
      break
    }
    if self.cur() == 0x2c {
      raise Unexpected(self.at(), ',')
    }
    // A bare `<<` is the merge key in the versions that have one; a quoted one
    // is the string it spells.
    if self.schema.merge && self.cur() == 0x3c && self.ahead(1) == 0x3c {
      let mat = self.at()
      self.bump()
      self.bump()
      self.flow_gap(indent, 0x7d)
      if self.cur() != 0x3a {
        raise Unexpected(self.at(), self.printable())
      }
      self.bump()
      self.flow_gap(indent, 0x7d)
      let value = if self.cur() == 0x2c || self.cur() == 0x7d {
        Json::null()
      } else {
        self.flow_node(indent, depth + 1)
      }
      merges.push((mat, value))
    } else {
      let kat = self.at()
      if self.at_explicit_key() {
        self.bump()
        self.gap()
      }
      let key = key_of(self.flow_node(indent, depth + 1), kat)
      self.flow_gap(indent, 0x7d)
      let value = if self.cur() == 0x3a {
        self.bump()
        self.flow_gap(indent, 0x7d)
        if self.cur() == 0x2c || self.cur() == 0x7d {
          Json::null()
        } else {
          self.flow_node(indent, depth + 1)
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
    }
    self.flow_gap(indent, 0x7d)
    if self.eof() {
      raise Truncated(at)
    }
    if self.cur() == 0x2c {
      self.bump()
    } else if self.cur() != 0x7d {
      raise Unexpected(self.at(), self.printable())
    }
  }
  Json::object(merged(out, merges))
}

///|
/// Skip to the next token inside a flow collection, where a line break may not
/// take the content back under the block that holds the collection (§7.4.1).
///
/// The closing bracket is exempt: it may sit in the column of the key that opened
/// the collection, which is how most files in the wild are written.
fn Reader::flow_gap(
  self : Reader,
  indent : Int32,
  close : Int32,
) -> Unit raise Refused {
  let line = self.line
  self.skip()
  if self.line != line &&
    !self.eof() &&
    self.column() <= indent &&
    self.cur() != close {
    raise BadIndent(self.at())
  }
}

///|
/// One node inside a flow collection, where indentation carries no meaning and the
/// terminators are the flow indicators.
fn Reader::flow_node(
  self : Reader,
  indent : Int32,
  depth : Int32,
) -> Json raise Refused {
  if depth > self.flavor.depth {
    raise TooDeep(self.at())
  }
  self.spend(self.at())
  self.skip()
  if self.cur() == 0x2a {
    return self.refer()
  }
  let props = self.props(-1)
  self.skip()
  let at = self.at()
  let value = match self.cur() {
    0x5b =>
      if !self.schema.flow {
        raise Disallowed(self.at(), "flow style")
      } else {
        self.flow_seq(indent, depth)
      }
    0x7b =>
      if !self.schema.flow {
        raise Disallowed(self.at(), "flow style")
      } else {
        self.flow_map(indent, depth)
      }
    _ => {
      // A property with no node behind it stands for the empty scalar: `{foo: !!str,}`
      // is a mapping whose first value is the empty string (§7.4.2).
      let empty = (props.tag is Some(_) || props.anchor is Some(_)) &&
        self.cur() is (0x2c | 0x5b | 0x5d | 0x7b | 0x7d | 0x3a | -1)
      if empty {
        self.resolve("", false, props.tag, at)
      } else {
        let (text, quoted) = self.scalar_text(Mode::Flow, -1)
        self.resolve(text, quoted, props.tag, at)
      }
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
/// Where a scalar is being read, which decides what ends it.
///
/// A `,` ends a scalar inside a flow collection and is an ordinary character in a
/// block one; a bare `[` likewise. A mapping key is one line and ends at its `: `,
/// which is neither of the other two.
priv enum Mode {
  Block
  Flow
  Key
}

///|
/// The text of a scalar at the cursor and whether it was quoted, which is what
/// decides between the string `"1"` and the number `1`.
fn Reader::scalar_text(
  self : Reader,
  mode : Mode,
  indent : Int32,
) -> (String, Bool) raise Refused {
  if self.cur() == 0x23 {
    // `#` never begins a scalar: it is a comment, or it is a fault (§6.2).
    raise Unexpected(self.at(), '#')
  }
  if self.cur() is (0x2c | 0x5d | 0x7d) {
    // Nor does a flow indicator, which only ever closes something (§7.3.3).
    raise Unexpected(self.at(), self.printable())
  }
  if mode is Flow &&
    self.cur() == 0x2d &&
    self.ahead(1) is (-1 | 0x2c | 0x5d | 0x7d) {
    // `[-]` is not a dash: a `-` followed by nothing is an indicator in search of
    // an entry.
    raise Unexpected(self.at(), '-')
  }
  match self.cur() {
    0x27 => (self.single(indent), true)
    0x22 => (self.double(indent), true)
    _ => (self.plain(mode, indent), false)
  }
}

///|
/// A single-quoted scalar (§7.3.2): the only thing it spells is a quote, doubled.
///
/// This is the form a Windows path or a regular expression is written in, because
/// a backslash in it is a backslash.
fn Reader::single(self : Reader, indent : Int32) -> String raise Refused {
  let at = self.at()
  self.bump()
  let out = StringBuilder()
  // Blanks are held back until something follows them: at the end of a line they
  // are not content, and §6.5 drops them.
  let mut blanks = ""
  for ;; {
    if self.eof() {
      raise Truncated(at)
    }
    let c = self.cur()
    if c == 0x27 {
      out.write_string(blanks)
      self.bump()
      if self.cur() == 0x27 {
        out.write_char('\'')
        self.bump()
        blanks = ""
        continue
      }
      break
    }
    if c == 0x0a || c == 0x0d {
      blanks = ""
      out.write_string(self.fold(at, indent))
      continue
    }
    if is_blank(c) {
      blanks = blanks + (if c == 0x20 { " " } else { "\t" })
      self.bump()
      continue
    }
    out.write_string(blanks)
    blanks = ""
    out.write_char(self.src[self.pos].unsafe_to_char())
    self.bump()
  }
  out.to_string()
}

///|
/// A double-quoted scalar (§7.3.1): the only form with escapes, and the only one
/// that can spell a character no other form can.
fn Reader::double(self : Reader, indent : Int32) -> String raise Refused {
  let at = self.at()
  self.bump()
  let out = StringBuilder()
  let mut blanks = ""
  for ;; {
    if self.eof() {
      raise Truncated(at)
    }
    let c = self.cur()
    if c == 0x22 {
      out.write_string(blanks)
      self.bump()
      break
    }
    if c == 0x5c {
      out.write_string(blanks)
      blanks = ""
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
      blanks = ""
      out.write_string(self.fold(at, indent))
      continue
    }
    if is_blank(c) {
      blanks = blanks + (if c == 0x20 { " " } else { "\t" })
      self.bump()
      continue
    }
    out.write_string(blanks)
    blanks = ""
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
  n : Int32,
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
fn nibble(c : Int32) -> Int32? {
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
fn Reader::fold(self : Reader, at : At, indent : Int32) -> String raise Refused {
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
  if breaks > 0 && self.column() <= indent {
    // A quoted scalar that runs on is a continuation of the node it belongs to, so
    // it has to be indented past that node's block (§7.3.1).
    raise BadIndent(self.at())
  }
  if self.at_marker() || self.at_end_marker() {
    // A quoted scalar may not swallow a document marker (§9.1.1).
    raise Unexpected(self.at(), self.printable())
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
/// comma or a bracket ends it, but it may still cross lines: a long key is often
/// written that way.
fn Reader::plain(
  self : Reader,
  mode : Mode,
  indent : Int32,
) -> String raise Refused {
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
      // `a: b: c` a fault rather than a guess. In flow context a colon is only an
      // indicator when something ends the scalar after it; `a:b` and `:x` are
      // text (§7.3.3).
      if c == 0x3a {
        let next = self.ahead(1)
        let blank = next is (-1 | 0x20 | 0x09 | 0x0a | 0x0d)
        let indicator = mode is Flow &&
          next is (0x2c | 0x5b | 0x5d | 0x7b | 0x7d)
        if blank || indicator {
          break
        }
      }
      if mode is Flow &&
        (c == 0x2c || c == 0x5b || c == 0x5d || c == 0x7b || c == 0x7d) {
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
    } else if first && mode is Flow {
      // Nothing plain starts with an indicator, and an empty entry is a fault.
      let c = self.cur()
      if c == 0x2c || c == 0x5d || c == 0x7d || c == 0x3a {
        raise Unexpected(self.at(), self.printable())
      }
    }
    // A key is one line; anything else may continue on the next.
    if mode is Key {
      break
    }
    let save = (self.pos, self.line, self.bol)
    let mut breaks = 0
    let mut commented = false
    for ;; {
      self.gap()
      if self.at_note() {
        // A comment ends the scalar; the line under it cannot continue it.
        commented = true
        break
      }
      if self.brk() {
        breaks = breaks + 1
        continue
      }
      break
    }
    if commented || breaks == 0 || self.eof() {
      self.pos = save.0
      self.line = save.1
      self.bol = save.2
      break
    }
    // A document marker at the start of a line ends the scalar, and one inside a
    // scalar is a fault: `...` means what it says wherever it appears.
    if self.at_marker() || self.at_end_marker() {
      self.pos = save.0
      self.line = save.1
      self.bol = save.2
      break
    }
    if mode is Block {
      if self.column() <= indent || self.opens_pair(indent) {
        self.pos = save.0
        self.line = save.1
        self.bol = save.2
        break
      }
    } else {
      // In flow context the scalar continues while the next line still reads as
      // text rather than as the collection's own punctuation.
      let c = self.cur()
      if c == 0x2c || c == 0x5d || c == 0x7d || c == 0x3a || self.at_note() {
        self.pos = save.0
        self.line = save.1
        self.bol = save.2
        break
      }
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
fn Reader::opens_pair(self : Reader, indent : Int32) -> Bool {
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
fn is_blank(c : Int32) -> Bool {
  c == 0x20 || c == 0x09
}

///|
/// Whether the indentation in front of the cursor holds a tab, which §5.5 does not
/// count as indentation at all: a line indented with one is a fault.
fn Reader::tabbed(self : Reader) -> Bool {
  let mut i = self.bol
  while i < self.pos {
    if self.src[i].to_int() == 0x09 {
      return true
    }
    i = i + 1
  }
  false
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
  indent : Int32,
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
  // The widest empty line seen before the content's indentation is known: §8.1.1.1
  // makes a leading empty line wider than the first content line a fault.
  let mut widest = 0
  for ;; {
    if self.eof() {
      break
    }
    if self.column() == 0 && (self.at_marker() || self.at_end_marker()) {
      // A document marker in the first column ends the scalar: at the root there is
      // no indentation to be wider than it (§9.1.1).
      break
    }
    let bol = self.pos
    let mut col = 0
    if width < 0 && self.cur() == 0x09 {
      raise BadIndent(self.at())
    }
    while self.cur() == 0x20 && (width < 0 || col < width) {
      self.bump()
      col = col + 1
    }
    if self.cur() == 0x0a || self.cur() == 0x0d {
      // An empty line: it belongs to the scalar whatever its width.
      let _ = self.brk()

      if width < 0 {
        leading = leading + 1
        if col > widest {
          widest = col
        }
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
      if col < widest {
        raise BadIndent(self.at())
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
  let mut pending = 0
  let mut more_before = false
  let mut started = false
  for i = 0; i < lines.length(); i = i + 1 {
    let line = lines[i]
    if line.length() == 0 {
      pending = pending + 1
      continue
    }
    let more = is_blank(line[0].to_int())
    if !started {
      // Leading empty lines are breaks, however many there were.
      for k = 0; k < pending; k = k + 1 {
        out.write_char('\n')
      }
      started = true
    } else if folded && pending == 0 && !more_before && !more {
      // Two ordinary lines: the break between them folds into a space (§6.5).
      out.write_char(' ')
    } else {
      // Otherwise the break stands. A blank line is itself a break, and a
      // more-indented line keeps the break that introduces it too (§8.1.3).
      let keep = if !folded {
        pending + 1
      } else if more_before || more {
        pending + 1
      } else {
        pending
      }
      for k = 0; k < keep; k = k + 1 {
        out.write_char('\n')
      }
    }
    out.write_string(line)
    more_before = more
    pending = 0
  }
  let body = out.to_string()
  let breaks = if body.length() == 0 { pending } else { pending + 1 }
  let _ = tag
  Json::string(chomped(body, breaks, chomp))
}

///|
/// The body with its trailing line breaks as the chomping indicator asks: `-` none,
/// `+` all of them, and neither exactly one (§8.1.1.2).
fn chomped(body : String, breaks : Int32, chomp : Int32) -> String {
  // Clipping keeps the final line break of the *content*; a scalar with no
  // content lines has no such break to keep, so it is empty.
  let keep = match chomp {
    -1 => 0
    1 => breaks
    _ => if breaks > 0 && body.length() > 0 { 1 } else { 0 }
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
/// A scalar as the value it denotes, under the rules the schema carries.
///
/// A quoted scalar is always a string: that is the whole point of quoting it, and
/// it is what makes `version: 1.0` a number and `version: "1.0"` a string.
///
/// This is the resolver every version in this library shares; a version differs in
/// its [`Rules`], and a dialect that differs in more than its types supplies a
/// function of its own through [`Schema::resolve`].
fn resolve_rules(
  text : String,
  quoted : Bool,
  tag : String?,
  at : At,
  rules : Rules,
) -> Json raise Refused {
  match tag {
    Some(t) => return tagged(text, t, quoted, at, rules)
    None => ()
  }
  if quoted {
    return Json::string(text)
  }
  untagged(text, rules)
}

///|
/// A scalar with no tag, resolved by what it looks like.
fn untagged(text : String, rules : Rules) -> Json {
  if rules.strings {
    // StrictYAML's rule: nothing is typed but by the schema it is read against.
    return Json::string(text)
  }
  if text.length() == 0 || text == "~" {
    return Json::null()
  }
  match text {
    "null" | "Null" | "NULL" => return Json::null()
    "true" | "True" | "TRUE" => return Json::boolean(true)
    "false" | "False" | "FALSE" => return Json::boolean(false)
    _ => ()
  }
  if rules.yes_no {
    match text {
      "yes" | "Yes" | "YES" | "on" | "On" | "ON" => return Json::boolean(true)
      "no" | "No" | "NO" | "off" | "Off" | "OFF" => return Json::boolean(false)
      _ => ()
    }
  }
  if rules.letters {
    match text {
      "y" | "Y" => return Json::boolean(true)
      "n" | "N" => return Json::boolean(false)
      _ => ()
    }
  }
  match number(text, rules) {
    Some(n) => Json::number(n)
    None => Json::string(text)
  }
}

///|
/// A scalar under an explicit tag.
///
/// The core schema's own tags are honoured. A tag from another vocabulary — a local
/// `!foo`, a `!!python/object`, an unregistered `tag:example.com,2000:app/foo` — is
/// not resolved: this reader has no constructor for it, so the scalar is what it
/// would have been without the tag. That is what §10.4 permits a processor to do,
/// and it is the only reading that does not invent a type.
fn tagged(
  text : String,
  tag : String,
  quoted : Bool,
  at : At,
  rules : Rules,
) -> Json raise Refused {
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
      // An explicit `!!bool` is a caller asking for a boolean, so every spelling
      // any version ever gave it counts — the tag removes the ambiguity the words
      // have when they are bare.
      match untagged(text, { ..rules, yes_no: true, }) {
        b if b is True || b is False => b
        _ => raise Unexpected(at, '?')
      }
    "tag:yaml.org,2002:int" | "tag:yaml.org,2002:float" =>
      match number(text, rules) {
        Some(n) => Json::number(n)
        None => raise Unexpected(at, '?')
      }
    // The non-specific tags say "whatever this looks like" and "a string".
    "!" => Json::string(text)
    "?" => untagged(text, rules)
    // `!!seq` and `!!map` name collections; a scalar cannot be one.
    "tag:yaml.org,2002:seq" | "tag:yaml.org,2002:map" => raise BadTag(at, tag)
    _ => if quoted { Json::string(text) } else { untagged(text, rules) }
  }
}

///|
/// A numeric literal under the given rules, or `None` for anything that is not
/// wholly numeric so the caller falls back to a string.
///
/// YAML 1.2's core schema (§10.2.1.2, §10.2.1.3) has decimal, `0o` octal and `0x`
/// hexadecimal integers, floats with an optional exponent, and `.inf` and `.nan` in
/// either case. The rules add what the older versions had: a `0` prefix as octal,
/// `0b` as binary, underscores as digit separators, and base-60.
fn number(s : String, rules : Rules) -> Double? {
  if s.length() == 0 {
    return None
  }
  let text = if rules.underscores { strip_underscores(s) } else { s }
  let mut i = 0
  let mut sign = 1.0
  if text[0].to_int() == 0x2d {
    sign = -1.0
    i = 1
  } else if text[0].to_int() == 0x2b {
    i = 1
  }
  if i >= text.length() {
    return None
  }
  let rest = text[i:].to_owned()
  if i == 0 {
    match rest {
      ".nan" | ".NaN" | ".NAN" => return Some(@double.not_a_number)
      _ => ()
    }
  }
  match rest {
    ".inf" | ".Inf" | ".INF" => return Some(sign * @double.infinity)
    _ => ()
  }
  if rules.sexagesimal {
    match base_sixty(rest) {
      Some(n) => return Some(sign * n)
      None => ()
    }
  }
  // `0o` and `0x` are whole integers or nothing; `0b` and a bare `0` are the older
  // spellings the rules switch on. A schema that spells octal as a leading zero is
  // older than the `0o` spelling, so it does not have it: `0o14` is a string in 1.1,
  // which is what PyYAML and libyaml make of it.
  if rest.length() > 2 && rest[0].to_int() == 0x30 {
    let radix = match rest[1].to_int() {
      0x6f | 0x4f => if rules.octal { 0 } else { 8 }
      0x78 | 0x58 => 16
      0x62 | 0x42 => if rules.binary { 2 } else { 0 }
      _ => 0
    }
    if radix != 0 {
      match digits_in(rest[2:], radix) {
        Some(n) => return Some(sign * n)
        None => return None
      }
    }
    if rules.octal && rest[1].to_int() >= 0x30 && rest[1].to_int() <= 0x37 {
      match digits_in(rest[1:], 8) {
        Some(n) => return Some(sign * n)
        None => return None
      }
    }
  }
  let mut whole = 0.0
  let mut digits = false
  while i < text.length() &&
        text[i].to_int() >= 0x30 &&
        text[i].to_int() <= 0x39 {
    whole = whole * 10.0 + (text[i].to_int() - 0x30).to_double()
    digits = true
    i = i + 1
  }
  let mut value = whole
  if i < text.length() && text[i].to_int() == 0x2e {
    i = i + 1
    let mut frac = 0.0
    let mut scale = 1.0
    while i < text.length() &&
          text[i].to_int() >= 0x30 &&
          text[i].to_int() <= 0x39 {
      frac = frac * 10.0 + (text[i].to_int() - 0x30).to_double()
      scale = scale * 10.0
      digits = true
      i = i + 1
    }
    value = value + frac / scale
  }
  if !digits {
    return None
  }
  if i < text.length() && (text[i].to_int() == 0x65 || text[i].to_int() == 0x45) {
    i = i + 1
    let mut esign = 1
    if i < text.length() &&
      (text[i].to_int() == 0x2b || text[i].to_int() == 0x2d) {
      if text[i].to_int() == 0x2d {
        esign = -1
      }
      i = i + 1
    }
    let mut exp = 0
    let mut any = false
    while i < text.length() &&
          text[i].to_int() >= 0x30 &&
          text[i].to_int() <= 0x39 {
      exp = exp * 10 + (text[i].to_int() - 0x30)
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
  if i != text.length() {
    return None
  }
  Some(sign * value)
}

///|
/// A number with its digit separators taken out.
fn strip_underscores(s : String) -> String {
  if index_of_unit(s, 0x5f) < 0 {
    return s
  }
  let out = StringBuilder()
  for i = 0; i < s.length(); i = i + 1 {
    if s[i].to_int() != 0x5f {
      out.write_char(s[i].unsafe_to_char())
    }
  }
  out.to_string()
}

///|
/// A run of digits in a radix, or `None` if there is anything else in it.
fn digits_in(s : StringView, radix : Int32) -> Double? {
  if s.length() == 0 {
    return None
  }
  let mut acc = 0.0
  for i = 0; i < s.length(); i = i + 1 {
    guard nibble(s[i].to_int()) is Some(d) else { return None }
    if d >= radix {
      return None
    }
    acc = acc * radix.to_double() + d.to_double()
  }
  Some(acc)
}

///|
/// A base-60 number of the form YAML 1.1 gives: `1:30` is ninety, `1:30:30` is five
/// thousand four hundred and thirty, and the last part may carry a fraction. The
/// parts are not restricted to two digits, which is what makes `1:234` ambiguous —
/// 1.1 resolves it as a number, and so does this.
fn base_sixty(text : String) -> Double? {
  let colon = index_of_unit(text, 0x3a)
  if colon <= 0 {
    return None
  }
  let mut total = 0.0
  let mut start = 0
  for i = 0; i <= text.length(); i = i + 1 {
    if i == text.length() || text[i].to_int() == 0x3a {
      let part = text[start:i].to_owned()
      if part.length() == 0 {
        return None
      }
      let value = if i == text.length() {
        match plain_decimal(part) {
          Some(v) => v
          None => return None
        }
      } else {
        match digits_in(part[:], 10) {
          Some(v) => v
          None => return None
        }
      }
      total = total * 60.0 + value
      start = i + 1
    }
  }
  Some(total)
}

///|
/// A decimal number, sign and fraction included, with nothing else in it.
fn plain_decimal(s : String) -> Double? {
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
  let mut value = 0.0
  let mut digits = false
  while i < s.length() && s[i].to_int() >= 0x30 && s[i].to_int() <= 0x39 {
    value = value * 10.0 + (s[i].to_int() - 0x30).to_double()
    digits = true
    i = i + 1
  }
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
  if !digits || i != s.length() {
    return None
  }
  Some(sign * value)
}
