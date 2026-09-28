///|
/// Markdown rendering, for pull requests, issue comments and change tickets.
///
/// The tables follow GitHub flavoured Markdown: a header row, a separator row
/// and one row per record. A `|` inside a cell is escaped as `\|` and a line
/// break inside a cell becomes a space, because a table cell cannot hold one.

///|
/// Escape one table cell.
fn markdown_cell(text : String) -> String {
  let builder = StringBuilder()
  for character in text {
    match character {
      '|' => builder.write_string("\\|")
      '\n' => builder.write_char(' ')
      '\r' => builder.write_char(' ')
      _ => builder.write_char(character)
    }
  }
  builder.to_string()
}

///|
/// One table row, including the trailing newline.
fn markdown_row(cells : Array[String]) -> String {
  let builder = StringBuilder()
  builder.write_char('|')
  for cell in cells {
    builder.write_char(' ')
    builder.write_string(markdown_cell(cell))
    builder.write_string(" |")
  }
  builder.write_char('\n')
  builder.to_string()
}

///|
/// The separator row for a table of `count` columns.
fn markdown_separator(count : Int) -> String {
  let cells : Array[String] = []
  for index = 0; index < count; index = index + 1 {
    cells.push("---")
  }
  markdown_row(cells)
}

///|
/// A table with the given header, separator width and body rows.
fn markdown_table(header : Array[String], rows : Array[String]) -> String {
  let builder = StringBuilder()
  builder.write_string(markdown_row(header))
  builder.write_string(markdown_separator(header.length()))
  for row in rows {
    builder.write_string(row)
  }
  builder.to_string()
}

///|
/// A table of every record of the plan, ordered by start minute.
///
/// An empty service and an empty dependency list render as `-`.
pub fn render_windows_markdown(plan : Plan) -> String {
  let rows : Array[String] = []
  for window in sort_windows_by_start(plan.windows) {
    let depends = if window.depends.length() == 0 {
      "-"
    } else {
      join(window.depends, ", ")
    }
    let service = if window.service == "" { "-" } else { window.service }
    rows.push(
      markdown_row([
        window.id,
        service,
        window.kind.label(),
        format_instant(window.start),
        format_instant(window.end),
        format_duration(window.duration()),
        window.risk.label(),
        depends,
      ]),
    )
  }
  markdown_table(
    ["id", "service", "kind", "start", "end", "duration", "risk", "depends"],
    rows,
  )
}

///|
/// A table of the freezes of the plan, or `none`.
fn render_freezes_markdown(plan : Plan) -> String {
  let freezes = sort_windows_by_start(plan.freezes())
  if freezes.length() == 0 {
    return "none\n"
  }
  let rows : Array[String] = []
  for freeze in freezes {
    rows.push(
      markdown_row([
        freeze.id,
        if freeze.service == "" {
          "-"
        } else {
          freeze.service
        },
        format_instant(freeze.start),
        format_instant(freeze.end),
        format_duration(freeze.duration()),
      ]),
    )
  }
  markdown_table(["id", "service", "start", "end", "duration"], rows)
}

///|
/// Render a whole audit as Markdown.
///
/// The summary is a bullet list, then one section per collection. A section
/// without rows renders the single line `none` so a reader can tell "nothing
/// found" from "section dropped". The text ends with exactly one newline.
pub fn render_report_markdown(report : AuditReport) -> String {
  let builder = StringBuilder()
  builder.write_string("# Moon Change Window Audit\n\n")
  builder.write_string("- status: " + report.status() + "\n")
  builder.write_string("- changes: " + report.change_count().to_string() + "\n")
  builder.write_string("- freezes: " + report.freeze_count().to_string() + "\n")
  builder.write_string("- errors: " + report.error_count().to_string() + "\n")
  builder.write_string(
    "- warnings: " + report.warning_count().to_string() + "\n",
  )
  builder.write_string(
    "- overlaps: " + report.overlaps.length().to_string() + "\n",
  )
  builder.write_string(
    "- freeze conflicts: " + report.freeze_conflicts.length().to_string() + "\n",
  )
  builder.write_string(
    "- dependency issues: " +
    report.dependency_issues.length().to_string() +
    "\n",
  )
  builder.write_string(
    "- blocked: " + format_duration(report.blocked_minutes) + "\n",
  )
  builder.write_string("\n## Windows\n\n")
  builder.write_string(render_windows_markdown(report.plan))
  builder.write_string("\n## Freezes\n\n")
  builder.write_string(render_freezes_markdown(report.plan))
  builder.write_string("\n## Overlaps\n\n")
  if report.overlaps.length() == 0 {
    builder.write_string("none\n")
  } else {
    let rows : Array[String] = []
    for overlap in report.overlaps {
      rows.push(
        markdown_row([
          overlap.first,
          overlap.second,
          overlap.minutes.to_string(),
          overlap.impact.label(),
        ]),
      )
    }
    builder.write_string(
      markdown_table(["first", "second", "minutes", "impact"], rows),
    )
  }
  builder.write_string("\n## Dependency issues\n\n")
  if report.dependency_issues.length() == 0 {
    builder.write_string("none\n")
  } else {
    let rows : Array[String] = []
    for issue in report.dependency_issues {
      rows.push(
        markdown_row([
          issue.window_id,
          issue.dependency,
          issue.problem.label(),
          issue.severity.label(),
          issue.detail,
        ]),
      )
    }
    builder.write_string(
      markdown_table(
        ["window", "dependency", "problem", "severity", "detail"],
        rows,
      ),
    )
  }
  builder.write_string("\n## Diagnostics\n\n")
  if report.plan.diagnostics.length() == 0 {
    builder.write_string("none\n")
  } else {
    let rows : Array[String] = []
    for diagnostic in report.plan.diagnostics {
      rows.push(
        markdown_row([
          diagnostic.severity.label(),
          diagnostic.line.to_string(),
          diagnostic.code,
          diagnostic.detail,
        ]),
      )
    }
    builder.write_string(
      markdown_table(["severity", "line", "code", "detail"], rows),
    )
  }
  builder.to_string()
}

///|
/// Render safe slots as a Markdown table, or `none` when there are none.
///
/// The text ends with exactly one newline.
pub fn render_slots_markdown(slots : Array[Slot]) -> String {
  let builder = StringBuilder()
  builder.write_string(
    "Safe change slots (" + slots.length().to_string() + ")\n\n",
  )
  if slots.length() == 0 {
    builder.write_string("none\n")
  } else {
    let rows : Array[String] = []
    for slot in slots {
      rows.push(
        markdown_row([
          format_instant(slot.start),
          format_instant(slot.end),
          format_duration(slot.duration()),
        ]),
      )
    }
    builder.write_string(markdown_table(["start", "end", "duration"], rows))
  }
  builder.to_string()
}
