// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// A document as it was written, not only as it reads.
//
// `Json` is what a configuration file means: a mapping is a map, a sequence is an
// array, and there is no room in either for the comment above a key, the flow
// style a short list was written in, or the tag that says `!!set`. That is the
// right type for a program that wants the value. It is the wrong type for a tool
// that has to write the file back, which is what this file is for: a tree that
// keeps the style, the anchor, the tag and the comments, and can be written back
// as the document it came from.

///|
/// How a scalar was written.
///
/// A block scalar carries the chomping indicator that was written with it, because
/// `|` and `|-` are different strings at the end of a line.
pub(all) enum ScalarStyle {
  Plain
  Single
  Double
  Literal(Int32)
  Folded(Int32)
} derive(Eq)
// `Eq` on a public enum is only useful when the methods are methods, and saying
// so here is what the compiler now asks for instead of promoting them silently.

///|
pub extend ScalarStyle with Eq::{not_equal, equal}

///|
/// What a node is.
///
/// An alias is a node of its own rather than a copy of what it names: a document
/// with an anchor and three aliases is three references, and writing it back as
/// twelve copies would be a different document.
pub(all) enum Kind {
  Null
  Bool(Bool)
  Number(Double)
  Str(String)
  Sequence(Array[Node])
  Mapping(Array[(Node, Node)])
  Alias(String)
}

///|
/// One node of a document.
pub(all) struct Node {
  kind : Kind
  /// A scalar as it was written, before resolution: `014`, `yes`, `~`.
  ///
  /// Keeping the spelling is what makes a round trip a round trip: `014` read as
  /// twelve and written as `12` would be the same value in a different document.
  text : String
  /// How a scalar was written. Meaningless for a collection.
  style : ScalarStyle
  /// Whether a collection was written in flow style.
  flow : Bool
  anchor : String?
  tag : String?
  /// The comment lines written above this node, without their `#`.
  before : Array[String]
  /// The comment at the end of this node's last line, without its `#`.
  after : String?
}

///|
/// A plain scalar, which is how most of YAML is written.
pub fn Node::scalar(text : String) -> Node {
  {
    kind: Str(text),
    text,
    style: Plain,
    flow: false,
    anchor: None,
    tag: None,
    before: [],
    after: None,
  }
}

///|
/// A scalar of a known kind, keeping the spelling it was read from.
pub fn Node::of_kind(kind : Kind, text : String) -> Node {
  {
    kind,
    text,
    style: Plain,
    flow: false,
    anchor: None,
    tag: None,
    before: [],
    after: None,
  }
}

///|
/// A block sequence.
pub fn Node::seq(items : Array[Node]) -> Node {
  {
    kind: Sequence(items),
    text: "",
    style: Plain,
    flow: false,
    anchor: None,
    tag: None,
    before: [],
    after: None,
  }
}

///|
/// A block mapping.
pub fn Node::map(pairs : Array[(Node, Node)]) -> Node {
  {
    kind: Mapping(pairs),
    text: "",
    style: Plain,
    flow: false,
    anchor: None,
    tag: None,
    before: [],
    after: None,
  }
}

///|
/// This node, anchored.
pub fn Node::anchored(self : Node, name : String) -> Node {
  { ..self, anchor: Some(name), }
}

///|
/// This node, tagged.
pub fn Node::tagged(self : Node, tag : String) -> Node {
  { ..self, tag: Some(tag), }
}

///|
/// This node, written in flow style.
pub fn Node::in_flow(self : Node, flow : Bool) -> Node {
  { ..self, flow, }
}

///|
/// This node, with the comments written around it.
pub fn Node::commented(
  self : Node,
  before~ : Array[String],
  after~ : String,
) -> Node {
  { ..self, before, after: Some(after), }
}

///|
/// This node, written in a particular scalar style.
pub fn Node::styled(self : Node, style : ScalarStyle) -> Node {
  { ..self, style, }
}

///|
/// Whether two documents would be written the same way.
///
/// The comparison a round trip is: read, write, read again, and the second tree is
/// the first one. Positions are not in the tree, so this is equality of content.
pub fn Node::same(self : Node, other : Node) -> Bool {
  if self.text != other.text ||
    self.style != other.style ||
    self.flow != other.flow ||
    self.anchor != other.anchor ||
    self.tag != other.tag ||
    self.before != other.before ||
    self.after != other.after {
    return false
  }
  match (self.kind, other.kind) {
    (Null, Null) => true
    (Alias(a), Alias(b)) => a == b
    (Bool(a), Bool(b)) => a == b
    (Number(a), Number(b)) => a == b
    (Str(a), Str(b)) => a == b
    (Sequence(a), Sequence(b)) =>
      a.length() == b.length() &&
      ({
        let mut ok = true
        for i = 0; i < a.length(); i = i + 1 {
          if !a[i].same(b[i]) {
            ok = false
          }
        }
        ok
      })
    (Mapping(a), Mapping(b)) =>
      a.length() == b.length() &&
      ({
        let mut ok = true
        for i = 0; i < a.length(); i = i + 1 {
          if !a[i].0.same(b[i].0) || !a[i].1.same(b[i].1) {
            ok = false
          }
        }
        ok
      })
    _ => false
  }
}

