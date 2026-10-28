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
  /// Nothing around it: `one`.
  Plain
  /// `'one'`, where a backslash is a backslash.
  Single
  /// `"one"`, the only form with escapes.
  Double
  /// `|` with its chomping indicator: the breaks are content, one per line.
  Literal(Int32)
  /// `>` with its chomping indicator: the breaks fold, and a blank line spells one.
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
  /// An empty node: `~`, `null`, or nothing written at all.
  Null
  /// A boolean, which only `true` and `false` are under the core schema.
  Bool(Bool)
  /// A number, held as the double it denotes.
  Number(Double)
  /// A string: everything that is not one of the above and was not tagged.
  Str(String)
  /// A sequence, in block or flow style.
  Sequence(Array[Node])
  /// A mapping, as the pairs it was written with: order is part of it, and a
  /// repeated key is kept twice.
  Mapping(Array[(Node, Node)])
  /// A reference to a node written earlier, by the anchor it was given.
  Alias(String)
}

///|
/// One node of a document.
pub(all) struct Node {
  /// What the node is.
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
  /// The `&name` the node was given, if it was given one.
  anchor : String?
  /// The tag written in front of the node, resolved through the document's
  /// `%TAG` handles — `tag:yaml.org,2002:str` rather than `!!str`.
  tag : String?
  /// The comment lines written above this node, without their `#`.
  before : Array[String]
  /// The comment at the end of this node's last line, without its `#`.
  after : String?
  /// Whether the document this node heads was opened by an explicit `---`.
  ///
  /// The markers are the frame of a document rather than its content (§9.1.1),
  /// but they are written as deliberately as anything else, and a document that
  /// had them gets them back. Both are false for every node that is not a
  /// document's root.
  explicit : Bool
  /// Whether the document was closed by an explicit `...`.
  closed : Bool
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
    explicit: false,
    closed: false,
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
    explicit: false,
    closed: false,
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
    explicit: false,
    closed: false,
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
    explicit: false,
    closed: false,
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
    self.after != other.after ||
    self.explicit != other.explicit ||
    self.closed != other.closed {
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
/// Skip the blank lines the cursor sits on, and only those: a comment is content
/// here.
///
/// The cursor ends on the first character that is not a blank — not at the start
/// of its line — because that is where the caller has to look to know how far the
/// line is indented (§8.2.1), and the indentation of the line before it says
/// nothing about it.
fn Reader::dblank(self : Reader) -> Unit {
  for ;; {
    self.gap()
    if !self.brk() {
      break
    }
  }
}

///|
/// The comments above the next node, with the blank lines between them stepped
/// over in either order.
///
/// `dcomments` stops at a blank line, which is what the caller after a value
/// needs; above a node a blank line detaches nothing, so a `# note`, a blank line
/// and then a sequence entry are still a comment on that entry.
fn Reader::dpreamble(self : Reader, before : Array[String]) -> Unit {
  for ;; {
    let at = self.pos
    for note in self.dcomments() {
      before.push(note)
    }
    self.dblank()
    if self.pos == at {
      break
    }
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
    // An alias may be the key of a pair — `*a : 1` — in which case the mapping
    // starts where the alias does (§7.1).
    if self.alias_line() {
      return { ..self.dblock_map(self.column(), depth), before, }
    }
    let name = self.dalias()
    self.gap()
    let after = if self.at_note() {
      let note = self.dnote()
      let _ = self.brk()
      Some(note)
    } else {
      None
    }
    return {
      kind: Alias(name),
      text: "",
      style: Plain,
      flow: false,
      anchor: None,
      tag: None,
      before,
      after,
      explicit: false,
      closed: false,
    }
  }
  let props = self.props(indent, dedent~)
  let moved = self.line != start.1
  let col = if moved { self.column() } else { opened }
  // A property on the line above the first key describes the mapping, and the
  // properties written on the key's own line describe the key: going back to the
  // start of that line is what lets the mapping read them there (§8.2.1).
  if props.key_line {
    let col = self.column()
    self.pos = self.bol
    let node = { ..self.dblock_map(col, depth), tag: props.tag, }
    return match props.anchor {
      Some(name) => { ..node.anchored(name), before, }
      None => { ..node, before, }
    }
  }
  // A tag or an anchor written in front of a key describes the key, not the
  // mapping it starts (§8.2.1): `!!str a: b` is a mapping whose key is a string,
  // while a property on a line of its own, above the first key, describes the
  // mapping. Going back to where the properties began is what lets the mapping
  // read them for its first key, and is why nothing is attached here.
  if !moved &&
    (props.anchor is Some(_) || props.tag is Some(_)) &&
    self.cur() != 0x5b &&
    self.cur() != 0x7b &&
    self.key_line() {
    self.pos = start.0
    self.line = start.1
    self.bol = start.2
    return { ..self.dblock_map(opened, depth), before, }
  }
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
    {
      kind,
      text,
      style,
      flow: false,
      anchor: None,
      tag,
      before,
      after: None,
      explicit: false,
      closed: false,
    }
  }
  match self.cur() {
    0x5b | 0x7b => {
      if !self.schema.flow {
        raise Disallowed(at, "flow style")
      }
      // A flow collection may be the key of a block mapping — `[a, b]: c` — and
      // then the mapping is the node, with the collection as its first key.
      if self.flow_key() {
        let node = self.dblock_map(col, depth)
        return { ..node, before, tag, }
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
          // Going back over the properties is how the first key gets them: they
          // were written in front of the key, not in front of the mapping.
          { ..node, before, tag: if moved { tag } else { None }, }
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
    let before : Array[String] = []
    self.dpreamble(before)
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
    let before : Array[String] = []
    self.dpreamble(before)
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
        // The key is on the lines under the `?`, and a sequence there may start
        // in the column of the `?` itself, which is what makes a sequence a key
        // without the indent a value would need (§8.2.2).
        self.gap()
        self.note()
        let _ = self.brk()
        self.skip()
        if self.eof() || self.at_marker() || self.at_end_marker() {
          Node::of_kind(Null, "")
        } else if self.column() == indent && self.at_item() {
          self.dblock_seq(indent, depth + 1)
        } else if self.column() > indent {
          self.dnode(indent, depth + 1, dedent=true)
        } else {
          Node::of_kind(Null, "")
        }
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
    let key = match self.dkey(indent, depth, at, kp, before) {
      Some(key) => key
      // Nothing where a key should be: the mapping ended on a line of its own.
      None => break
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
/// The key of an implicit pair, with the properties written in front of it.
///
/// A key may be a scalar, an alias, or a flow collection — `[a, b]: c` is a
/// mapping whose key is a sequence (§7.3.3, §7.4.2) — and it is one line long
/// whichever it is. `None` means the line holds no pair at all, which is where a
/// block mapping ends.
fn Reader::dkey(
  self : Reader,
  indent : Int32,
  depth : Int32,
  at : At,
  kp : Props,
  before : Array[String],
) -> Node? raise Refused {
  if self.cur() == 0x2a {
    if kp.anchor is Some(_) || kp.tag is Some(_) {
      raise Unexpected(at, '*')
    }
    let name = self.dalias()
    self.gap()
    guard self.at_value_sep() else { raise Unexpected(at, self.printable()) }
    return Some({ ..Node::of_kind(Alias(name), ""), before, })
  }
  if self.cur() == 0x5b || self.cur() == 0x7b {
    if !self.schema.flow {
      raise Disallowed(self.at(), "flow style")
    }
    let node = if self.cur() == 0x5b {
      self.dflow_seq(indent, depth + 1)
    } else {
      self.dflow_map(indent, depth + 1)
    }
    self.gap()
    guard self.at_value_sep() else { raise Unexpected(at, self.printable()) }
    return Some({ ..node, tag: kp.tag, anchor: kp.anchor, before, })
  }
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
  if !self.at_value_sep() {
    if text.length() == 0 && !quoted && kp.tag is None && kp.anchor is None {
      return None
    }
    raise Unexpected(at, self.printable())
  }
  let kind = self.dkind(text, quoted, kp.tag, at)
  Some({
    kind,
    text,
    style,
    flow: false,
    anchor: kp.anchor,
    tag: kp.tag,
    before,
    after: None,
    explicit: false,
    closed: false,
  })
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
/// A flow sequence, whose entries may each be a single pair of its own.
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
    if self.at_explicit_key() {
      // `[? key : value]` is a single pair written out, which is a one-pair
      // mapping like any other (§7.4.4).
      self.bump()
      self.flow_gap(indent, 0x5d)
      let key = if self.cur() is (0x3a | 0x2c | 0x5d) {
        Node::of_kind(Null, "")
      } else {
        self.dflow_node(indent, depth + 1)
      }
      self.flow_gap(indent, 0x5d)
      let value = if self.cur() == 0x3a {
        self.bump()
        self.flow_gap(indent, 0x5d)
        if self.cur() is (0x2c | 0x5d) {
          Node::of_kind(Null, "")
        } else {
          self.dflow_node(indent, depth + 1)
        }
      } else {
        Node::of_kind(Null, "")
      }
      items.push({ ..Node::map([(key, value)]), flow: true, })
      self.flow_gap(indent, 0x5d)
    } else if self.at_empty_key() {
      // `[: value]` is a single pair whose key was not written (§7.4.1).
      self.bump()
      self.flow_gap(indent, 0x5d)
      let value = if self.cur() is (0x2c | 0x5d) {
        Node::of_kind(Null, "")
      } else {
        self.dflow_node(indent, depth + 1)
      }
      items.push({
        ..Node::map([(Node::of_kind(Null, ""), value)]),
        flow: true,
      })
      self.flow_gap(indent, 0x5d)
    } else {
      let kline = self.line
      let mut entry = self.dflow_node(indent, depth + 1)
      self.flow_gap(indent, 0x5d)
      // `[a: b]` is a one-pair mapping, which is where a block mapping would have
      // been if the sequence were not flow, and its key is one line long (§7.4.1).
      if self.cur() == 0x3a && self.line == kline {
        self.bump()
        self.flow_gap(indent, 0x5d)
        let value = if self.cur() is (0x2c | 0x5d) {
          Node::of_kind(Null, "")
        } else {
          self.dflow_node(indent, depth + 1)
        }
        entry = { ..Node::map([(entry, value)]), flow: true, }
        self.flow_gap(indent, 0x5d)
      }
      items.push(entry)
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
    // `? ` introduces an explicit key, and `: ` on its own a key that was not
    // written: both are pairs with an empty side (§7.4.2).
    if self.at_explicit_key() {
      self.bump()
      self.flow_gap(indent, 0x7d)
    }
    let key = if self.cur() is (0x2c | 0x7d) || self.at_empty_key() {
      Node::of_kind(Null, "")
    } else {
      self.dflow_node(indent, depth + 1)
    }
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
      // `{a, b}` is a set: keys with empty values (§7.4.2).
      Node::of_kind(Null, "")
    }
    pairs.push((key, value))
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
        // A tag describes the collection whether or not anything is in it, so it
        // belongs on the node the collection makes (§6.9.1).
        let node = self.dflow_seq(indent, depth)
        { ..node, tag: props.tag, }
      }
    0x7b =>
      if !self.schema.flow {
        raise Disallowed(at, "flow style")
      } else {
        let node = self.dflow_map(indent, depth)
        { ..node, tag: props.tag, }
      }
    _ => {
      // A property with no node behind it stands for the empty scalar:
      // `{foo: !!str,}` is a mapping whose value is the empty string (§7.4.2).
      let bare = (props.tag is Some(_) || props.anchor is Some(_)) &&
        self.cur() is (0x2c | 0x5b | 0x5d | 0x7b | 0x7d | 0x3a | -1)
      if bare {
        let kind = self.dkind("", false, props.tag, at)
        return match props.anchor {
          Some(name) =>
            { ..Node::of_kind(kind, "").anchored(name), tag: props.tag, }
          None => { ..Node::of_kind(kind, ""), tag: props.tag, }
        }
      }
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
        explicit: false,
        closed: false,
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
  let docs = parse_all(src, flavor~, schema~)
  if docs.length() == 0 {
    Node::of_kind(Null, "")
  } else {
    docs[0]
  }
}

///|
/// Every document in the stream, as trees.
///
/// A stream with nothing in it holds no document, which is what `loads_all` says
/// too; `parse` is where a single document is owed, and it gives the null one.
pub fn parse_all(
  src : StringView,
  flavor~ : Flavor = strict,
  schema~ : Schema = core,
) -> Array[Node] raise Refused {
  let reader = Reader::new(src, flavor, schema)
  let out : Array[Node] = []
  let mut last = -1
  for ;; {
    if reader.eof() {
      break
    }
    // Every turn of this loop has to consume something, or a document that reads
    // as nothing would spin here for ever.
    if reader.pos == last {
      raise Unexpected(reader.at(), reader.printable())
    }
    last = reader.pos
    // A document's directives and anchors are its own: `%TAG` and `%YAML` are
    // read again for the next one (§6.8.1), and an alias does not reach past a
    // `...`.
    reader.handles.clear()
    reader.anchors.clear()
    reader.versioned = false
    // The frame of a stream — directives, `---`, `...`, comments and blank lines —
    // is not its content: a tree keeps what a document says, and the writer puts
    // the frame back from it. They may come in any order (§9.1.1), so they are
    // read in one loop, and what a `---` opened is decided where it ends.
    let mut marked = false
    let before : Array[String] = []
    let mut open = true
    while open {
      if reader.cur() == 0x25 {
        reader.directive()
        continue
      }
      if reader.at_marker() {
        // A second `---` before any content closes an empty document.
        if marked {
          out.push({ ..Node::of_kind(Null, ""), before, explicit: true, })
        }
        let _ = reader.marker("---")
        marked = true
        reader.gap()
        if !(reader.eof() || reader.at_note() || reader.at_break()) {
          // A node on the marker's own line: `--- "foo"` is a document.
          open = false
        }
        continue
      }
      if reader.at_end_marker() {
        let _ = reader.marker("...")
        reader.gap()
        if reader.at_note() {
          let _ = reader.dnote()
        }
        let _ = reader.brk()
        // A `---` that closed before it held anything held an empty document.
        if marked {
          out.push({
            ..Node::of_kind(Null, ""),
            before,
            explicit: true,
            closed: true,
          })
          marked = false
        }
        continue
      }
      let notes = reader.dcomments()
      let at = reader.pos
      for note in notes {
        before.push(note)
      }
      reader.dblank()
      if reader.pos != at || notes.length() > 0 {
        continue
      }
      open = false
    }
    if reader.eof() {
      // A stream that ends on its frame holds whatever the frame opened: a `---`
      // holds an empty document, and comments on their own hold nothing at all —
      // a comment is not a document, and a tree that invented one for it would
      // disagree with the value the same stream denotes.
      if marked {
        out.push({ ..Node::of_kind(Null, ""), before, explicit: true, })
      }
      break
    }
    let root = reader.dnode(-1, 0, before~)
    reader.skip()
    let mut closed = false
    if reader.at_end_marker() {
      let _ = reader.marker("...")
      reader.gap()
      if reader.at_note() {
        let _ = reader.dnote()
      }
      let _ = reader.brk()
      closed = true
    }
    out.push({ ..root, explicit: marked, closed, })
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
/// Whether the first line of `text` that holds anything starts with a space, which
/// is the case a block scalar needs an explicit indentation indicator for.
fn starts_indented(text : String) -> Bool {
  for i = 0; i < text.length(); i = i + 1 {
    let c = text[i].to_int()
    if c == 0x0a {
      continue
    }
    return c == 0x20
  }
  false
}

///|
/// `text` with each break it holds spelled as the blank lines that fold back into
/// it, continuing at column `at`.
///
/// One break between two lines of a plain or quoted scalar folds to a space, so a
/// break the text really holds has to be written as two (§6.5). A run of `k`
/// breaks becomes `k + 1`.
fn folded_text(text : String, at : Int32) -> String {
  if index_of_unit(text, 0x0a) < 0 {
    return text
  }
  let out = StringBuilder()
  let mut i = 0
  while i < text.length() {
    if text[i].to_int() == 0x0a {
      let mut k = 0
      while i < text.length() && text[i].to_int() == 0x0a {
        k = k + 1
        i = i + 1
      }
      for _ in 0..<(k + 1) {
        out.write_char('\n')
      }
      if i < text.length() {
        out.write_string(spaces(at))
      }
      continue
    }
    out.write_char(text[i].unsafe_to_char())
    i = i + 1
  }
  out.to_string()
}

///|
/// A scalar as it is written in block context, continuing at column `at` when its
/// text holds a break.
fn scalar_written(node : Node, at : Int32) -> String {
  match node.style {
    Single => folded_text(dquote_single(node.text), at)
    Double => dquote_double(node.text)
    _ => if node.text.length() == 0 { "" } else { folded_text(node.text, at) }
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
        let sep = if pair.0.kind is Alias(_) { " : " } else { ": " }
        parts.push(props_prefix(pair.0) + k + sep + props_prefix(pair.1) + v)
      }
      Some("{" + parts.join(", ") + "}")
    }
    Alias(name) => Some("*" + name)
    Sequence(_) | Mapping(_) => None
    _ =>
      match node.style {
        Literal(_) | Folded(_) => None
        // A scalar whose text holds a break is written over several lines, which
        // only a block context can do: it needs a column to continue at.
        _ =>
          if index_of_unit(node.text, 0x0a) >= 0 {
            None
          } else {
            Some(scalar_text_of(node))
          }
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
  parent : Int32,
) -> Unit {
  let (chomp, folded) = match node.style {
    Literal(n) => (n, false)
    Folded(n) => (n, true)
    _ => (0, false)
  }
  out.write_char(if folded { '>' } else { '|' })
  // Content whose first line begins with a space needs an indentation indicator:
  // without one the reader takes that space for the indentation, and the value
  // that comes back is missing it (§8.1.1.1).
  let width = body_at - parent
  if starts_indented(node.text) && width > 0 && width < 10 {
    out.write_char((0x30 + width).unsafe_to_char())
  }
  out.write_string(chomp_mark(chomp))
  out.write_char('\n')
  out.write_string(block_body(node.text, spaces(body_at), folded))
}

///|
/// Emit a document as YAML, keeping the styles and comments it was read with.
///
/// `indent` is how far a nested block is indented, and `from` is how far the root
/// already is — a document embedded in another one needs the second.
///
/// A document that was written under an explicit `---` gets one back, on a line of
/// its own; the comments above it stay above it.
pub fn emit(node : Node, indent~ : Int32 = 2, from~ : Int32 = 0) -> String {
  let out = StringBuilder()
  let body = emit_body(node, indent, from)
  out.write_string(body)
  if node.closed {
    out.write_string(spaces(from))
    out.write_string("...")
    out.write_char('\n')
  }
  out.to_string()
}

///|
/// The document itself, without the `...` that may close it.
fn emit_body(node : Node, indent : Int32, from : Int32) -> String {
  let out = StringBuilder()
  for comment in node.before {
    write_comment(out, comment, from)
  }
  if node.explicit {
    out.write_string(spaces(from))
    out.write_string("---")
    out.write_char('\n')
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
          write_block_scalar(out, node, from + indent, from - 1)
        }
        _ => out.write_string(scalar_written(node, from + indent))
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
        if first && on_dash {
          // The `-` that opened this entry is the first line's indentation.
        } else {
          out.write_string(spaces(inner))
        }
        first = false
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
                write_block_scalar(out, item, inner + indent, inner)
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
                  Mapping(_) =>
                    if props_text(item).length() == 0 {
                      // A block mapping under a `-` starts on the `-` line, which
                      // is what makes `- key: value` a list of mappings.
                      out.write_char(' ')
                      write_block(
                        out,
                        item,
                        indent,
                        inner + indent,
                        on_dash=true,
                      )
                    } else {
                      // A tag or an anchor describes the mapping, so it takes the
                      // `-` line and the mapping starts under it (§8.2.1).
                      out.write_char(' ')
                      out.write_string(props_text(item))
                      out.write_char('\n')
                      write_block(out, item, indent, inner + indent)
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
            // A name runs to the next token, so an alias key needs the space that
            // keeps its `:` out of the name (§7.1).
            if key.kind is Alias(_) {
              out.write_char(' ')
            }
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
                write_block_scalar(out, value, inner + indent, inner)
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
          write_block_scalar(out, node, at + indent, at)
        }
        _ => out.write_string(scalar_written(node, at + indent))
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

// -- the events a document stands for ------------------------------------------

///|
/// One document as the events a parser produces for it: `+DOC` down to `-DOC`,
/// with a `+MAP`/`+SEQ` for a collection, `=VAL` for a scalar and `=ALI` for a
/// reference, each nested one space further in than the event that opened it.
///
/// The notation is the YAML Test Suite's, which is where it is specified: the
/// style a scalar was written in is the character before its text (`:`, `'`, `"`,
/// `|`, `>`), a flow collection carries `{}` or `[]`, an anchor `&name` and a tag
/// `<tag>` come before the value, and control characters are escaped.
///
/// This is the document as a parse rather than as a value: a key that is not a
/// string, a key written twice, two documents in one stream — all of them have
/// events, and none of them has a `Json`. A caller who wants to know whether two
/// documents are the same *document* rather than the same value can compare these.
pub fn Node::events(self : Node) -> String {
  let out = StringBuilder()
  write_event(out, 0, events_open(self))
  events_into(out, self, 1)
  write_event(out, 0, events_close(self))
  out.to_string()
}

///|
/// Every document's events, between the `+STR` and `-STR` that open and close a
/// stream — one line per event, which is what makes two streams comparable line
/// by line.
pub fn events_all(nodes : Array[Node]) -> String {
  let out = StringBuilder()
  write_event(out, 0, "+STR")
  for node in nodes {
    write_event(out, 1, events_open(node))
    events_into(out, node, 2)
    write_event(out, 1, events_close(node))
  }
  write_event(out, 0, "-STR")
  out.to_string()
}

///|
/// The event that opens a document, with the `---` the document was written under.
fn events_open(node : Node) -> String {
  if node.explicit {
    "+DOC ---"
  } else {
    "+DOC"
  }
}

///|
/// The event that closes a document, with the `...` that closed it.
fn events_close(node : Node) -> String {
  if node.closed {
    "-DOC ..."
  } else {
    "-DOC"
  }
}

///|
/// One event, indented `depth` spaces.
fn write_event(out : StringBuilder, depth : Int32, text : String) -> Unit {
  for i = 0; i < depth; i = i + 1 {
    out.write_char(' ')
  }
  out.write_string(text)
  out.write_char('\n')
}

///|
/// The events of one node and everything under it.
fn events_into(out : StringBuilder, node : Node, depth : Int32) -> Unit {
  let props = events_props(node)
  match node.kind {
    Sequence(items) => {
      write_event(out, depth, "+SEQ" + events_flow(node) + props)
      for item in items {
        events_into(out, item, depth + 1)
      }
      write_event(out, depth, "-SEQ")
    }
    Mapping(pairs) => {
      write_event(out, depth, "+MAP" + events_flow(node) + props)
      for pair in pairs {
        events_into(out, pair.0, depth + 1)
        events_into(out, pair.1, depth + 1)
      }
      write_event(out, depth, "-MAP")
    }
    Alias(name) => write_event(out, depth, "=ALI *" + name)
    _ =>
      write_event(
        out,
        depth,
        "=VAL" +
        props +
        " " +
        event_style(node.style).to_string() +
        event_text(node.text),
      )
  }
}

///|
/// ` []` or ` {}` for a collection written in flow style, and nothing otherwise.
fn events_flow(node : Node) -> String {
  if !node.flow {
    return ""
  }
  match node.kind {
    Sequence(_) => " []"
    Mapping(_) => " {}"
    _ => ""
  }
}

///|
/// ` &anchor <tag>`, in that order — the notation's own, and the order a reader
/// accepts them in either way (§6.9).
fn events_props(node : Node) -> String {
  let out = StringBuilder()
  match node.anchor {
    Some(name) => out.write_string(" &" + name)
    None => ()
  }
  match node.tag {
    Some(tag) => out.write_string(" <" + tag + ">")
    None => ()
  }
  out.to_string()
}

///|
/// The character the notation puts in front of a scalar to say how it was written.
fn event_style(style : ScalarStyle) -> Char {
  match style {
    Plain => ':'
    Single => '\''
    Double => '"'
    Literal(_) => '|'
    Folded(_) => '>'
  }
}

///|
/// A scalar's text, with the characters an event cannot hold on one line escaped.
fn event_text(text : String) -> String {
  let out = StringBuilder()
  for i = 0; i < text.length(); i = i + 1 {
    let c = text[i].to_int()
    if c == 0x5c {
      out.write_string("\\\\")
    } else if c == 0x00 {
      out.write_string("\\0")
    } else if c == 0x07 {
      out.write_string("\\a")
    } else if c == 0x08 {
      out.write_string("\\b")
    } else if c == 0x09 {
      out.write_string("\\t")
    } else if c == 0x0a {
      out.write_string("\\n")
    } else if c == 0x0b {
      out.write_string("\\v")
    } else if c == 0x0c {
      out.write_string("\\f")
    } else if c == 0x0d {
      out.write_string("\\r")
    } else if c == 0x1b {
      out.write_string("\\e")
    } else if c < 0x20 {
      out.write_string("\\x")
      out.write_string(hex_of(c))
    } else {
      out.write_char(text[i].unsafe_to_char())
    }
  }
  out.to_string()
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
