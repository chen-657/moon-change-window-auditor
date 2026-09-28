///|
/// Text rendering of audit results.
///
/// Every line of the report is stable and greppable, so the output can be
/// pasted into a change ticket, diffed between pipeline runs or filtered with
/// `grep`. The format is covered by tests.

///|
/// Render diagnostics one per line, without indentation. An empty list renders
/// as an empty string.
pub fn render_diagnostics(diagnostics : Array[Diagnostic]) -> String {
  let builder = StringBuilder()
  for index = 0; index < diagnostics.length(); index = index + 1 {
    if index > 0 {
      builder.write_char('\n')
    }
    builder.write_string(diagnostics[index].to_line())
  }
  builder.to_string()
}

///|
/// Append a titled, indented section. `(none)` marks an empty section.
fn write_section(
  builder : StringBuilder,
  title : String,
  lines : Array[String],
) -> Unit {
  builder.write_char('\n')
  builder.write_string(title)
  builder.write_char('\n')
  if lines.length() == 0 {
    builder.write_string("  (none)\n")
  } else {
    for line in lines {
      builder.write_string("  ")
      builder.write_string(line)
      builder.write_char('\n')
    }
  }
}

///|
/// Render a whole audit as a text report.
///
/// The summary carries the counts, the blocked time and the `status` line:
/// `FAIL` when at least one error was found, `PASS` otherwise. Warnings alone
/// keep the status at `PASS`.
pub fn render_report(report : AuditReport) -> String {
  let builder = StringBuilder()
  builder.write_string("Moon Change Window Audit\n")
  builder.write_string("windows: " + report.change_count().to_string() + "\n")
  builder.write_string("freezes: " + report.freeze_count().to_string() + "\n")
  builder.write_string("errors: " + report.error_count().to_string() + "\n")
  builder.write_string("warnings: " + report.warning_count().to_string() + "\n")
  builder.write_string(
    "overlaps: " + report.overlaps.length().to_string() + "\n",
  )
  builder.write_string(
    "freeze conflicts: " + report.freeze_conflicts.length().to_string() + "\n",
  )
  builder.write_string(
    "dependency issues: " + report.dependency_issues.length().to_string() + "\n",
  )
  builder.write_string(
    "blocked: " + format_duration(report.blocked_minutes) + "\n",
  )
  builder.write_string("status: " + report.status() + "\n")
  let window_lines : Array[String] = []
  for window in sort_windows_by_start(report.plan.changes()) {
    window_lines.push(window.to_line())
  }
  write_section(builder, "WINDOWS", window_lines)
  let freeze_lines : Array[String] = []
  for freeze in sort_windows_by_start(report.plan.freezes()) {
    freeze_lines.push(freeze.to_freeze_line())
  }
  write_section(builder, "FREEZES", freeze_lines)
  let overlap_lines : Array[String] = []
  for overlap in report.overlaps {
    overlap_lines.push(overlap.to_line())
  }
  write_section(builder, "OVERLAPS", overlap_lines)
  let conflict_lines : Array[String] = []
  for conflict in report.freeze_conflicts {
    conflict_lines.push(conflict.to_line())
  }
  write_section(builder, "FREEZE CONFLICTS", conflict_lines)
  let issue_lines : Array[String] = []
  for issue in report.dependency_issues {
    issue_lines.push(issue.to_line())
  }
  write_section(builder, "DEPENDENCY ISSUES", issue_lines)
  let diagnostic_lines : Array[String] = []
  for diagnostic in report.plan.diagnostics {
    diagnostic_lines.push(diagnostic.to_line())
  }
  write_section(builder, "DIAGNOSTICS", diagnostic_lines)
  builder.to_string()
}

///|
/// Render the slots returned by `safe_slots`, one per line with its length.
pub fn render_slots(slots : Array[Slot]) -> String {
  let builder = StringBuilder()
  builder.write_string(
    "Safe change slots (" + slots.length().to_string() + ")\n",
  )
  if slots.length() == 0 {
    builder.write_string("  (none)\n")
  } else {
    for slot in slots {
      builder.write_string("  ")
      builder.write_string(slot.to_line())
      builder.write_char('\n')
    }
  }
  builder.to_string()
}
