///|
/// Change policy layer: operational rules turned into explicit violations.
///
/// The audit answers "is this plan internally consistent?". A policy answers
/// "is this plan acceptable for us?" - how many changes may run at once, how
/// long a single change may last, how much slack a dependency needs, how many
/// high risk changes a day may carry, and whether changes may run inside a
/// freeze.
///
/// Nothing here mutates the plan or re-implements the audit: every violation is
/// derived from `audit(plan)` and from the exported concurrency and time
/// helpers, so a policy report always agrees with the audit it wraps.
///
/// Violations are produced in a fixed rule order and, inside a rule, in plan or
/// service order. Two runs over the same plan therefore render the same text.

///|
/// Thresholds and flags applied on top of an audit.
///
/// A limit of `0` means "unlimited", and a flag set to `false` disables the
/// rule it belongs to. `Policy::relaxed()` therefore reports nothing at all.
///
/// `max_change_minutes` measures each change on its own and never counts
/// freezes; the freeze rules are `forbid_freeze_conflicts` and, indirectly,
/// `require_service` only for changes.
pub(all) struct Policy {
  max_concurrent : Int
  max_change_minutes : Int
  min_dependency_slack_minutes : Int
  forbid_high_risk_overlap : Bool
  max_high_risk_per_day : Int
  forbid_freeze_conflicts : Bool
  require_service : Bool
}

///|
/// The default policy: every numeric limit is off, changes may run inside a
/// freeze only if the plan says so, and an unnamed service is accepted.
///
/// Only `forbid_freeze_conflicts` is on, because a change running inside a
/// declared freeze is a contradiction rather than a tuning choice.
pub fn Policy::standard() -> Policy {
  {
    max_concurrent: 0,
    max_change_minutes: 0,
    min_dependency_slack_minutes: 0,
    forbid_high_risk_overlap: false,
    max_high_risk_per_day: 0,
    forbid_freeze_conflicts: true,
    require_service: false,
  }
}

///|
/// A tight policy for a fragile service: two changes at a time, no change
/// longer than two hours, thirty minutes of slack after every dependency, no
/// two high risk changes in the same minute, two high risk changes a day, no
/// change inside a freeze and no change without a named service.
pub fn Policy::strict() -> Policy {
  {
    max_concurrent: 2,
    max_change_minutes: 120,
    min_dependency_slack_minutes: 30,
    forbid_high_risk_overlap: true,
    max_high_risk_per_day: 2,
    forbid_freeze_conflicts: true,
    require_service: true,
  }
}

///|
/// A policy that reports nothing: every limit is off, every flag is false. Use
/// it as the neutral element from which a caller builds its own thresholds.
pub fn Policy::relaxed() -> Policy {
  {
    max_concurrent: 0,
    max_change_minutes: 0,
    min_dependency_slack_minutes: 0,
    forbid_high_risk_overlap: false,
    max_high_risk_per_day: 0,
    forbid_freeze_conflicts: false,
    require_service: false,
  }
}

///|
/// Render every setting as one `key = value` line, in declaration order.
///
/// Booleans render as `true` or `false`, a limit of `0` renders as `unlimited`,
/// and the result has no trailing newline.
pub fn Policy::describe(self : Policy) -> String {
  let builder = StringBuilder()
  builder.write_string(
    "max_concurrent = " + limit_text(self.max_concurrent) + "\n",
  )
  builder.write_string(
    "max_change_minutes = " + limit_text(self.max_change_minutes) + "\n",
  )
  builder.write_string(
    "min_dependency_slack_minutes = " +
    limit_text(self.min_dependency_slack_minutes) +
    "\n",
  )
  builder.write_string(
    "forbid_high_risk_overlap = " +
    bool_text(self.forbid_high_risk_overlap) +
    "\n",
  )
  builder.write_string(
    "max_high_risk_per_day = " + limit_text(self.max_high_risk_per_day) + "\n",
  )
  builder.write_string(
    "forbid_freeze_conflicts = " +
    bool_text(self.forbid_freeze_conflicts) +
    "\n",
  )
  builder.write_string("require_service = " + bool_text(self.require_service))
  builder.to_string()
}

///|
/// Render a limit as a number, or as `unlimited` when it is off (`0`).
fn limit_text(value : Int) -> String {
  if value == 0 {
    "unlimited"
  } else {
    value.to_string()
  }
}

///|
/// Render a flag that decides whether a rule runs.
fn bool_text(value : Bool) -> String {
  if value {
    "true"
  } else {
    "false"
  }
}

