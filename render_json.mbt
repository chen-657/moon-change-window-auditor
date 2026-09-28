///|
/// Machine readable rendering of plans, audits and safe slots as JSON.
///
/// The emitter is a tiny purpose built writer instead of a generic
/// serialisation library, because the package must stay dependency free and the
/// output has to be byte for byte reproducible on every backend. Each value is
/// pretty printed with two spaces per nesting level, one field per line and no
/// trailing commas; an empty array is written inline as `[]`.
///
/// Every document ends with exactly one newline, so a caller can append the
/// text to a log or a file without adding one.

///|
/// Lower case hexadecimal digit of a value in `0-15`.
fn hex_digit(value : Int) -> String {
  let digits : Array[String] = [
    "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "a", "b", "c", "d", "e", "f",
  ]
  digits[value]
}

///|
/// Escape one character for the body of a JSON string.
fn escape_char(character : Char) -> String {
  match character {
    '"' => "\\\""
    '\\' => "\\\\"
    '\n' => "\\n"
    '\r' => "\\r"
    '\t' => "\\t"
    // 0x08 backspace
    '\u{0008}' => "\\b"
    // 0x0c form feed
    '\u{000C}' => "\\f"
    _ =>
      if character.to_int() < 0x20 {
        let code = character.to_int()
        let builder = StringBuilder()
        builder.write_string("\\u00")
        builder.write_string(hex_digit(code / 16))
        builder.write_string(hex_digit(code % 16))
        builder.to_string()
      } else {
        character.to_string()
      }
  }
}

///|
/// Escape a string for the body of a JSON string.
///
/// `"` becomes `\"`, `\` becomes `\\`, a newline `\n`, a carriage return `\r`, a
/// tab `\t`, a backspace `\b` and a form feed `\f`. Any other character below
/// `0x20` becomes `\u00XX` with two lower case hexadecimal digits. Everything
/// from `0x20` upwards passes through unchanged, so UTF-8 text such as `订单`
/// stays readable and is not turned into `\u` escapes.
///
/// The backslash case runs before the others would matter, because a single
/// pass over the input never looks at text it has already emitted.
pub fn json_escape(text : String) -> String {
  let builder = StringBuilder()
  for character in text {
    builder.write_string(escape_char(character))
  }
  builder.to_string()
}

///|
/// Hand rolled JSON writer: owns the current indentation and the newline rules,
/// so every value is laid out the same way.
priv struct JsonWriter {
  builder : StringBuilder
  mut indent : Int
}

///|
/// An empty writer at the top level.
fn new_json_writer() -> JsonWriter {
  { builder: StringBuilder(), indent: 0, }
}

///|
/// Append the current indentation.
fn write_indent(writer : JsonWriter) -> Unit {
  for index = 0; index < writer.indent; index = index + 1 {
    writer.builder.write_string("  ")
  }
}

///|
/// Move one level in or out.
fn write_nested(writer : JsonWriter, delta : Int) -> Unit {
  writer.indent = writer.indent + delta
}

///|
/// Start a line and print a key. The colon ends the line so that the value can
/// open on the following one.
fn write_key(writer : JsonWriter, key : String) -> Unit {
  writer.builder.write_char('\n')
  write_indent(writer)
  writer.builder.write_char('"')
  writer.builder.write_string(json_escape(key))
  writer.builder.write_string("\":")
}

///|
/// Print an atomic value on the current line.
fn write_atom(writer : JsonWriter, text : String) -> Unit {
  writer.builder.write_string(text)
}

///|
/// Print an already escaped string value on the current line.
fn write_string_value(writer : JsonWriter, text : String) -> Unit {
  writer.builder.write_char('"')
  writer.builder.write_string(json_escape(text))
  writer.builder.write_char('"')
}

///|
/// Print an integer value on the current line.
fn write_int_value(writer : JsonWriter, value : Int) -> Unit {
  writer.builder.write_string(value.to_string())
}

