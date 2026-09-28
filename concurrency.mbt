///|
/// Parallel change load.
///
/// These measurements ignore risk and dependencies: they count the records that
/// cover a minute, which is what a change calendar shows. They answer questions
/// like "how many changes run at 22:00", "when is the plan busiest" and "how
/// long do we keep more than two changes in flight".

///|
/// Highest number of changes that run at the same time.
pub(all) struct PeakConcurrency {
  minute : Int
  count : Int
}

///|
/// Render as `3 changes at 2026-10-01T22:00`.
pub fn PeakConcurrency::to_line(self : PeakConcurrency) -> String {
  self.count.to_string() + " changes at " + format_instant(self.minute)
}

///|
/// One sample of a load profile.
pub(all) struct LoadPoint {
  start : Int
  count : Int
}

///|
/// Render as `2026-10-01T22:00 load 3`.
pub fn LoadPoint::to_line(self : LoadPoint) -> String {
  format_instant(self.start) + " load " + self.count.to_string()
}

///|
/// Number of changes covering the minute.
///
/// Freezes are not changes, so they never raise this count.
pub fn concurrency_at(plan : Plan, minute : Int) -> Int {
  let mut count = 0
  for change in plan.changes() {
    if minute >= change.start && minute < change.end {
      count = count + 1
    }
  }
  count
}

///|
/// Number of changes of one service covering the minute. An empty service name
/// matches the changes that have no service.
pub fn service_concurrency_at(
  plan : Plan,
  service : String,
  minute : Int,
) -> Int {
  let mut count = 0
  for change in plan.changes() {
    if change.service == service &&
      minute >= change.start &&
      minute < change.end {
      count = count + 1
    }
  }
  count
}

///|
/// Highest number of simultaneous changes, or `None` for a plan without
/// changes.
///
/// The maximum can only be reached at the start of some change, so the search
/// walks the start minutes and breaks ties towards the earliest one. The answer
/// is therefore deterministic.
pub fn peak_concurrency(plan : Plan) -> PeakConcurrency? {
  let changes = plan.changes()
  if changes.length() == 0 {
    return None
  }
  let mut best : PeakConcurrency? = None
  for change in changes {
    let count = concurrency_at(plan, change.start)
    match best {
      None => best = Some({ minute: change.start, count, })
      Some(current) =>
        if count > current.count {
          best = Some({ minute: change.start, count, })
        }
    }
  }
  best
}

///|
/// Intervals during which at least `min_count` changes run at the same time,
/// merged and ordered.
///
/// `min_count` of `1` therefore returns the blocked intervals of the changes,
/// and a higher value narrows that down to the crowded part of the plan.
pub fn busiest_intervals(plan : Plan, min_count : Int) -> Array[Slot] {
  let boundaries : Array[Int] = []
  for change in plan.changes() {
    push_unique_int(boundaries, change.start)
    push_unique_int(boundaries, change.end)
  }
  let ordered = sorted_ints(boundaries)
  let crowded : Array[Slot] = []
  let mut index = 0
  while index + 1 < ordered.length() {
    let from = ordered[index]
    let to = ordered[index + 1]
    if to > from && concurrency_at(plan, from) >= min_count {
      crowded.push({ start: from, end: to, })
    }
    index = index + 1
  }
  merge_slots(crowded)
}

///|
/// Highest number of changes running at any minute inside the interval.
pub fn max_concurrency_in(plan : Plan, slot : Slot) -> Int {
  let mut best = 0
  for change in plan.changes() {
    let start = if change.start > slot.start {
      change.start
    } else {
      slot.start
    }
    if start < slot.end && start < change.end {
      let count = concurrency_at(plan, start)
      if count > best {
        best = count
      }
    }
  }
  best
}

///|
/// Sample the number of running changes every `step_minutes` from `from` while
/// the sample stays before `to`.
///
/// A step of zero or less produces no samples. Sampling stops after 10000
/// points so that a long horizon with a tiny step cannot build an unbounded
/// array; the caller keeps control of the cost by choosing the step.
pub fn load_profile(
  plan : Plan,
  from : Int,
  to : Int,
  step_minutes : Int,
) -> Array[LoadPoint] {
  let points : Array[LoadPoint] = []
  if step_minutes <= 0 || to <= from {
    return points
  }
  let mut minute = from
  while minute < to && points.length() < 10000 {
    points.push({ start: minute, count: concurrency_at(plan, minute), })
    minute = minute + step_minutes
  }
  points
}

///|
/// Total length of every change, counting minutes shared by several changes
/// once per change.
///
/// This is the workload the plan asks for, while `blocked_minutes` is the
/// calendar time it occupies.
pub fn change_minutes(plan : Plan) -> Int {
  let mut total = 0
  for change in plan.changes() {
    total = total + change.duration()
  }
  total
}

///|
/// Total length of every freeze, counting shared minutes once per freeze.
pub fn freeze_minutes(plan : Plan) -> Int {
  let mut total = 0
  for freeze in plan.freezes() {
    total = total + freeze.duration()
  }
  total
}
