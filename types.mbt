///|
/// Data model of a change window plan and of the audit result.

///|
/// Severity of a diagnostic or of a dependency issue.
pub(all) enum Severity {
  Error
  Warning
} derive(Eq)

///|
pub extend Severity with Eq::{equal}

///|
pub extend Severity with Eq::{not_equal}

///|
/// Lower case label: `error` or `warning`.
pub fn Severity::label(self : Severity) -> String {
  match self {
    Severity::Error => "error"
    Severity::Warning => "warning"
  }
}

///|
/// One problem found while parsing or auditing.
pub(all) struct Diagnostic {
  severity : Severity
  code : String
  line : Int
  detail : String
}

///|
/// Render as `error line 3: invalid-instant (start="2026-13-01T22:00")`.
///
/// The `line` part is omitted when the diagnostic is not tied to an input line.
pub fn Diagnostic::to_line(self : Diagnostic) -> String {
  let position = if self.line > 0 {
    " line " + self.line.to_string()
  } else {
    ""
  }
  let head = self.severity.label() + position + ": " + self.code
  if self.detail == "" {
    head
  } else {
    head + " (" + self.detail + ")"
  }
}

///|
/// Risk level attached to a change window.
pub(all) enum Risk {
  Low
  Medium
  High
} derive(Eq)

///|
pub extend Risk with Eq::{equal}

///|
pub extend Risk with Eq::{not_equal}

///|
/// Parse `low`, `medium` or `high`. Matching is exact and lower case.
pub fn Risk::parse(text : String) -> Risk? {
  match text {
    "low" => Some(Risk::Low)
    "medium" => Some(Risk::Medium)
    "high" => Some(Risk::High)
    _ => None
  }
}

///|
/// Lower case label of a risk level.
pub fn Risk::label(self : Risk) -> String {
  match self {
    Risk::Low => "low"
    Risk::Medium => "medium"
    Risk::High => "high"
  }
}

///|
/// One maintenance or change window: a half open `[start, end)` interval with
/// the identifiers of the windows it depends on.
pub(all) struct Window {
  id : String
  service : String
  start : Int
  end : Int
  risk : Risk
  depends : Array[String]
}

///|
/// Length of the window in minutes. Always positive for a parsed window.
pub fn Window::duration(self : Window) -> Int {
  self.end - self.start
}

///|
/// Render as
/// `database | orders-db | 2026-10-01T22:00 -> 2026-10-01T23:30 | 1h30m | high | -`.
///
/// An empty service or an empty dependency list renders as `-`.
pub fn Window::to_line(self : Window) -> String {
  let service = if self.service == "" { "-" } else { self.service }
  let dependencies = if self.depends.length() == 0 {
    "-"
  } else {
    join(self.depends, ", ")
  }
  let builder = StringBuilder()
  builder.write_string(self.id)
  builder.write_string(" | ")
  builder.write_string(service)
  builder.write_string(" | ")
  builder.write_string(format_instant(self.start))
  builder.write_string(" -> ")
  builder.write_string(format_instant(self.end))
  builder.write_string(" | ")
  builder.write_string(format_duration(self.duration()))
  builder.write_string(" | ")
  builder.write_string(self.risk.label())
  builder.write_string(" | ")
  builder.write_string(dependencies)
  builder.to_string()
}

///|
/// A parsed set of change windows together with everything reported while
/// parsing.
pub(all) struct Plan {
  windows : Array[Window]
  diagnostics : Array[Diagnostic]
}

///|
/// Number of windows that were accepted.
pub fn Plan::window_count(self : Plan) -> Int {
  self.windows.length()
}

///|
/// First window with the given id in input order, or `None`.
///
/// Duplicate ids are reported as errors while parsing; this lookup keeps using
/// the first record so that a plan with duplicates still resolves every
/// dependency to exactly one window.
pub fn Plan::find(self : Plan, id : String) -> Window? {
  find_window(self.windows, id)
}

///|
/// True when parsing produced at least one error. Records with an error are
/// dropped from `windows`, so the plan itself is still safe to inspect.
pub fn Plan::has_errors(self : Plan) -> Bool {
  has_error_diagnostic(self.diagnostics)
}

///|
/// First window with the given id, or `None`.
fn find_window(windows : Array[Window], id : String) -> Window? {
  for window in windows {
    if window.id == id {
      return Some(window)
    }
  }
  None
}

///|
/// True when any diagnostic has error severity.
fn has_error_diagnostic(diagnostics : Array[Diagnostic]) -> Bool {
  for diagnostic in diagnostics {
    if diagnostic.severity == Severity::Error {
      return true
    }
  }
  false
}