///|
/// A JSON array of strings, laid out over several lines.
fn json_string_array(values : Array[String]) -> String {
  if values.length() == 0 {
    return "[]"
  }
  let writer = new_json_writer()
  writer.builder.write_string("[")
  write_nested(writer, 1)
  for index = 0; index < values.length(); index = index + 1 {
    writer.builder.write_char('\n')
    write_indent(writer)
    write_string_value(writer, values[index])
    if index + 1 < values.length() {
      writer.builder.write_char(',')
    }
  }
  write_nested(writer, -1)
  writer.builder.write_char('\n')
  write_indent(writer)
  writer.builder.write_char(']')
  writer.builder.to_string()
}

///|
/// Append the closing line of an object or array.
fn write_closer(writer : JsonWriter, closer : Char) -> Unit {
  write_nested(writer, -1)
  writer.builder.write_char('\n')
  write_indent(writer)
  writer.builder.write_char(closer)
}

///|
/// One window object.
///
/// The field order is `id`, `service`, `kind`, `start`, `end`, `minutes`,
/// `risk`, `depends`. `start` and `end` are rendered with `format_instant`,
/// `minutes` is the raw length in minutes, `kind` and `risk` use their lower
/// case `label()` and `depends` keeps the input order of the dependencies. A
/// freeze carries no dependencies of its own, so its `depends` array is empty.
fn json_window_object(window : Window) -> String {
  let writer = new_json_writer()
  writer.builder.write_string("{")
  write_nested(writer, 1)
  write_key(writer, "id")
  write_string_value(writer, window.id)
  write_key(writer, "service")
  write_string_value(writer, window.service)
  write_key(writer, "kind")
  write_string_value(writer, window.kind.label())
  write_key(writer, "start")
  write_string_value(writer, format_instant(window.start))
  write_key(writer, "end")
  write_string_value(writer, format_instant(window.end))
  write_key(writer, "minutes")
  write_int_value(writer, window.duration())
  write_key(writer, "risk")
  write_string_value(writer, window.risk.label())
  write_key(writer, "depends")
  write_atom(writer, json_string_array(window.depends))
  write_closer(writer, '}')
  writer.builder.to_string()
}

///|
/// One diagnostic object.
fn json_diagnostic_object(diagnostic : Diagnostic) -> String {
  let writer = new_json_writer()
  writer.builder.write_string("{")
  write_nested(writer, 1)
  write_key(writer, "severity")
  write_string_value(writer, diagnostic.severity.label())
  write_key(writer, "line")
  write_int_value(writer, diagnostic.line)
  write_key(writer, "code")
  write_string_value(writer, diagnostic.code)
  write_key(writer, "detail")
  write_string_value(writer, diagnostic.detail)
  write_closer(writer, '}')
  writer.builder.to_string()
}

///|
/// One overlap object.
fn json_overlap_object(overlap : Overlap) -> String {
  let writer = new_json_writer()
  writer.builder.write_string("{")
  write_nested(writer, 1)
  write_key(writer, "first")
  write_string_value(writer, overlap.first)
  write_key(writer, "second")
  write_string_value(writer, overlap.second)
  write_key(writer, "minutes")
  write_int_value(writer, overlap.minutes)
  write_key(writer, "impact")
  write_string_value(writer, overlap.impact.label())
  write_closer(writer, '}')
  writer.builder.to_string()
}

///|
/// One freeze conflict object.
fn json_conflict_object(conflict : FreezeConflict) -> String {
  let writer = new_json_writer()
  writer.builder.write_string("{")
  write_nested(writer, 1)
  write_key(writer, "window")
  write_string_value(writer, conflict.window_id)
  write_key(writer, "freeze")
  write_string_value(writer, conflict.freeze_id)
  write_key(writer, "minutes")
  write_int_value(writer, conflict.minutes)
  write_closer(writer, '}')
  writer.builder.to_string()
}