// -- reading ------------------------------------------------------------------

///|
/// The comment text at the cursor, without its `#`, or the empty string.
fn Reader::dnote(self : Reader) -> String {
  if !self.at_note() {
    return ""
  }
  self.bump()
  let start = self.pos
  while !self.eof() && self.cur() != 0x0a && self.cur() != 0x0d {
    self.bump()
  }
  trim_unit(self.src[start:self.pos].to_owned())
}

///|
/// Skip blank lines, and only blank lines: a comment is content here.
fn Reader::dblank(self : Reader) -> Unit {
  for ;; {
    let save = (self.pos, self.line, self.bol)
    self.gap()
    if self.brk() {
      continue
    }
    self.pos = save.0
    self.line = save.1
    self.bol = save.2
    break
  }
}

///|
/// The comment lines between here and the next node, in order.
///
/// A blank line between a comment and the node under it does not detach the
/// comment: it is still the comment above that node, which is where a writer would
/// put it back.
fn Reader::dcomments(self : Reader) -> Array[String] {
  let out : Array[String] = []
  for ;; {
    self.gap()
    if self.at_note() {
      out.push(self.dnote())
      let _ = self.brk()
      self.dblank()
      continue
    }
    break
  }
  out
}

///|
/// The kind a scalar has, given how it was written and what tag, if any, was put
/// in front of it.
fn Reader::dkind(
  self : Reader,
  text : String,
  quoted : Bool,
  tag : String?,
  at : At,
) -> Kind raise Refused {
  match self.resolve(text, quoted, tag, at) {
    Null => Null
    True => Bool(true)
    False => Bool(false)
    Number(n, ..) => Number(n)
    String(s) => Str(s)
    _ => Str(text)
  }
}

///|
/// An alias `*name`, kept as the reference it is.
fn Reader::dalias(self : Reader) -> String raise Refused {
  let at = self.at()
  if !self.schema.anchors {
    raise Disallowed(at, "an alias")
  }
  self.bump()
  let name = self.until_anchor()
  if name.length() == 0 {
    raise BadAnchor(at, "")
  }
  name
}

///|
/// A node, with the properties and comments written around it.
fn Reader::dnode(
  self : Reader,
  indent : Int32,
  depth : Int32,
  inline~ : Bool = false,
  dedent~ : Bool = false,
  before~ : Array[String] = [],
) -> Node raise Refused {
  if depth > self.flavor.depth {
    raise TooDeep(self.at())
  }
  self.spend(self.at())
  let before = before + self.dcomments()
  self.gap()
  let start = (self.pos, self.line, self.bol)
  let opened = self.column()
  if self.cur() == 0x2a {
    let name = self.dalias()
    return {
      kind: Alias(name),
      text: "",
      style: Plain,
      flow: false,
      anchor: None,
      tag: None,
      before,
      after: None,
    }
  }
  let props = self.props(indent, dedent~)
  let moved = self.line != start.1
  let col = if moved { self.column() } else { opened }
  let node = self.dbody(
    indent,
    depth,
    props.tag,
    col,
    start,
    inline && !moved,
    moved,
    before,
  )
  match props.anchor {
    Some(name) => node.anchored(name)
    None => node
  }
}