///|
/// A half open `[start, end)` interval on the minute axis.
pub(all) struct Slot {
  start : Int
  end : Int
}

///|
/// Length of the interval in minutes.
pub fn Slot::duration(self : Slot) -> Int {
  self.end - self.start
}

///|
/// Render as `2026-10-01T20:00 -> 2026-10-01T22:00 (2h)`.
pub fn Slot::to_line(self : Slot) -> String {
  format_instant(self.start) +
  " -> " +
  format_instant(self.end) +
  " (" +
  format_duration(self.duration()) +
  ")"
}

///|
/// Operational impact of an overlap, derived from the risk of both windows.
pub(all) enum Impact {
  Critical
  Major
  Minor
} derive(Eq)

///|
pub extend Impact with Eq::{equal}

///|
pub extend Impact with Eq::{not_equal}

///|
/// Lower case label: `critical`, `major` or `minor`.
pub fn Impact::label(self : Impact) -> String {
  match self {
    Impact::Critical => "critical"
    Impact::Major => "major"
    Impact::Minor => "minor"
  }
}

///|
/// Two windows that share at least one minute.
pub(all) struct Overlap {
  first : String
  second : String
  minutes : Int
  impact : Impact
}

///|
/// Render as `api vs database: 45m (major)`.
pub fn Overlap::to_line(self : Overlap) -> String {
  self.first +
  " vs " +
  self.second +
  ": " +
  format_duration(self.minutes) +
  " (" +
  self.impact.label() +
  ")"
}

///|
/// Kind of dependency problem reported by `audit`.
pub(all) enum DependencyProblem {
  MissingDependency
  SelfDependency
  OutOfOrder
  BackToBack
} derive(Eq)

///|
pub extend DependencyProblem with Eq::{equal}

///|
pub extend DependencyProblem with Eq::{not_equal}

///|
/// Kebab case label: `missing-dependency`, `self-dependency`, `out-of-order` or
/// `back-to-back`.
pub fn DependencyProblem::label(self : DependencyProblem) -> String {
  match self {
    MissingDependency => "missing-dependency"
    SelfDependency => "self-dependency"
    OutOfOrder => "out-of-order"
    BackToBack => "back-to-back"
  }
}

///|
/// A problem between one window and one of the windows it depends on.
pub(all) struct DependencyIssue {
  window_id : String
  dependency : String
  problem : DependencyProblem
  severity : Severity
  detail : String
}

///|
/// Render as
/// `error api -> database: out-of-order (the dependency ends 45m after the dependent starts)`.
pub fn DependencyIssue::to_line(self : DependencyIssue) -> String {
  self.severity.label() +
  " " +
  self.window_id +
  " -> " +
  self.dependency +
  ": " +
  self.problem.label() +
  " (" +
  self.detail +
  ")"
}

///|
/// Result of auditing a plan.
pub(all) struct AuditReport {
  plan : Plan
  overlaps : Array[Overlap]
  dependency_issues : Array[DependencyIssue]
  blocked_minutes : Int
}

///|
/// Number of windows in the audited plan.
pub fn AuditReport::window_count(self : AuditReport) -> Int {
  self.plan.window_count()
}

///|
/// Number of errors: parse errors, overlaps and error level dependency issues.
pub fn AuditReport::error_count(self : AuditReport) -> Int {
  let mut total = 0
  for diagnostic in self.plan.diagnostics {
    if diagnostic.severity == Severity::Error {
      total = total + 1
    }
  }
  for issue in self.dependency_issues {
    if issue.severity == Severity::Error {
      total = total + 1
    }
  }
  total + self.overlaps.length()
}

///|
/// Number of warnings: parse warnings and warning level dependency issues.
pub fn AuditReport::warning_count(self : AuditReport) -> Int {
  let mut total = 0
  for diagnostic in self.plan.diagnostics {
    if diagnostic.severity == Severity::Warning {
      total = total + 1
    }
  }
  for issue in self.dependency_issues {
    if issue.severity == Severity::Warning {
      total = total + 1
    }
  }
  total
}

///|
/// True when the audit found at least one error.
pub fn AuditReport::has_errors(self : AuditReport) -> Bool {
  self.error_count() > 0
}

///|
/// `PASS` when there is no error and `FAIL` otherwise. Warnings do not fail an
/// audit.
pub fn AuditReport::status(self : AuditReport) -> String {
  if self.has_errors() {
    "FAIL"
  } else {
    "PASS"
  }
}