///|
/// One rule breach: which rule, how bad, about what, and why.
///
/// `subject` is a window id, a service name or `all`, depending on the rule.
pub(all) struct PolicyViolation {
  code : String
  severity : Severity
  subject : String
  detail : String
}

///|
/// Render as `error max-concurrent (all): ...`, without a line number because a
/// policy speaks about the plan as a whole.
pub fn PolicyViolation::to_line(self : PolicyViolation) -> String {
  self.severity.label() +
  " " +
  self.code +
  " (" +
  self.subject +
  "): " +
  self.detail
}

///|
/// An audit together with the policy it was judged against and every breach of
/// that policy.
pub(all) struct PolicyReport {
  plan : Plan
  audit : AuditReport
  policy : Policy
  violations : Array[PolicyViolation]
}

///|
/// Judge a plan against a policy.
///
/// The audit is computed exactly once with `audit(plan)` and stored unchanged,
/// so `report.audit` is always the same report the plain audit would return;
/// the policy only adds violations beside it.
pub fn audit_with_policy(plan : Plan, policy : Policy) -> PolicyReport {
  let report = audit(plan)
  {
    plan,
    audit: report,
    policy,
    violations: policy_violations(plan, report, policy),
  }
}

///|
/// Number of policy violations, regardless of severity.
pub fn PolicyReport::violation_count(self : PolicyReport) -> Int {
  self.violations.length()
}

///|
/// Policy errors plus the errors the underlying audit found.
pub fn PolicyReport::error_count(self : PolicyReport) -> Int {
  let mut total = self.audit.error_count()
  for violation in self.violations {
    if violation.severity == Severity::Error {
      total = total + 1
    }
  }
  total
}

///|
/// Policy warnings plus the warnings the underlying audit found.
pub fn PolicyReport::warning_count(self : PolicyReport) -> Int {
  let mut total = self.audit.warning_count()
  for violation in self.violations {
    if violation.severity == Severity::Warning {
      total = total + 1
    }
  }
  total
}

///|
/// True when either the audit or the policy found an error.
pub fn PolicyReport::has_errors(self : PolicyReport) -> Bool {
  self.error_count() > 0
}

///|
/// `FAIL` when there is at least one error, `PASS` otherwise. A report whose
/// only findings are warnings stays at `PASS`.
pub fn PolicyReport::status(self : PolicyReport) -> String {
  if self.has_errors() {
    "FAIL"
  } else {
    "PASS"
  }
}

///|
/// Highest number of simultaneous changes of one service.
///
/// The maximum is reached at the start of some change of that service, so the
/// search walks those start minutes and breaks ties towards the earliest one.
fn service_peak(plan : Plan, service : String) -> Int {
  let mut best = 0
  for change in plan.changes() {
    if change.service == service {
      let count = service_concurrency_at(plan, service, change.start)
      if count > best {
        best = count
      }
    }
  }
  best
}

///|
/// True when the plan holds a change with this id and high risk.
fn is_high_risk_change(plan : Plan, id : String) -> Bool {
  match plan.find(id) {
    Some(window) => window.is_change() && window.risk == Risk::High
    None => false
  }
}

///|
/// Length of the overlap between two changes of the plan, or `0` when they do
/// not overlap or when one of them is missing.
fn overlap_for_pair(plan : Plan, first_id : String, second_id : String) -> Int {
  match (plan.find(first_id), plan.find(second_id)) {
    (Some(first), Some(second)) =>
      overlap_minutes(first.start, first.end, second.start, second.end)
    _ => 0
  }
}

///|
/// Every policy violation of a plan, in the fixed rule order:
///
/// 1. `max-concurrent`, 2. `max-change-minutes`, 3. `min-dependency-slack`,
/// 4. `high-risk-overlap`, 5. `max-high-risk-per-day`, 6. `freeze-conflict`,
/// 7. `service-missing`.
fn policy_violations(
  plan : Plan,
  report : AuditReport,
  policy : Policy,
) -> Array[PolicyViolation] {
  let violations : Array[PolicyViolation] = []
  append_concurrency_violations(plan, policy, violations)
  append_change_length_violations(plan, policy, violations)
  append_slack_violations(plan, policy, violations)
  append_high_risk_overlap_violations(plan, report, policy, violations)
  append_daily_high_risk_violations(plan, policy, violations)
  append_freeze_violations(report, policy, violations)
  append_service_violations(plan, policy, violations)
  violations
}