///|
/// The content of a node, once its properties are off.
fn Reader::dbody(
  self : Reader,
  indent : Int32,
  depth : Int32,
  tag : String?,
  col : Int32,
  start : (Int32, Int32, Int32),
  inline : Bool,
  moved : Bool,
  before : Array[String],
) -> Node raise Refused {
  let at = self.at()
  let plain_of = fn(kind, text, style) -> Node {
    { kind, text, style, flow: false, anchor: None, tag, before, after: None, }
  }
  match self.cur() {
    0x5b | 0x7b => {
      if !self.schema.flow {
        raise Disallowed(at, "flow style")
      }
      let node = if self.cur() == 0x5b {
        self.dflow_seq(indent, depth)
      } else {
        self.dflow_map(indent, depth)
      }
      { ..node, before, tag, }
    }
    0x7c | 0x3e => {
      let folded = self.cur() == 0x3e
      let (text, chomp) = self.block_parts(indent, folded)
      let kind = self.dkind(text, true, tag, at)
      let style = if folded { Folded(chomp) } else { Literal(chomp) }
      plain_of(kind, text, style)
    }
    0x26 | 0x21 =>
      // A property that belongs to this node's content: a mapping whose first key
      // carries an anchor or a tag of its own.
      if self.key_line() {
        let node = self.dblock_map(col, depth)
        { ..node, before, tag, }
      } else {
        raise Unexpected(at, self.printable())
      }
    _ =>
      if self.at_item() {
        if inline {
          raise Unexpected(at, '-')
        }
        let node = self.dblock_seq(col, depth)
        { ..node, before, tag, }
      } else if self.at_explicit_key() {
        if inline {
          raise Unexpected(at, '?')
        }
        let node = self.dblock_map(col, depth)
        { ..node, before, tag, }
      } else {
        let own = (self.pos, self.line, self.bol)
        let own_col = self.column()
        let style = match self.cur() {
          0x27 => ScalarStyle::Single
          0x22 => ScalarStyle::Double
          _ => Plain
        }
        let (text, quoted) = self.scalar_text(Mode::Block, indent)
        let tail = (self.pos, self.line, self.bol)
        self.gap()
        if self.at_value_sep() {
          if inline {
            raise Unexpected(self.at(), ':')
          }
          let back = if moved { own } else { start }
          self.pos = back.0
          self.line = back.1
          self.bol = back.2
          let node = self.dblock_map(if moved { own_col } else { col }, depth)
          { ..node, before, tag, }
        } else {
          self.pos = tail.0
          self.line = tail.1
          self.bol = tail.2
          let after = self.dcomments()
          let kind = self.dkind(text, quoted, tag, at)
          {
            ..plain_of(kind, text, style),
            after: if after.length() > 0 {
              Some(after[0])
            } else {
              None
            },
          }
        }
      }
  }
}

///|
/// A block sequence, with its comments.
fn Reader::dblock_seq(
  self : Reader,
  indent : Int32,
  depth : Int32,
) -> Node raise Refused {
  if depth > self.flavor.depth {
    raise TooDeep(self.at())
  }
  let items : Array[Node] = []
  for ;; {
    let before = self.dcomments()
    self.dblank()
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
    self.gap()
    if self.spent_line() {
      self.gap()
      self.note()
      let _ = self.brk()

      self.skip()
      if self.eof() || self.column() <= indent {
        items.push({ ..Node::of_kind(Null, ""), before, })
        continue
      }
      items.push(self.dnode(indent, depth + 1, before~))
    } else {
      items.push(self.dnode(indent, depth + 1, before~))
    }
  }
  Node::seq(items)
}

///|
/// A block mapping, with its comments and its explicit keys.
fn Reader::dblock_map(
  self : Reader,
  indent : Int32,
  depth : Int32,
) -> Node raise Refused {
  if depth > self.flavor.depth {
    raise TooDeep(self.at())
  }
  let pairs : Array[(Node, Node)] = []
  let merges : Array[(At, Node)] = []
  for ;; {
    let before = self.dcomments()
    self.dblank()
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
    if self.at_explicit_key() {
      self.bump()
      self.gap()
      let key = if self.spent_line() {
        Node::of_kind(Null, "")
      } else {
        self.dnode(indent, depth + 1, before~)
      }
      self.skip()
      let value = if self.column() == indent && self.at_value_sep() {
        self.bump()
        self.gap()
        if self.spent_line() {
          self.dpair_value(indent, depth)
        } else {
          self.dnode(indent, depth + 1, dedent=true)
        }
      } else {
        Node::of_kind(Null, "")
      }
      pairs.push((key, value))
      continue
    }
    if self.at_item() {
      break
    }
    let kp = self.props(indent)
    self.gap()
    let key = if self.cur() == 0x2a {
      if kp.anchor is Some(_) || kp.tag is Some(_) {
        raise Unexpected(at, '*')
      }
      let name = self.dalias()
      { ..Node::of_kind(Alias(name), ""), before, }
    } else {
      let style = match self.cur() {
        0x27 => ScalarStyle::Single
        0x22 => ScalarStyle::Double
        _ => Plain
      }
      let (text, quoted) = self.scalar_text(Mode::Key, indent)
      if self.line != at.line {
        raise Unexpected(self.at(), '\n')
      }
      self.gap()
      guard self.at_value_sep() else {
        if text.length() == 0 && !quoted && kp.tag is None && kp.anchor is None {
          break
        }
        raise Unexpected(at, self.printable())
      }
      let kind = self.dkind(text, quoted, kp.tag, at)
      {
        kind,
        text,
        style,
        flow: false,
        anchor: kp.anchor,
        tag: kp.tag,
        before,
        after: None,
      }
    }
    self.bump()
    // A bare `<<` is the merge key in the versions that have one.
    if self.schema.merge &&
      !(key.style is Single || key.style is Double) &&
      key.text == "<<" {
      merges.push((at, self.dpair_value(indent, depth)))
      continue
    }
    let value = self.dpair_value(indent, depth)
    pairs.push((key, value))
  }
  if merges.length() > 0 {
    for pair in merged_pairs(merges) {
      pairs.push(pair)
    }
  }
  Node::map(pairs)
}

