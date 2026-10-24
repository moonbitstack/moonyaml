// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Whether two values are the same document.
///
/// Numbers compare as doubles, with NaN equal to itself because a document
/// whose expected value is `.nan` is not a failure. A mapping's key order does
/// not matter: the suite records the order its reference parser built, which is
/// not always the order this family does — the same pairs in another order are
/// the same document.
pub fn same(a : Json, b : Json) -> Bool {
  match (a, b) {
    (Null, Null) | (True, True) | (False, False) => true
    (Number(x, ..), Number(y, ..)) => x == y || (x != x && y != y)
    (String(x), String(y)) => x == y
    (Array(x), Array(y)) =>
      if x.length() != y.length() {
        false
      } else {
        let mut ok = true
        for i in 0..<x.length() {
          if !same(x[i], y[i]) {
            ok = false
          }
        }
        ok
      }
    (Object(x), Object(y)) =>
      if x.length() != y.length() {
        false
      } else {
        let mut ok = true
        for k, v in x {
          match y.get(k) {
            Some(w) => if !same(v, w) { ok = false }
            None => ok = false
          }
        }
        ok
      }
    _ => false
  }
}

///|
/// Every scalar as one sentinel, which is what is left of a document once a
/// reader that reads every scalar as a string has been at it: the shape, and
/// nothing else. Comparing shapes is how the StrictYAML harness checks that a
/// document still reads as the mapping or sequence it is without pretending
/// the scalars came out as numbers.
pub fn shape(v : Json) -> Json {
  match v {
    Array(items) => Json::array(items.map(shape))
    Object(fields) => {
      let out : Map[String, Json] = Map([])
      for k, held in fields {
        out[k] = shape(held)
      }
      Json::object(out)
    }
    _ => Json::string("·")
  }
}