///|
/// Rule 1 `max-concurrent` (error): first the whole plan, then every service
/// that has changes, in code point order of the service names.
fn append_concurrency_violations(
  plan : Plan,
  policy : Policy,
  violations : Array[PolicyViolation],
) -> Unit {
  let limit = policy.max_concurrent
  if limit <= 0 {
    return
  }
  match peak_concurrency(plan) {
    Some(peak) =>
      if peak.count > limit {
        violations.push({
          code: "max-concurrent",
          severity: Severity::Error,
          subject: "all",
          detail: peak.count.to_string() +
          " simultaneous changes at " +
          format_instant(peak.minute) +
          " exceed the limit of " +
          limit.to_string(),
        })
      }
    None => ()
  }
  let services : Array[String] = []
  for change in plan.changes() {
    services.push(change.service)
  }
  for service in distinct_strings(services) {
    let count = service_peak(plan, service)
    if count > limit {
      violations.push({
        code: "max-concurrent",
        severity: Severity::Error,
        subject: service,
        detail: count.to_string() +
        " simultaneous changes at " +
        format_instant(service_peak_minute(plan, service, count)) +
        " exceed the limit of " +
        limit.to_string(),
      })
    }
  }
}

///|
/// First start minute at which a service reaches its peak; ties go to the
/// earliest change, which keeps the rendered detail stable.
fn service_peak_minute(plan : Plan, service : String, peak : Int) -> Int {
  for change in plan.changes() {
    if change.service == service &&
      service_concurrency_at(plan, service, change.start) == peak {
      return change.start
    }
  }
  0
}

///|
/// Rule 2 `max-change-minutes` (error): every change longer than the limit, in
/// plan order. Freezes are never measured by this rule.
fn append_change_length_violations(
  plan : Plan,
  policy : Policy,
  violations : Array[PolicyViolation],
) -> Unit {
  let limit = policy.max_change_minutes
  if limit <= 0 {
    return
  }
  for change in plan.changes() {
    let duration = change.duration()
    if duration > limit {
      violations.push({
        code: "max-change-minutes",
        severity: Severity::Error,
        subject: change.id,
        detail: "the change lasts " +
        format_duration(duration) +
        ", the limit is " +
        format_duration(limit),
      })
    }
  }
}

///|
/// Rule 3 `min-dependency-slack` (warning): every dependency that exists in the
/// plan and leaves less than the required slack, in plan order and in
/// dependency order inside a change.
///
/// A negative slack means the dependency still runs when the dependent starts;
/// the detail then reports the overlap in those words instead of a bare
/// magnitude.
fn append_slack_violations(
  plan : Plan,
  policy : Policy,
  violations : Array[PolicyViolation],
) -> Unit {
  let limit = policy.min_dependency_slack_minutes
  if limit <= 0 {
    return
  }
  for change in plan.changes() {
    for dependency_id in change.depends {
      match plan.find(dependency_id) {
        None => ()
        Some(dependency) =>
          if dependency.id != change.id {
            let slack = change.start - dependency.end
            if slack < limit {
              let detail = if slack < 0 {
                "overlaps " +
                dependency.id +
                " and misses the minimum slack of " +
                format_duration(limit) +
                " by " +
                format_duration(slack)
              } else {
                "only " +
                format_duration(slack) +
                " of slack after " +
                dependency.id +
                ", the minimum is " +
                format_duration(limit)
              }
              violations.push({
                code: "min-dependency-slack",
                severity: Severity::Warning,
                subject: change.id,
                detail,
              })
            }
          }
      }
    }
  }
}

///|
/// Rule 4 `high-risk-overlap` (error): every overlapping pair the audit found
/// that involves at least one high risk change, reported once per pair and in
/// the order the audit produced the pairs.
fn append_high_risk_overlap_violations(
  plan : Plan,
  report : AuditReport,
  policy : Policy,
  violations : Array[PolicyViolation],
) -> Unit {
  if !policy.forbid_high_risk_overlap {
    return
  }
  for overlap in report.overlaps {
    let first_high = is_high_risk_change(plan, overlap.first)
    let second_high = is_high_risk_change(plan, overlap.second)
    if !first_high && !second_high {
      continue
    }
    let subject = if first_high { overlap.first } else { overlap.second }
    let other = if first_high { overlap.second } else { overlap.first }
    violations.push({
      code: "high-risk-overlap",
      severity: Severity::Error,
      subject,
      detail: "high risk " +
      subject +
      " overlaps " +
      other +
      " for " +
      format_duration(overlap_for_pair(plan, subject, other)),
    })
  }
}

