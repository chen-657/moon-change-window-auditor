///|
/// The "can I add this change, and when" layer.
///
/// Everything here answers one of three questions about a *candidate* interval
/// that is not part of the plan yet:
///
/// 1. `can_schedule` explains why the candidate is refused or accepted,
/// 2. `earliest_start` and `slack_minutes` look for room around it,
/// 3. `earliest_schedule` compresses the whole plan to the earliest dependency
///    aware schedule without ever moving a change earlier.
///
/// Every decision is reproducible: conflicts are collected in plan order and no
/// result depends on a hash or on a library sort.

///|
/// One planned change the candidate runs into, with the shared minutes.
pub(all) struct SlotConflict {
  window_id : String
  minutes : Int
}

///|
/// Render as `api: 45m`.
pub fn SlotConflict::to_line(self : SlotConflict) -> String {
  self.window_id + ": " + format_duration(self.minutes)
}

///|
/// True when `candidate` shares at least one minute with a change or a freeze
/// of the plan.
///
/// Used by `earliest_start` to decide whether a position has to be skipped; it
/// is the union of the two blocking rules of `can_schedule`.
fn schedule_is_blocked(plan : Plan, candidate : Slot) -> Bool {
  for window in plan.windows {
    if overlap_minutes(window.start, window.end, candidate.start, candidate.end) >
      0 {
      return true
    }
  }
  false
}

///|
/// The verdict for one candidate interval.
///
/// `reasons` lists the rule codes that fired, in the fixed order
/// `no-duration`, `too-short`, `blocked-by-change`, `inside-freeze`,
/// `unknown-dependency`, `dependency-order`, each at most once. `allowed` is
/// true exactly when `reasons` is empty.
///
/// Freezes and changes both block. A freeze never appears in
/// `change_conflicts`: freezes are reported through `freeze_ids`.
pub(all) struct ScheduleCheck {
  candidate : Slot
  allowed : Bool
  reasons : Array[String]
  change_conflicts : Array[SlotConflict]
  freeze_ids : Array[String]
}

///|
/// Render as `<ALLOWED|REJECTED> <start> -> <end> (<duration>)`, followed by
/// ` (<reasons joined by ,>)` when at least one rule fired.
///
/// For example
/// `REJECTED 2026-10-01T22:30 -> 2026-10-01T23:30 (1h) (blocked-by-change,inside-freeze)`.
pub fn ScheduleCheck::to_line(self : ScheduleCheck) -> String {
  let status = if self.allowed { "ALLOWED" } else { "REJECTED" }
  let head = status +
    " " +
    format_instant(self.candidate.start) +
    " -> " +
    format_instant(self.candidate.end) +
    " (" +
    format_duration(self.candidate.duration()) +
    ")"
  if self.reasons.length() == 0 {
    head
  } else {
    head + " (" + join(self.reasons, ",") + ")"
  }
}

///|
/// Decide whether a candidate interval may be added to the plan.
///
/// The rules are applied in a fixed order and each reason is reported at most
/// once:
///
/// - `no-duration`: the candidate is empty or reversed,
/// - `too-short`: shorter than `min_minutes`,
/// - `blocked-by-change`: it overlaps a planned change; a change that only
///   touches the candidate is not a conflict,
/// - `inside-freeze`: it overlaps a change freeze,
/// - `unknown-dependency`: one of `depends` is not a record of the plan,
/// - `dependency-order`: a dependency that exists ends after the candidate
///   starts. Ending exactly at the start is accepted, so a change may run back
///   to back with what it waits for.
///
/// Dependencies are read from the `depends` argument rather than from a record,
/// because the candidate is not in the plan yet.
pub fn can_schedule(
  plan : Plan,
  candidate : Slot,
  depends : Array[String],
  min_minutes : Int,
) -> ScheduleCheck {
  let reasons : Array[String] = []
  let duration = candidate.duration()
  if duration <= 0 {
    reasons.push("no-duration")
  } else if duration < min_minutes {
    reasons.push("too-short")
  }
  let conflicts : Array[SlotConflict] = []
  for change in plan.changes() {
    let minutes = overlap_minutes(
      change.start,
      change.end,
      candidate.start,
      candidate.end,
    )
    if minutes > 0 {
      conflicts.push({ window_id: change.id, minutes, })
    }
  }
  if conflicts.length() > 0 {
    reasons.push("blocked-by-change")
  }
  let freeze_ids : Array[String] = []
  for freeze in freezes_hit_by(plan, candidate) {
    freeze_ids.push(freeze.id)
  }
  if freeze_ids.length() > 0 {
    reasons.push("inside-freeze")
  }
  for dependency in depends {
    match plan.find(dependency) {
      None => push_unique_reason(reasons, "unknown-dependency")
      Some(window) =>
        if window.end > candidate.start {
          push_unique_reason(reasons, "dependency-order")
        }
    }
  }
  {
    candidate,
    allowed: reasons.length() == 0,
    reasons,
    change_conflicts: conflicts,
    freeze_ids,
  }
}