///|
/// One dependency issue object.
fn json_issue_object(issue : DependencyIssue) -> String {
  let writer = new_json_writer()
  writer.builder.write_string("{")
  write_nested(writer, 1)
  write_key(writer, "window")
  write_string_value(writer, issue.window_id)
  write_key(writer, "dependency")
  write_string_value(writer, issue.dependency)
  write_key(writer, "problem")
  write_string_value(writer, issue.problem.label())
  write_key(writer, "severity")
  write_string_value(writer, issue.severity.label())
  write_key(writer, "detail")
  write_string_value(writer, issue.detail)
  write_closer(writer, '}')
  writer.builder.to_string()
}

///|
/// One safe slot object.
fn json_slot_object(slot : Slot) -> String {
  let writer = new_json_writer()
  writer.builder.write_string("{")
  write_nested(writer, 1)
  write_key(writer, "start")
  write_string_value(writer, format_instant(slot.start))
  write_key(writer, "end")
  write_string_value(writer, format_instant(slot.end))
  write_key(writer, "minutes")
  write_int_value(writer, slot.duration())
  write_closer(writer, '}')
  writer.builder.to_string()
}

///|
/// Render a plan as JSON: an object with `windows` and `diagnostics`.
///
/// Windows appear in `sort_windows_by_start` order, which is stable for equal
/// start minutes, so the same plan always renders the same bytes. Diagnostics
/// keep their input order, because their line numbers are only meaningful in
/// that order.
pub fn render_plan_json(plan : Plan) -> String {
  let writer = new_json_writer()
  writer.builder.write_string("{")
  write_nested(writer, 1)
  write_key(writer, "windows")
  let ordered = sort_windows_by_start(plan.windows)
  if ordered.length() == 0 {
    write_atom(writer, "[]")
  } else {
    write_atom(writer, "[")
    write_nested(writer, 1)
    for index = 0; index < ordered.length(); index = index + 1 {
      writer.builder.write_char('\n')
      write_indent(writer)
      write_atom(writer, json_window_object(ordered[index]))
      if index + 1 < ordered.length() {
        writer.builder.write_char(',')
      }
    }
    write_closer(writer, ']')
  }
  write_key(writer, "diagnostics")
  if plan.diagnostics.length() == 0 {
    write_atom(writer, "[]")
  } else {
    write_atom(writer, "[")
    write_nested(writer, 1)
    for index = 0; index < plan.diagnostics.length(); index = index + 1 {
      writer.builder.write_char('\n')
      write_indent(writer)
      write_atom(writer, json_diagnostic_object(plan.diagnostics[index]))
      if index + 1 < plan.diagnostics.length() {
        writer.builder.write_char(',')
      }
    }
    write_closer(writer, ']')
  }
  write_closer(writer, '}')
  writer.builder.write_char('\n')
  writer.builder.to_string()
}

