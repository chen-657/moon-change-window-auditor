///|
/// String helpers shared by the parser, the audit and the report renderer.

///|
/// Parse a run of ASCII digits. Empty input, signs, spaces and separators are
/// rejected, so `parse_digits("+7")` and `parse_digits(" 7")` both return
/// `None`.
fn parse_digits(text : StringView) -> Int? {
  if text.length() == 0 {
    return None
  }
  let mut total = 0
  for index = 0; index < text.length(); index = index + 1 {
    let code = text[index].to_int()
    if code < 48 || code > 57 {
      return None
    }
    total = total * 10 + (code - 48)
  }
  Some(total)
}

///|
/// Left pad a non-negative number with `0` up to `width` characters.
fn pad_left(value : Int, width : Int) -> String {
  let mut text = value.to_string()
  while text.length() < width {
    text = "0" + text
  }
  text
}

///|
/// Join strings with a separator. An empty array yields an empty string.
fn join(values : Array[String], separator : String) -> String {
  let builder = StringBuilder()
  for index = 0; index < values.length(); index = index + 1 {
    if index > 0 {
      builder.write_string(separator)
    }
    builder.write_string(values[index])
  }
  builder.to_string()
}

///|
/// Window and dependency identifiers accept ASCII letters, digits, `_`, `.` and
/// `-`. They must be non empty and at most 64 characters long, which keeps
/// reports readable and rejects pasted prose or stray quoting.
fn is_valid_identifier(value : String) -> Bool {
  if value.length() == 0 || value.length() > 64 {
    return false
  }
  for character in value.iter() {
    let code = character.to_int()
    let is_digit = code >= 48 && code <= 57
    let is_upper = code >= 65 && code <= 90
    let is_lower = code >= 97 && code <= 122
    let is_punctuation = code == 95 || code == 45 || code == 46
    if !(is_digit || is_upper || is_lower || is_punctuation) {
      return false
    }
  }
  true
}

///|
/// Split `key=value` at the first `=` and trim both sides.
fn split_field(text : StringView) -> (String, String)? {
  for index = 0; index < text.length(); index = index + 1 {
    if text[index] == '=' {
      let key = text[0:index].to_owned().trim().to_owned()
      let value = text[index + 1:text.length()].to_owned().trim().to_owned()
      return Some((key, value))
    }
  }
  None
}

///|
/// Compare two strings by code point: `-1`, `0` or `1`.
///
/// Ordering is defined here instead of relying on a trait so that every sorted
/// report is reproducible on all four backends.
fn compare_strings(left : String, right : String) -> Int {
  let left_chars = left.iter().to_array()
  let right_chars = right.iter().to_array()
  let mut index = 0
  while index < left_chars.length() && index < right_chars.length() {
    let left_code = left_chars[index].to_int()
    let right_code = right_chars[index].to_int()
    if left_code < right_code {
      return -1
    }
    if left_code > right_code {
      return 1
    }
    index = index + 1
  }
  if left_chars.length() < right_chars.length() {
    return -1
  }
  if left_chars.length() > right_chars.length() {
    return 1
  }
  0
}

///|
/// Copy strings ordered by code point, keeping input order for equals.
fn sorted_strings(values : Array[String]) -> Array[String] {
  let ordered : Array[String] = []
  for value in values {
    ordered.push(value)
  }
  let mut index = 1
  while index < ordered.length() {
    let current = ordered[index]
    let mut position = index
    while position > 0 && compare_strings(current, ordered[position - 1]) < 0 {
      ordered[position] = ordered[position - 1]
      position = position - 1
    }
    ordered[position] = current
    index = index + 1
  }
  ordered
}

///|
/// Sorted copy of an array without repeated values.
fn distinct_strings(values : Array[String]) -> Array[String] {
  let ordered = sorted_strings(values)
  let unique : Array[String] = []
  for value in ordered {
    if unique.length() == 0 || unique[unique.length() - 1] != value {
      unique.push(value)
    }
  }
  unique
}