///|
/// Rule 5 `max-high-risk-per-day` (error): days with more high risk changes
/// than allowed, in ascending calendar order.
///
/// A change belongs to the day its start falls in, so a change that crosses
/// midnight counts towards the day it begins on. Ordering uses insertion sort
/// on the day index rather than a library sort, which keeps the output
/// reproducible.
fn append_daily_high_risk_violations(
  plan : Plan,
  policy : Policy,
  violations : Array[PolicyViolation],
) -> Unit {
  let limit = policy.max_high_risk_per_day
  if limit <= 0 {
    return
  }
  let days : Array[Int] = []
  let counts : Array[Int] = []
  for change in plan.changes() {
    if change.risk == Risk::High {
      let day = change.start / MINUTES_PER_DAY
      match day_index(days, day) {
        Some(position) => counts[position] = counts[position] + 1
        None => {
          days.push(day)
          counts.push(1)
        }
      }
    }
  }
  let order : Array[Int] = []
  for index = 0; index < days.length(); index = index + 1 {
    order.push(index)
  }
  let mut position = 1
  while position < order.length() {
    let current = order[position]
    let mut scan = position
    while scan > 0 && days[order[scan - 1]] > days[current] {
      order[scan] = order[scan - 1]
      scan = scan - 1
    }
    order[scan] = current
    position = position + 1
  }
  for index in order {
    if counts[index] > limit {
      violations.push({
        code: "max-high-risk-per-day",
        severity: Severity::Error,
        subject: format_instant(days[index] * MINUTES_PER_DAY),
        detail: counts[index].to_string() +
        " high risk changes on this day, the limit is " +
        limit.to_string(),
      })
    }
  }
}

///|
/// Position of a value in an array, or `None`.
fn day_index(values : Array[Int], value : Int) -> Int? {
  for index = 0; index < values.length(); index = index + 1 {
    if values[index] == value {
      return Some(index)
    }
  }
  None
}

///|
/// Rule 6 `freeze-conflict` (error): one violation per conflict the audit
/// found, so a change inside two freezes produces two violations.
fn append_freeze_violations(
  report : AuditReport,
  policy : Policy,
  violations : Array[PolicyViolation],
) -> Unit {
  if !policy.forbid_freeze_conflicts {
    return
  }
  for conflict in report.freeze_conflicts {
    violations.push({
      code: "freeze-conflict",
      severity: Severity::Error,
      subject: conflict.window_id,
      detail: "runs inside freeze " +
      conflict.freeze_id +
      " for " +
      format_duration(conflict.minutes),
    })
  }
}

///|
/// Rule 7 `service-missing` (warning): every change without a service name, in
/// plan order.
fn append_service_violations(
  plan : Plan,
  policy : Policy,
  violations : Array[PolicyViolation],
) -> Unit {
  if !policy.require_service {
    return
  }
  for change in plan.changes() {
    if change.service == "" {
      violations.push({
        code: "service-missing",
        severity: Severity::Warning,
        subject: change.id,
        detail: "no service is named for this change",
      })
    }
  }
}

///|
/// Render a policy report.
///
/// The header is followed by the untouched audit report, then by the policy
/// section: the two-space-indented violations, or `  (none)`, and finally the
/// `policy: <status>` line. The string ends with exactly one newline.
pub fn render_policy_report(report : PolicyReport) -> String {
  let builder = StringBuilder()
  builder.write_string("Moon Change Window Policy Report\n")
  builder.write_string(render_report(report.audit))
  builder.write_char('\n')
  builder.write_string("POLICY VIOLATIONS\n")
  if report.violations.length() == 0 {
    builder.write_string("  (none)\n")
  } else {
    for violation in report.violations {
      builder.write_string("  ")
      builder.write_string(violation.to_line())
      builder.write_char('\n')
    }
  }
  builder.write_string("policy: " + report.status() + "\n")
  builder.to_string()
}

///|
/// Render violations one per line, without indentation. An empty list renders
/// as an empty string.
pub fn render_violations(violations : Array[PolicyViolation]) -> String {
  let builder = StringBuilder()
  for index = 0; index < violations.length(); index = index + 1 {
    if index > 0 {
      builder.write_char('\n')
    }
    builder.write_string(violations[index].to_line())
  }
  builder.to_string()
}