///|
/// The pairs a merge key brought in, at the place the key was.
fn merged_pairs(merges : Array[(At, Node)]) -> Array[(Node, Node)] {
  let out : Array[(Node, Node)] = []
  for (_, source) in merges {
    match source.kind {
      Mapping(pairs) =>
        for pair in pairs {
          out.push(pair)
        }
      Sequence(items) =>
        for item in items {
          match item.kind {
            Mapping(pairs) =>
              for pair in pairs {
                out.push(pair)
              }
            _ => ()
          }
        }
      _ => ()
    }
  }
  out
}

///|
/// The value of a pair whose `:` is behind the cursor.
fn Reader::dpair_value(
  self : Reader,
  indent : Int32,
  depth : Int32,
) -> Node raise Refused {
  self.gap()
  if self.spent_line() {
    self.gap()
    self.note()
    let _ = self.brk()

    self.skip()
    if self.eof() || self.at_marker() || self.at_end_marker() {
      Node::of_kind(Null, "")
    } else if self.column() > indent {
      self.dnode(indent, depth + 1, dedent=true)
    } else if self.column() == indent && self.at_item() {
      self.dblock_seq(indent, depth + 1)
    } else {
      Node::of_kind(Null, "")
    }
  } else {
    self.dnode(indent, depth + 1, inline=true, dedent=true)
  }
}

///|
/// A flow sequence.
fn Reader::dflow_seq(
  self : Reader,
  indent : Int32,
  depth : Int32,
) -> Node raise Refused {
  let at = self.at()
  self.bump()
  let items : Array[Node] = []
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
      raise Unexpected(self.at(), ',')
    }
    items.push(self.dflow_node(indent, depth + 1))
    self.flow_gap(indent, 0x5d)
    if self.cur() == 0x2c {
      self.bump()
    } else if self.cur() != 0x5d {
      raise Unexpected(self.at(), self.printable())
    }
  }
  { ..Node::seq(items), flow: true, }
}

///|
/// A flow mapping.
fn Reader::dflow_map(
  self : Reader,
  indent : Int32,
  depth : Int32,
) -> Node raise Refused {
  let at = self.at()
  self.bump()
  let pairs : Array[(Node, Node)] = []
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
    let kat = self.at()
    if self.at_explicit_key() {
      self.bump()
      self.gap()
    }
    let key = self.dflow_node(indent, depth + 1)
    self.flow_gap(indent, 0x7d)
    let value = if self.cur() == 0x3a {
      self.bump()
      self.flow_gap(indent, 0x7d)
      if self.cur() is (0x2c | 0x7d) {
        Node::of_kind(Null, "")
      } else {
        self.dflow_node(indent, depth + 1)
      }
    } else {
      Node::of_kind(Null, "")
    }
    let _ = kat
    pairs.push((key, value))
    self.flow_gap(indent, 0x7d)
    if self.cur() == 0x2c {
      self.bump()
    } else if self.cur() != 0x7d {
      raise Unexpected(self.at(), self.printable())
    }
  }
  { ..Node::map(pairs), flow: true, }
}

///|
/// One node inside a flow collection.
fn Reader::dflow_node(
  self : Reader,
  indent : Int32,
  depth : Int32,
) -> Node raise Refused {
  if depth > self.flavor.depth {
    raise TooDeep(self.at())
  }
  self.spend(self.at())
  self.flow_gap(indent, 0x00)
  if self.cur() == 0x2a {
    let name = self.dalias()
    return Node::of_kind(Alias(name), "")
  }
  let props = self.props(-1)
  self.flow_gap(indent, 0x00)
  let at = self.at()
  let node = match self.cur() {
    0x5b =>
      if !self.schema.flow {
        raise Disallowed(at, "flow style")
      } else {
        self.dflow_seq(indent, depth)
      }
    0x7b =>
      if !self.schema.flow {
        raise Disallowed(at, "flow style")
      } else {
        self.dflow_map(indent, depth)
      }
    _ => {
      let style = match self.cur() {
        0x27 => ScalarStyle::Single
        0x22 => ScalarStyle::Double
        _ => Plain
      }
      let (text, quoted) = self.scalar_text(Mode::Flow, -1)
      let kind = self.dkind(text, quoted, props.tag, at)
      {
        kind,
        text,
        style,
        flow: false,
        anchor: None,
        tag: props.tag,
        before: [],
        after: None,
      }
    }
  }
  match props.anchor {
    Some(name) => node.anchored(name)
    None => node
  }
}

