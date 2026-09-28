///|
/// Comma separated export, for spreadsheets and for tools that only speak CSV.
///
/// The dialect is the usual one: fields are separated by commas, a field that
/// contains a comma, a double quote or a line break is wrapped in double quotes,
/// and an inner double quote is doubled. Every document ends with exactly one
/// newline.

///|
/// Quote a field when it needs it.
///
/// A field needs quoting when it holds a comma, a double quote, a newline or a
/// carriage return; inside the quotes every double quote is doubled.
pub fn csv_escape(text : String) -> String {
  let mut needs_quotes = false
  for character in text {
    match character {
      ',' | '"' | '\n' | '\r' => needs_quotes = true
      _ => ()
    }
  }
  if !needs_quotes {
    return text
  }
  let builder = StringBuilder()
  builder.write_char('"')
  for character in text {
    if character == '"' {
      builder.write_string("\"\"")
    } else {
      builder.write_char(character)
    }
  }
  builder.write_char('"')
  builder.to_string()
}

///|
/// One CSV line from already escaped fields.
fn csv_line(fields : Array[String]) -> String {
  let builder = StringBuilder()
  for index = 0; index < fields.length(); index = index + 1 {
    if index > 0 {
      builder.write_char(',')
    }
    builder.write_string(fields[index])
  }
  builder.write_char('\n')
  builder.to_string()
}

///|
/// Every record of the plan as CSV, ordered by start minute.
///
/// Columns are `id,service,kind,start,end,minutes,risk,depends`; a dependency
/// list is joined with `|`, because a comma inside a cell would be ambiguous
/// even when quoted.
pub fn render_windows_csv(plan : Plan) -> String {
  let builder = StringBuilder()
  builder.write_string("id,service,kind,start,end,minutes,risk,depends\n")
  for window in sort_windows_by_start(plan.windows) {
    builder.write_string(
      csv_line([
        csv_escape(window.id),
        csv_escape(window.service),
        csv_escape(window.kind.label()),
        csv_escape(format_instant(window.start)),
        csv_escape(format_instant(window.end)),
        csv_escape(window.duration().to_string()),
        csv_escape(window.risk.label()),
        csv_escape(join(window.depends, "|")),
      ]),
    )
  }
  builder.to_string()
}

///|
/// The overlaps of an audit as CSV, with the four columns
/// `first,second,minutes,impact`.
pub fn render_overlaps_csv(report : AuditReport) -> String {
  let builder = StringBuilder()
  builder.write_string("first,second,minutes,impact\n")
  for overlap in report.overlaps {
    builder.write_string(
      csv_line([
        csv_escape(overlap.first),
        csv_escape(overlap.second),
        csv_escape(overlap.minutes.to_string()),
        csv_escape(overlap.impact.label()),
      ]),
    )
  }
  builder.to_string()
}

///|
/// Safe slots as CSV, with the columns `start,end,minutes`.
pub fn render_slots_csv(slots : Array[Slot]) -> String {
  let builder = StringBuilder()
  builder.write_string("start,end,minutes\n")
  for slot in slots {
    builder.write_string(
      csv_line([
        csv_escape(format_instant(slot.start)),
        csv_escape(format_instant(slot.end)),
        csv_escape(slot.duration().to_string()),
      ]),
    )
  }
  builder.to_string()
}

///|
/// Freeze conflicts as CSV, with the columns `window,freeze,minutes`.
pub fn render_freeze_conflicts_csv(report : AuditReport) -> String {
  let builder = StringBuilder()
  builder.write_string("window,freeze,minutes\n")
  for conflict in report.freeze_conflicts {
    builder.write_string(
      csv_line([
        csv_escape(conflict.window_id),
        csv_escape(conflict.freeze_id),
        csv_escape(conflict.minutes.to_string()),
      ]),
    )
  }
  builder.to_string()
}

///|
/// Dependency issues as CSV, with the columns
/// `window,dependency,problem,severity,detail`.
pub fn render_dependency_issues_csv(report : AuditReport) -> String {
  let builder = StringBuilder()
  builder.write_string("window,dependency,problem,severity,detail\n")
  for issue in report.dependency_issues {
    builder.write_string(
      csv_line([
        csv_escape(issue.window_id),
        csv_escape(issue.dependency),
        csv_escape(issue.problem.label()),
        csv_escape(issue.severity.label()),
        csv_escape(issue.detail),
      ]),
    )
  }
  builder.to_string()
}