///|
/// Append a rule code unless it is already reported, which keeps each reason in
/// its first position and the list free of duplicates.
fn push_unique_reason(reasons : Array[String], reason : String) -> Unit {
  if !reasons.contains(reason) {
    reasons.push(reason)
  }
}

///|
/// Free function alias of `ScheduleCheck::to_line`.
pub fn schedule_check_line(check : ScheduleCheck) -> String {
  check.to_line()
}

///|
/// Build a `[start, end)` interval, so that callers do not have to name the
/// struct literal of `Slot`.
pub fn candidate_slot(start : Int, end : Int) -> Slot {
  { start, end, }
}

///|
/// Smallest slack, in minutes, that `id` has against its dependencies:
/// `change.start - dependency.end`.
///
/// A negative value means the dependency outlives the start of the dependent,
/// `0` means back to back. `None` when the record is not in the plan or when
/// none of its dependencies exists, because there is then nothing to measure.
pub fn slack_minutes(plan : Plan, id : String) -> Int? {
  let record = match plan.find(id) {
    Some(window) => window
    None => return None
  }
  let mut slack : Int? = None
  for dependency in record.depends {
    match plan.find(dependency) {
      None => ()
      Some(target) => {
        let value = record.start - target.end
        match slack {
          None => slack = Some(value)
          Some(current) => if value < current { slack = Some(value) }
        }
      }
    }
  }
  slack
}

///|
/// Earliest minute at or after `candidate.start` where an interval of the same
/// duration fits without overlapping a change or a freeze.
///
/// The walk never steps minute by minute across a blocked stretch: when the
/// current position is blocked it jumps to the end of the blocking interval, so
/// a long freeze is skipped in one step. The last position tried is
/// `candidate.start + search_minutes`.
///
/// `None` when the duration is not positive, when `min_minutes` is greater than
/// the duration, when `search_minutes` is negative, or when nothing fits inside
/// the search range. A zero `search_minutes` therefore asks the single question
/// "does the candidate fit where it is?".
pub fn earliest_start(
  plan : Plan,
  candidate : Slot,
  min_minutes : Int,
  search_minutes : Int,
) -> Int? {
  let duration = candidate.duration()
  if duration <= 0 || min_minutes > duration || search_minutes < 0 {
    return None
  }
  let limit = candidate.start + search_minutes
  let mut cursor = candidate.start
  while cursor <= limit {
    let probe = { start: cursor, end: cursor + duration, }
    if !schedule_is_blocked(plan, probe) {
      return Some(cursor)
    }
    let mut moved = cursor
    for window in plan.windows {
      if overlap_minutes(window.start, window.end, probe.start, probe.end) > 0 {
        if window.end > moved {
          moved = window.end
        }
      }
    }
    if moved <= cursor {
      cursor = cursor + 1
    } else {
      cursor = moved
    }
  }
  None
}

///|
/// One change of the compressed schedule.
///
/// `start`/`end` are the planned minutes, `original_start` the minute the plan
/// asked for and `shift_minutes` the delay that was added. The shift is never
/// negative: a change is never moved earlier than its original start.
pub(all) struct ScheduledChange {
  id : String
  start : Int
  end : Int
  original_start : Int
  shift_minutes : Int
}