///|
/// One document, as a tree.
pub fn parse(
  src : StringView,
  flavor~ : Flavor = strict,
  schema~ : Schema = core,
) -> Node raise Refused {
  parse_all(src, flavor~, schema~)[0]
}

///|
/// Every document in the stream, as trees.
pub fn parse_all(
  src : StringView,
  flavor~ : Flavor = strict,
  schema~ : Schema = core,
) -> Array[Node] raise Refused {
  let reader = Reader::new(src, flavor, schema)
  let out : Array[Node] = []
  for ;; {
    if reader.eof() {
      break
    }
    // Directives and a `---` are the frame of a document, not its content; the
    // tree keeps what a document means, and the writer puts the frame back.
    if reader.cur() == 0x25 {
      reader.directive()
      continue
    }
    if reader.at_marker() {
      let _ = reader.marker("---")
      let mut empty = true
      reader.gap()
      if !(reader.at_note() || reader.at_break() || reader.eof()) {
        empty = false
      }
      if empty {
        let _ = reader.brk()
        out.push(Node::of_kind(Null, ""))
        continue
      }
    }
    let before = reader.dcomments()
    reader.dblank()
    if reader.eof() {
      if before.length() > 0 {
        out.push({ ..Node::of_kind(Null, ""), before, })
      }
      break
    }
    out.push(reader.dnode(-1, 0, before~))
    reader.skip()
  }
  if out.length() == 0 {
    out.push(Node::of_kind(Null, ""))
  }
  out
}

// -- writing ------------------------------------------------------------------

///|
/// A single-quoted spelling of `text`.
fn dquote_single(text : String) -> String {
  let out = StringBuilder()
  out.write_char('\'')
  for i = 0; i < text.length(); i = i + 1 {
    if text[i].to_int() == 0x27 {
      out.write_char('\'')
    }
    out.write_char(text[i].unsafe_to_char())
  }
  out.write_char('\'')
  out.to_string()
}

///|
/// A double-quoted spelling of `text`, with the escapes a document needs.
fn dquote_double(text : String) -> String {
  let out = StringBuilder()
  out.write_char('"')
  for i = 0; i < text.length(); i = i + 1 {
    let c = text[i].to_int()
    if c == 0x22 {
      out.write_string("\\\"")
    } else if c == 0x5c {
      out.write_string("\\\\")
    } else if c == 0x0a {
      out.write_string("\\n")
    } else if c == 0x09 {
      out.write_string("\\t")
    } else if c == 0x0d {
      out.write_string("\\r")
    } else if c < 0x20 {
      out.write_string("\\x")
      out.write_string(hex_of(c))
    } else {
      out.write_char(text[i].unsafe_to_char())
    }
  }
  out.write_char('"')
  out.to_string()
}

///|
/// Two hexadecimal digits, lower case.
fn hex_of(c : Int32) -> String {
  let digits = "0123456789abcdef"
  let high = digits[c / 16 % 16].unsafe_to_char()
  let low = digits[c % 16].unsafe_to_char()
  "\{high}\{low}"
}

///|
/// A block scalar's body: one line of content per line, indented by `indent`.
///
/// The text is what a reader gave back, so the line breaks it holds are content.
/// A literal scalar keeps them by putting each line on its own line; a folded
/// scalar's break between two ordinary lines would read back as a space, so a
/// break the content really holds is written as an empty line (§6.5). An empty
/// line carries no indentation, so a body never ends in white space.
///
/// The body always ends with the break that closes its last content line, which
/// is also the break that starts whatever is written next — `-` is what takes
/// that break off again on the way back in, so the writer never has to skip it.
fn block_body(text : String, indent : String, folded : Bool) -> String {
  let out = StringBuilder()
  let lines = text.split("\n").to_array()
  // The break after the final content line is not part of the text.
  let mut last = lines.length() - 1
  if lines[last].length() == 0 {
    last = last - 1
  }
  let mut pending = 0
  let mut started = false
  let mut more_before = false
  for i = 0; i <= last; i = i + 1 {
    let line = lines[i]
    if line.length() == 0 {
      pending = pending + 1
      continue
    }
    let more = is_blank(line[0].to_int())
    let blanks = if folded && started && !more_before && !more {
      pending + 1
    } else {
      pending
    }
    for k = 0; k < blanks; k = k + 1 {
      out.write_char('\n')
    }
    out.write_string(indent)
    out.write_string(line.to_owned())
    out.write_char('\n')
    pending = 0
    started = true
    more_before = more
  }
  // Whatever is still pending is the trailing break a `+` keeps and a `-` strips.
  for k = 0; k < pending; k = k + 1 {
    out.write_char('\n')
  }
  out.to_string()
}

