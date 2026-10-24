// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A JSON reader for the expected side of a suite comparison.
///
/// The suite's `json` field is written by hand in places and by the reference
/// parsers in others; this reads it strictly, because a value that will not
/// parse is a fault in the data and the harness should say so rather than
/// quietly compare nothing.
priv struct Scan {
  src : String
  mut pos : Int32
}

///|
fn Scan::new(src : String) -> Scan {
  { src, pos: 0, }
}

///|
fn Scan::cur(self : Scan) -> Int32 {
  if self.pos < self.src.length() {
    self.src[self.pos].to_int()
  } else {
    -1
  }
}

///|
fn Scan::bump(self : Scan) -> Unit {
  self.pos = self.pos + 1
}

///|
fn Scan::done(self : Scan) -> Bool {
  self.pos >= self.src.length()
}

///|
fn Scan::gap(self : Scan) -> Unit {
  while self.cur() is (0x20 | 0x09 | 0x0a | 0x0d) {
    self.bump()
  }
}

///|
/// One JSON value, or `None` where the text is not one.
fn Scan::value(self : Scan) -> Json? {
  self.gap()
  match self.cur() {
    0x7b => self.object()
    0x5b => self.array()
    0x22 =>
      match self.text() {
        Some(s) => Some(Json::string(s))
        None => None
      }
    0x74 => self.word("true", Json::boolean(true))
    0x66 => self.word("false", Json::boolean(false))
    0x6e => self.word("null", Json::null())
    _ => self.number()
  }
}

///|
/// `true`, `false` or `null`, spelled out.
fn Scan::word(self : Scan, want : String, value : Json) -> Json? {
  let end = self.pos + want.length()
  if end <= self.src.length() && self.src[self.pos:end].to_owned() == want {
    self.pos = end
    Some(value)
  } else {
    None
  }
}

///|
/// A string with the escapes JSON defines.
fn Scan::text(self : Scan) -> String? {
  self.bump()
  let out = StringBuilder()
  for ;; {
    let c = self.cur()
    if c < 0 {
      return None
    }
    if c == 0x22 {
      self.bump()
      return Some(out.to_string())
    }
    if c == 0x5c {
      self.bump()
      let e = self.cur()
      self.bump()
      match e {
        0x22 => out.write_char('"')
        0x5c => out.write_char('\\')
        0x2f => out.write_char('/')
        0x62 => out.write_char('\u{08}')
        0x66 => out.write_char('\u{0c}')
        0x6e => out.write_char('\n')
        0x72 => out.write_char('\r')
        0x74 => out.write_char('\t')
        0x75 => {
          guard self.quad() is Some(unit) else { return None }
          // A lead surrogate takes the trail that follows it; anything else is
          // the character it names.
          if unit >= 0xd800 && unit <= 0xdbff && self.cur() == 0x5c {
            let save = self.pos
            self.bump()
            if self.cur() == 0x75 {
              self.bump()
              guard self.quad() is Some(low) else { return None }
              if low >= 0xdc00 && low <= 0xdfff {
                let joined = 0x10000 + ((unit - 0xd800) << 10) + (low - 0xdc00)
                out.write_char(joined.unsafe_to_char())
                continue
              }
            }
            self.pos = save
          }
          out.write_char(unit.unsafe_to_char())
        }
        _ => return None
      }
      continue
    }
    out.write_char(self.src[self.pos].unsafe_to_char())
    self.bump()
  }
  None
}

///|
/// Four hexadecimal digits as the code unit they name.
fn Scan::quad(self : Scan) -> Int32? {
  let mut v = 0
  for _ in 0..<4 {
    let c = self.cur()
    let d = if c >= 0x30 && c <= 0x39 {
      c - 0x30
    } else if c >= 0x61 && c <= 0x66 {
      c - 0x61 + 10
    } else if c >= 0x41 && c <= 0x46 {
      c - 0x41 + 10
    } else {
      return None
    }
    v = (v << 4) | d
    self.bump()
  }
  Some(v)
}

///|
/// An array `[...]`.
fn Scan::array(self : Scan) -> Json? {
  self.bump()
  let out : Array[Json] = []
  for ;; {
    self.gap()
    if self.cur() == 0x5d {
      self.bump()
      return Some(Json::array(out))
    }
    match self.value() {
      Some(v) => out.push(v)
      None => return None
    }
    self.gap()
    match self.cur() {
      0x2c => self.bump()
      0x5d => ()
      _ => return None
    }
  }
  None
}

///|
/// An object `{...}`.
fn Scan::object(self : Scan) -> Json? {
  self.bump()
  let out : Map[String, Json] = Map([])
  for ;; {
    self.gap()
    if self.cur() == 0x7d {
      self.bump()
      return Some(Json::object(out))
    }
    if self.cur() != 0x22 {
      return None
    }
    guard self.text() is Some(key) else { return None }
    self.gap()
    if self.cur() != 0x3a {
      return None
    }
    self.bump()
    match self.value() {
      Some(v) => out[key] = v
      None => return None
    }
    self.gap()
    match self.cur() {
      0x2c => self.bump()
      0x7d => ()
      _ => return None
    }
  }
  None
}

///|
/// A number: whole or with a fraction and an exponent.
fn Scan::number(self : Scan) -> Json? {
  let start = self.pos
  if self.cur() == 0x2d {
    self.bump()
  }
  while self.cur() >= 0x30 && self.cur() <= 0x39 {
    self.bump()
  }
  if self.cur() == 0x2e {
    self.bump()
    while self.cur() >= 0x30 && self.cur() <= 0x39 {
      self.bump()
    }
  }
  if self.cur() == 0x65 || self.cur() == 0x45 {
    self.bump()
    if self.cur() == 0x2b || self.cur() == 0x2d {
      self.bump()
    }
    while self.cur() >= 0x30 && self.cur() <= 0x39 {
      self.bump()
    }
  }
  let text = self.src[start:self.pos].to_owned()
  if text.length() == 0 {
    return None
  }
  match decimal(text) {
    Some(n) => Some(Json::number(n))
    None => None
  }
}

///|
/// A decimal literal as the double it denotes, or `None` where it is not one.
fn decimal(s : String) -> Double? {
  if s.length() == 0 {
    return None
  }
  let mut i = 0
  let mut sign = 1.0
  if s[0].to_int() == 0x2d {
    sign = -1.0
    i = 1
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
    for _ in 0..<exp {
      factor = factor * 10.0
    }
    value = if esign < 0 { value / factor } else { value * factor }
  }
  if i != s.length() {
    return None
  }
  Some(sign * value)
}

///|
/// One of the suite's JSON values, or `None` where the text is not one.
pub fn expected(text : String) -> Json? {
  let scan = Scan::new(text)
  let value = scan.value()
  match value {
    None => None
    Some(v) => {
      scan.gap()
      if scan.done() {
        Some(v)
      } else {
        None
      }
    }
  }
}
