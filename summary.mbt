///|
/// Aggregate facts about one plan.
///
/// The audit answers "what is wrong?"; a summary answers "what does this plan
/// look like?": how many records of each kind, how much calendar time they
/// occupy, how much work they represent, which risk levels they carry, how
/// crowded the busiest minute is and how the load spreads over services.
///
/// Everything is derived from the exported helpers, so a summary can never
/// disagree with the audit and the concurrency measurements taken separately.

///|
/// What one service contributes to a plan.
///
/// The empty service name stands for the changes that name no service; it is
/// reported as `(none)` in text output.
pub(all) struct ServiceSummary {
  service : String
  changes : Int
  blocked_minutes : Int
  peak_concurrency : Int
  high_risk_changes : Int
}

///|
/// Render as
/// `orders-db: 2 changes, 1h30m blocked, peak 2, 1 high risk change`.
///
/// A service with a single change reads `1 change`, not `1 changes`.
pub fn ServiceSummary::to_line(self : ServiceSummary) -> String {
  let name = if self.service == "" { "(none)" } else { self.service }
  name +
  ": " +
  count_text(self.changes, "change", "changes") +
  ", " +
  format_duration(self.blocked_minutes) +
  " blocked, peak " +
  self.peak_concurrency.to_string() +
  ", " +
  count_text(self.high_risk_changes, "high risk change", "high risk changes")
}

///|
/// Everything a single glance should tell about a plan.
///
/// `blocked_minutes` is calendar time (overlaps counted once), while
/// `change_minutes` is workload (every change counted on its own), so the two
/// differ exactly by the overlap inside the plan.
pub(all) struct PlanSummary {
  changes : Int
  freezes : Int
  blocked_minutes : Int
  change_minutes : Int
  low_risk : Int
  medium_risk : Int
  high_risk : Int
  earliest : Int?
  latest : Int?
  span_minutes : Int
  peak : PeakConcurrency?
  services : Array[ServiceSummary]
}

///|
/// Union length of one service's changes: overlapping changes of that service
/// are counted once, and freezes are not part of it.
fn service_blocked_minutes(plan : Plan, service : String) -> Int {
  let slots : Array[Slot] = []
  for change in plan.changes() {
    if change.service == service {
      slots.push({ start: change.start, end: change.end, })
    }
  }
  total_duration(merge_slots(slots))
}

///|
/// Summarise a plan.
///
/// Services are ordered by name with code point comparison, so the empty
/// service sorts first and the output never depends on the input order.
pub fn summarize(plan : Plan) -> PlanSummary {
  let changes = plan.changes()
  let freezes = plan.freezes()
  let mut low_risk = 0
  let mut medium_risk = 0
  let mut high_risk = 0
  for change in changes {
    match change.risk {
      Risk::Low => low_risk = low_risk + 1
      Risk::Medium => medium_risk = medium_risk + 1
      Risk::High => high_risk = high_risk + 1
    }
  }
  let mut earliest : Int? = None
  let mut latest : Int? = None
  for window in plan.windows {
    match earliest {
      None => earliest = Some(window.start)
      Some(current) =>
        if window.start < current {
          earliest = Some(window.start)
        }
    }
    match latest {
      None => latest = Some(window.end)
      Some(current) => if window.end > current { latest = Some(window.end) }
    }
  }
  let span = match (earliest, latest) {
    (Some(from), Some(to)) => to - from
    _ => 0
  }
  let names : Array[String] = []
  for change in changes {
    names.push(change.service)
  }
  let services : Array[ServiceSummary] = []
  for service in distinct_strings(names) {
    let mut high = 0
    let mut count = 0
    for change in changes {
      if change.service == service {
        count = count + 1
        if change.risk == Risk::High {
          high = high + 1
        }
      }
    }
    services.push({
      service,
      changes: count,
      blocked_minutes: service_blocked_minutes(plan, service),
      peak_concurrency: service_peak(plan, service),
      high_risk_changes: high,
    })
  }
  {
    changes: changes.length(),
    freezes: freezes.length(),
    blocked_minutes: blocked_minutes(plan),
    change_minutes: change_minutes(plan),
    low_risk,
    medium_risk,
    high_risk,
    earliest,
    latest,
    span_minutes: span,
    peak: peak_concurrency(plan),
    services,
  }
}

///|
/// Render a summary as a stable text block.
///
/// The shape is fixed: a block of `key: value` lines, then a `SERVICES`
/// section with one two-space-indented line per service or `  (none)`. The text
/// ends with exactly one newline.
pub fn render_summary(summary : PlanSummary) -> String {
  let builder = StringBuilder()
  builder.write_string("Plan summary\n")
  builder.write_string("changes: " + summary.changes.to_string() + "\n")
  builder.write_string("freezes: " + summary.freezes.to_string() + "\n")
  builder.write_string(
    "risks: low " +
    summary.low_risk.to_string() +
    ", medium " +
    summary.medium_risk.to_string() +
    ", high " +
    summary.high_risk.to_string() +
    "\n",
  )
  builder.write_string(
    "blocked: " + format_duration(summary.blocked_minutes) + "\n",
  )
  builder.write_string(
    "workload: " + format_duration(summary.change_minutes) + "\n",
  )
  match (summary.earliest, summary.latest) {
    (Some(from), Some(to)) =>
      builder.write_string(
        "span: " + format_instant(from) + " -> " + format_instant(to) + "\n",
      )
    _ => builder.write_string("span: (empty)\n")
  }
  match summary.peak {
    Some(peak) => builder.write_string("peak: " + peak.to_line() + "\n")
    None => builder.write_string("peak: (none)\n")
  }
  builder.write_string(
    "services: " + summary.services.length().to_string() + "\n",
  )
  builder.write_string("\nSERVICES\n")
  if summary.services.length() == 0 {
    builder.write_string("  (none)\n")
  } else {
    for service in summary.services {
      builder.write_string("  ")
      builder.write_string(service.to_line())
      builder.write_char('\n')
    }
  }
  builder.to_string()
}

///|
/// The summary of one service, or `None` when the name is not in the plan.
pub fn find_service(summary : PlanSummary, service : String) -> ServiceSummary? {
  for entry in summary.services {
    if entry.service == service {
      return Some(entry)
    }
  }
  None
}
