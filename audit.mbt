///|
/// Offline audit of a change window plan: overlaps and dependency order.

///|
/// Overlap in minutes of two half open intervals; `0` when they only touch.
fn overlap_minutes(
  first_start : Int,
  first_end : Int,
  second_start : Int,
  second_end : Int,
) -> Int {
  let start = if first_start > second_start {
    first_start
  } else {
    second_start
  }
  let end = if first_end < second_end { first_end } else { second_end }
  let length = end - start
  if length > 0 {
    length
  } else {
    0
  }
}

///|
/// Impact of an overlap: two high risk windows are `critical`, one high risk
/// window makes it `major`, everything else is `minor`.
fn impact_of(first : Risk, second : Risk) -> Impact {
  let first_high = first == Risk::High
  let second_high = second == Risk::High
  if first_high && second_high {
    Impact::Critical
  } else if first_high || second_high {
    Impact::Major
  } else {
    Impact::Minor
  }
}

///|
/// Copy windows ordered by start minute, keeping input order for equal starts.
fn sort_windows_by_start(windows : Array[Window]) -> Array[Window] {
  let ordered : Array[Window] = []
  for window in windows {
    ordered.push(window)
  }
  let mut index = 1
  while index < ordered.length() {
    let current = ordered[index]
    let mut position = index
    while position > 0 && ordered[position - 1].start > current.start {
      ordered[position] = ordered[position - 1]
      position = position - 1
    }
    ordered[position] = current
    index = index + 1
  }
  ordered
}

///|
/// Audit a plan.
///
/// Finds every pair of windows that share at least one minute, checks every
/// dependency for a missing target, a self reference and a wrong order, and
/// measures the total blocked time.
///
/// A dependency is satisfied when it ends at or before the dependent starts.
/// Ending exactly at the start is accepted but reported as a `back-to-back`
/// warning, because a change with no slack has no room for overrun.
///
/// Windows that failed to parse are not part of `plan.windows` and therefore
/// cannot overlap or be depended on; their problems stay in
/// `plan.diagnostics`, and the report still fails.
pub fn audit(plan : Plan) -> AuditReport {
  let ordered = sort_windows_by_start(plan.windows)
  let overlaps : Array[Overlap] = []
  let mut first_index = 0
  while first_index < ordered.length() {
    let first = ordered[first_index]
    let mut second_index = first_index + 1
    while second_index < ordered.length() {
      let second = ordered[second_index]
      if second.start >= first.end {
        break
      }
      let minutes = overlap_minutes(
        first.start,
        first.end,
        second.start,
        second.end,
      )
      if minutes > 0 {
        overlaps.push({
          first: first.id,
          second: second.id,
          minutes,
          impact: impact_of(first.risk, second.risk),
        })
      }
      second_index = second_index + 1
    }
    first_index = first_index + 1
  }
  let issues : Array[DependencyIssue] = []
  for window in plan.windows {
    for dependency in window.depends {
      if dependency == window.id {
        issues.push({
          window_id: window.id,
          dependency,
          problem: DependencyProblem::SelfDependency,
          severity: Severity::Error,
          detail: "the window depends on itself",
        })
        continue
      }
      match find_window(plan.windows, dependency) {
        None =>
          issues.push({
            window_id: window.id,
            dependency,
            problem: DependencyProblem::MissingDependency,
            severity: Severity::Error,
            detail: "no window with this id exists in the plan",
          })
        Some(target) =>
          if target.end > window.start {
            issues.push({
              window_id: window.id,
              dependency,
              problem: DependencyProblem::OutOfOrder,
              severity: Severity::Error,
              detail: "the dependency ends " +
              format_duration(target.end - window.start) +
              " after the dependent starts",
            })
          } else if target.end == window.start {
            issues.push({
              window_id: window.id,
              dependency,
              problem: DependencyProblem::BackToBack,
              severity: Severity::Warning,
              detail: "no slack between the dependency end and the dependent start",
            })
          }
      }
    }
  }
  {
    plan,
    overlaps,
    dependency_issues: issues,
    blocked_minutes: blocked_minutes(plan),
  }
}