///|
/// Render an audit as JSON.
///
/// The summary fields come first, then the collections. `changes` holds the
/// planned changes and `freezes` the change freezes, each sorted by start; the
/// remaining arrays keep the order the audit produced them in, so an overlap,
/// a conflict or an issue stays attributable to the same pair of records.
pub fn render_report_json(report : AuditReport) -> String {
  let writer = new_json_writer()
  writer.builder.write_string("{")
  write_nested(writer, 1)
  write_key(writer, "status")
  write_string_value(writer, report.status())
  write_key(writer, "changes")
  let changes = sort_windows_by_start(report.plan.changes())
  if changes.length() == 0 {
    write_atom(writer, "[]")
  } else {
    write_atom(writer, "[")
    write_nested(writer, 1)
    for index = 0; index < changes.length(); index = index + 1 {
      writer.builder.write_char('\n')
      write_indent(writer)
      write_atom(writer, json_window_object(changes[index]))
      if index + 1 < changes.length() {
        writer.builder.write_char(',')
      }
    }
    write_closer(writer, ']')
  }
  write_key(writer, "freezes")
  let freezes = sort_windows_by_start(report.plan.freezes())
  if freezes.length() == 0 {
    write_atom(writer, "[]")
  } else {
    write_atom(writer, "[")
    write_nested(writer, 1)
    for index = 0; index < freezes.length(); index = index + 1 {
      writer.builder.write_char('\n')
      write_indent(writer)
      write_atom(writer, json_window_object(freezes[index]))
      if index + 1 < freezes.length() {
        writer.builder.write_char(',')
      }
    }
    write_closer(writer, ']')
  }
  write_key(writer, "errors")
  write_int_value(writer, report.error_count())
  write_key(writer, "warnings")
  write_int_value(writer, report.warning_count())
  write_key(writer, "overlaps")
  if report.overlaps.length() == 0 {
    write_atom(writer, "[]")
  } else {
    write_atom(writer, "[")
    write_nested(writer, 1)
    for index = 0; index < report.overlaps.length(); index = index + 1 {
      writer.builder.write_char('\n')
      write_indent(writer)
      write_atom(writer, json_overlap_object(report.overlaps[index]))
      if index + 1 < report.overlaps.length() {
        writer.builder.write_char(',')
      }
    }
    write_closer(writer, ']')
  }
  write_key(writer, "freeze_conflicts")
  if report.freeze_conflicts.length() == 0 {
    write_atom(writer, "[]")
  } else {
    write_atom(writer, "[")
    write_nested(writer, 1)
    for index = 0; index < report.freeze_conflicts.length(); index = index + 1 {
      writer.builder.write_char('\n')
      write_indent(writer)
      write_atom(writer, json_conflict_object(report.freeze_conflicts[index]))
      if index + 1 < report.freeze_conflicts.length() {
        writer.builder.write_char(',')
      }
    }
    write_closer(writer, ']')
  }
  write_key(writer, "dependency_issues")
  if report.dependency_issues.length() == 0 {
    write_atom(writer, "[]")
  } else {
    write_atom(writer, "[")
    write_nested(writer, 1)
    for index = 0; index < report.dependency_issues.length(); index = index + 1 {
      writer.builder.write_char('\n')
      write_indent(writer)
      write_atom(writer, json_issue_object(report.dependency_issues[index]))
      if index + 1 < report.dependency_issues.length() {
        writer.builder.write_char(',')
      }
    }
    write_closer(writer, ']')
  }
  write_key(writer, "blocked_minutes")
  write_int_value(writer, report.blocked_minutes)
  write_key(writer, "diagnostics")
  if report.plan.diagnostics.length() == 0 {
    write_atom(writer, "[]")
  } else {
    write_atom(writer, "[")
    write_nested(writer, 1)
    for index = 0; index < report.plan.diagnostics.length(); index = index + 1 {
      writer.builder.write_char('\n')
      write_indent(writer)
      write_atom(writer, json_diagnostic_object(report.plan.diagnostics[index]))
      if index + 1 < report.plan.diagnostics.length() {
        writer.builder.write_char(',')
      }
    }
    write_closer(writer, ']')
  }
  write_closer(writer, '}')
  writer.builder.write_char('\n')
  writer.builder.to_string()
}

///|
/// Render safe slots as a JSON array of `{start, end, minutes}` objects.
///
/// The input order is preserved: `safe_slots` already returns the intervals in
/// chronological order, and re-sorting here would hide a caller's own ordering.
pub fn render_slots_json(slots : Array[Slot]) -> String {
  if slots.length() == 0 {
    return "[]\n"
  }
  let writer = new_json_writer()
  writer.builder.write_string("[")
  write_nested(writer, 1)
  for index = 0; index < slots.length(); index = index + 1 {
    writer.builder.write_char('\n')
    write_indent(writer)
    write_atom(writer, json_slot_object(slots[index]))
    if index + 1 < slots.length() {
      writer.builder.write_char(',')
    }
  }
  write_nested(writer, -1)
  writer.builder.write_char('\n')
  write_indent(writer)
  writer.builder.write_char(']')
  writer.builder.write_char('\n')
  writer.builder.to_string()
}