///|
/// A tag as it is written: a tag in the standard prefix keeps the `!!` shorthand
/// a reader resolves it to, a local tag is already written in full, and anything
/// else has to be spelled out between `!<` and `>`.
fn tag_text(tag : String) -> String {
  let standard = "tag:yaml.org,2002:"
  if tag.has_prefix(standard) {
    "!!" + tag[standard.length():].to_owned()
  } else if tag.has_prefix("!") {
    tag
  } else {
    "!<" + tag + ">"
  }
}

///|
/// The properties a node carries: its tag and its anchor, in that order, with a
/// single space between them and nothing at either end.
fn props_text(node : Node) -> String {
  let parts : Array[String] = []
  match node.tag {
    Some(tag) => parts.push(tag_text(tag))
    None => ()
  }
  match node.anchor {
    Some(name) => parts.push("&" + name)
    None => ()
  }
  parts.join(" ")
}

///|
/// The properties followed by the space that separates them from what they
/// describe: nothing at all when the node carries none.
fn props_prefix(node : Node) -> String {
  let text = props_text(node)
  if text.length() == 0 {
    text
  } else {
    text + " "
  }
}

///|
/// The properties written after something that already ended: nothing, or a
/// space and then the properties, so a line never ends in white space.
fn props_after(out : StringBuilder, node : Node) -> Unit {
  let text = props_text(node)
  if text.length() > 0 {
    out.write_char(' ')
    out.write_string(text)
  }
}

///|
/// A scalar on one line, in the style it was written.
fn scalar_text_of(node : Node) -> String {
  match node.style {
    Single => dquote_single(node.text)
    Double => dquote_double(node.text)
    _ =>
      if node.text.length() == 0 {
        // An empty plain scalar is written as nothing at all, which is how it read.
        ""
      } else {
        node.text
      }
  }
}

///|
/// A node that fits on one line, without its properties: a scalar, an alias, or a
/// flow collection of those. `None` means the node needs lines of its own.
fn inline_text(node : Node) -> String? {
  match node.kind {
    Sequence(items) if node.flow => {
      let parts : Array[String] = []
      for item in items {
        guard inline_text(item) is Some(text) else { return None }
        parts.push(props_prefix(item) + text)
      }
      Some("[" + parts.join(", ") + "]")
    }
    Mapping(pairs) if node.flow => {
      let parts : Array[String] = []
      for pair in pairs {
        guard inline_text(pair.0) is Some(k) else { return None }
        guard inline_text(pair.1) is Some(v) else { return None }
        parts.push(props_prefix(pair.0) + k + ": " + props_prefix(pair.1) + v)
      }
      Some("{" + parts.join(", ") + "}")
    }
    Alias(name) => Some("*" + name)
    Sequence(_) | Mapping(_) => None
    _ =>
      match node.style {
        Literal(_) | Folded(_) => None
        _ => Some(scalar_text_of(node))
      }
  }
}

///|
/// A block scalar written where the cursor is: the indicator, then the body.
///
/// The body's own indentation is part of the scalar, so `body_at` is the column
/// every line of the content starts in, and `text` keeps whatever further
/// indentation the content itself had.
fn write_block_scalar(
  out : StringBuilder,
  node : Node,
  body_at : Int32,
) -> Unit {
  let (chomp, folded) = match node.style {
    Literal(n) => (n, false)
    Folded(n) => (n, true)
    _ => (0, false)
  }
  out.write_char(if folded { '>' } else { '|' })
  out.write_string(chomp_mark(chomp))
  out.write_char('\n')
  out.write_string(block_body(node.text, spaces(body_at), folded))
}

///|
/// Emit a document as YAML, keeping the styles and comments it was read with.
///
/// `indent` is how far a nested block is indented, and `from` is how far the root
/// already is — a document embedded in another one needs the second.
pub fn emit(node : Node, indent~ : Int32 = 2, from~ : Int32 = 0) -> String {
  let out = StringBuilder()
  for comment in node.before {
    write_comment(out, comment, from)
  }
  match node.kind {
    Sequence(_) | Mapping(_) =>
      if node.flow {
        out.write_string(spaces(from))
        out.write_string(props_prefix(node))
        out.write_string(inline_text(node).unwrap_or("[]"))
        write_note(out, node)
        out.write_char('\n')
      } else {
        // A block collection's properties take a line of their own, so they
        // describe the collection rather than whatever it holds (§8.2.2).
        if props_text(node).length() > 0 {
          out.write_string(spaces(from))
          out.write_string(props_text(node))
          out.write_char('\n')
        }
        write_block(out, node, indent, from)
      }
    _ => {
      out.write_string(spaces(from))
      out.write_string(props_prefix(node))
      let mut block = false
      match node.style {
        Literal(_) | Folded(_) => {
          block = true
          write_block_scalar(out, node, from + indent)
        }
        _ => out.write_string(scalar_text_of(node))
      }
      write_note(out, node)
      if !block {
        out.write_char('\n')
      }
    }
  }
  out.to_string()
}