///|
/// Render as `<id> <start> -> <end> (+<shift>)`, for example
/// `db 2026-10-01T19:00 -> 2026-10-01T20:00 (+0m)`.
pub fn ScheduledChange::to_line(self : ScheduledChange) -> String {
  self.id +
  " " +
  format_instant(self.start) +
  " -> " +
  format_instant(self.end) +
  " (+" +
  format_duration(self.shift_minutes) +
  ")"
}

///|
/// Compress the whole plan into the earliest dependency aware schedule.
///
/// Changes are processed in `execution_order`, and a change starts at the later
/// of its original start and the scheduled end of every dependency that exists
/// in the plan and was already scheduled. Duration and order are preserved, and
/// nothing is moved earlier, so the result is a valid schedule whenever the
/// original plan is acyclic.
///
/// `None` when the plan cannot be ordered, that is when it contains a cycle.
pub fn earliest_schedule(plan : Plan) -> Array[ScheduledChange]? {
  let order = match execution_order(plan) {
    Some(ids) => ids
    None => return None
  }
  let scheduled : Array[ScheduledChange] = []
  for id in order {
    match plan.find(id) {
      None => ()
      Some(window) => {
        let mut start = window.start
        // Dependencies already scheduled decide how far the start is pushed
        // forward. A dependency that is missing from the plan is simply not in
        // `scheduled`, and the audit reports it separately.
        for dependency in window.depends {
          for already in scheduled {
            if already.id == dependency && already.end > start {
              start = already.end
            }
          }
        }
        scheduled.push({
          id,
          start,
          end: start + window.duration(),
          original_start: window.start,
          shift_minutes: start - window.start,
        })
      }
    }
  }
  Some(scheduled)
}

///|
/// Render a schedule that is already known to be acyclic, one two space
/// indented line per change.
///
/// An empty schedule renders as `Earliest dependency aware schedule (0 changes)\n  (no changes)\n`.
pub fn render_schedule(schedule : Array[ScheduledChange]) -> String {
  let builder = StringBuilder()
  builder.write_string(
    "Earliest dependency aware schedule (" +
    count_text(schedule.length(), "change", "changes") +
    ")\n",
  )
  if schedule.length() == 0 {
    builder.write_string("  (no changes)\n")
  } else {
    for change in schedule {
      builder.write_string("  ")
      builder.write_string(change.to_line())
      builder.write_char('\n')
    }
  }
  builder.to_string()
}

///|
/// Render the result of `earliest_schedule`, including the cyclic case that the
/// schedule array itself cannot express.
///
/// - a schedule: `Earliest dependency aware schedule (<n> changes)` and one
///   indented line per change,
/// - `None`: `Earliest dependency aware schedule` and `  (cyclic)`,
/// - an empty schedule: `Earliest dependency aware schedule (0 changes)` and
///   `  (no changes)`.
///
/// The plan is not needed: `earliest_schedule` already turned it into the
/// schedule, and the cyclic case carries no per change detail.
/// The text always ends with exactly one newline.
pub fn render_schedule_result(schedule : Array[ScheduledChange]?) -> String {
  match schedule {
    None => "Earliest dependency aware schedule\n" + "  (cyclic)\n"
    Some(changes) => render_schedule(changes)
  }
}

///|
/// The first `limit` free slots of `safe_slots(plan, from, to, min_minutes)`, in
/// order.
///
/// The horizon is not extended to fill the limit: fewer slots are returned when
/// the plan leaves less room. `limit <= 0` yields an empty array.
pub fn next_slots(
  plan : Plan,
  from : Int,
  to : Int,
  min_minutes : Int,
  limit : Int,
) -> Array[Slot] {
  let found : Array[Slot] = []
  if limit <= 0 {
    return found
  }
  for slot in safe_slots(plan, from, to, min_minutes) {
    if found.length() >= limit {
      break
    }
    found.push(slot)
  }
  found
}