///|
/// The chomping indicator a block scalar was written with.
fn chomp_mark(chomp : Int32) -> String {
  if chomp < 0 {
    "-"
  } else if chomp > 0 {
    "+"
  } else {
    ""
  }
}

///|
/// `n` spaces.
fn spaces(n : Int32) -> String {
  let out = StringBuilder()
  for i = 0; i < n; i = i + 1 {
    out.write_char(' ')
  }
  out.to_string()
}

///|
/// A block collection, one entry per line, with its entries starting in column
/// `at`: the root sits at zero, and a nested block is one indent further in than
/// the key that holds it.
fn write_block(
  out : StringBuilder,
  node : Node,
  indent : Int32,
  at : Int32,
  on_dash~ : Bool = false,
) -> Unit {
  let inner = at
  let mut first = true
  match node.kind {
    Sequence(items) => {
      if items.length() == 0 {
        out.write_string(spaces(at))
        out.write_string("[]")
        out.write_char('\n')
        return
      }
      for item in items {
        for comment in item.before {
          write_comment(out, comment, inner)
        }
        out.write_string(spaces(inner))
        out.write_char('-')
        match inline_text(item) {
          Some(text) =>
            if text.length() == 0 && props_text(item).length() == 0 {
              out.write_char('\n')
            } else {
              out.write_char(' ')
              out.write_string(props_prefix(item))
              out.write_string(text)
              write_note(out, item)
              out.write_char('\n')
            }
          None =>
            match item.style {
              Literal(_) | Folded(_) => {
                // The indicator shares the `-` line and the body starts under it.
                out.write_char(' ')
                out.write_string(props_prefix(item))
                write_block_scalar(out, item, inner + indent)
              }
              _ =>
                match item.kind {
                  Sequence(_) =>
                    if props_text(item).length() == 0 {
                      // A sequence in a sequence shares the `-` line: `- - one`.
                      out.write_char(' ')
                      write_block(
                        out,
                        item,
                        indent,
                        inner + indent,
                        on_dash=true,
                      )
                    } else {
                      // Its properties take the `-` line, so the entries movein.
                      out.write_char(' ')
                      out.write_string(props_text(item))
                      out.write_char('\n')
                      write_block(out, item, indent, inner + indent)
                    }
                  Mapping(_) => {
                    // A block mapping under a `-` starts on the `-` line, which is
                    // what makes `- key: value` a list of mappings.
                    out.write_char(' ')
                    out.write_string(props_prefix(item))
                    write_block(out, item, indent, inner + indent, on_dash=true)
                  }
                  _ => {
                    out.write_char('\n')
                    block_or_scalar(out, item, indent, inner + indent)
                  }
                }
            }
        }
      }
    }
    Mapping(pairs) => {
      if pairs.length() == 0 {
        out.write_string(spaces(at))
        out.write_string("{}")
        out.write_char('\n')
        return
      }
      for pair in pairs {
        let key = pair.0
        let value = pair.1
        for comment in key.before {
          write_comment(out, comment, inner)
        }
        if first && on_dash {
          // The `-` that opened this entry is the first line's indentation.
        } else {
          out.write_string(spaces(inner))
        }
        first = false
        // A key that is a collection is written explicitly, which is the one form
        // that never leaves the reader guessing where the key ends (§8.2.2).
        let key_form = match key.kind {
          Sequence(_) | Mapping(_) => None
          _ => inline_text(key)
        }
        match key_form {
          Some(text) => {
            out.write_string(props_prefix(key))
            out.write_string(text)
            out.write_char(':')
          }
          None => {
            out.write_char('?')
            write_key(out, key, indent, inner + indent)
            out.write_string(spaces(inner))
            out.write_char(':')
          }
        }
        match inline_text(value) {
          Some(text) =>
            if text.length() == 0 && props_text(value).length() == 0 {
              write_note(out, key)
              out.write_char('\n')
            } else {
              out.write_char(' ')
              out.write_string(props_prefix(value))
              out.write_string(text)
              write_note(out, value)
              out.write_char('\n')
            }
          None =>
            match value.style {
              Literal(_) | Folded(_) => {
                // The indicator belongs on the key's line, and the body under it.
                out.write_char(' ')
                out.write_string(props_prefix(value))
                write_block_scalar(out, value, inner + indent)
              }
              _ => {
                // A block collection's properties belong on the key's line too, so
                // the anchor is the map's rather than its first key's (§8.2.1).
                props_after(out, value)
                write_note(out, key)
                out.write_char('\n')
                block_or_scalar(out, value, indent, inner + indent)
              }
            }
        }
      }
    }
    _ => ()
  }
}

///|
/// A node on lines of its own starting at column `at`, for a node whose
/// properties the caller has already written: a block collection, or a scalar
/// that cannot share a line with what introduced it.
fn block_or_scalar(
  out : StringBuilder,
  node : Node,
  indent : Int32,
  at : Int32,
) -> Unit {
  match node.kind {
    Sequence(_) | Mapping(_) =>
      if node.flow {
        out.write_string(spaces(at))
        out.write_string(inline_text(node).unwrap_or("[]"))
        write_note(out, node)
        out.write_char('\n')
      } else {
        write_block(out, node, indent, at)
      }
    _ => {
      out.write_string(spaces(at))
      let mut block = false
      match node.style {
        Literal(_) | Folded(_) => {
          block = true
          write_block_scalar(out, node, at + indent)
        }
        _ => out.write_string(scalar_text_of(node))
      }
      write_note(out, node)
      if !block {
        out.write_char('\n')
      }
    }
  }
}

///|
/// The key of an explicit pair: on the `?` line when it fits there, and on the
/// lines under it when it does not.
fn write_key(
  out : StringBuilder,
  key : Node,
  indent : Int32,
  at : Int32,
) -> Unit {
  match inline_text(key) {
    Some(text) => {
      out.write_char(' ')
      out.write_string(props_prefix(key))
      out.write_string(text)
      write_note(out, key)
      out.write_char('\n')
    }
    None => {
      props_after(out, key)
      out.write_char('\n')
      block_or_scalar(out, key, indent, at)
    }
  }
}

///|
/// A comment line at column `at`.
fn write_comment(out : StringBuilder, text : String, at : Int32) -> Unit {
  out.write_string(spaces(at))
  out.write_char('#')
  if text.length() > 0 {
    out.write_char(' ')
    out.write_string(text)
  }
  out.write_char('\n')
}

///|
/// The comment written beside `node`, if it had one.
fn write_note(out : StringBuilder, node : Node) -> Unit {
  match node.after {
    Some(note) => {
      out.write_string(" # ")
      out.write_string(note)
    }
    None => ()
  }
}

// -- the value a tree stands for -------------------------------------------------

///|
/// A key as the string a `Json` object keys it by.
///
/// `Json` has only string keys, so a mapping written with a collection as its key
/// keeps that key as the JSON text of the collection: not the same document, but
/// not a silent collision either.
fn key_string(value : Json) -> String {
  match value {
    String(s) => s
    Number(n, ..) => n.to_string()
    True => "true"
    False => "false"
    Null => "null"
    _ => value.stringify()
  }
}

///|
/// The `Json` this document denotes, with its aliases expanded.
pub fn Node::to_json(self : Node) -> Json {
  self.to_json_with(Map([]))
}

///|
/// The `Json` this node denotes, resolving aliases through `anchors`.
fn Node::to_json_with(self : Node, anchors : Map[String, Json]) -> Json {
  let value = match self.kind {
    Null => Json::null()
    Bool(b) => Json::boolean(b)
    Number(n) => Json::number(n)
    Str(s) => Json::string(s)
    Alias(name) =>
      match anchors.get(name) {
        Some(v) => v
        None => Json::null()
      }
    Sequence(items) => {
      let out : Array[Json] = []
      for item in items {
        out.push(item.to_json_with(anchors))
      }
      Json::array(out)
    }
    Mapping(pairs) => {
      let out : Map[String, Json] = Map([])
      for pair in pairs {
        let k = key_string(pair.0.to_json_with(anchors))
        out[k] = pair.1.to_json_with(anchors)
      }
      Json::object(out)
    }
  }
  match self.anchor {
    Some(name) => {
      anchors[name] = value
      value
    }
    None => value
  }
}

///|
/// A tree for a `Json` value: the document a program would write for it.
pub fn Node::of_json(value : Json) -> Node {
  match value {
    Null => Node::of_kind(Null, "")
    True => Node::of_kind(Bool(true), "true")
    False => Node::of_kind(Bool(false), "false")
    Number(n, ..) => Node::of_kind(Number(n), n.to_string())
    String(s) => Node::of_kind(Str(s), s)
    Array(items) => Node::seq(items.map(fn(item) { Node::of_json(item) }))
    Object(fields) =>
      Node::map(
        fields
        .to_array()
        .map(fn(pair) {
          (Node::of_kind(Str(pair.0), pair.0), Node::of_json(pair.1))
        }),
      )
  }
}
