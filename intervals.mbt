///|
/// Interval arithmetic behind `blocked_intervals` and `safe_slots`.
///
/// Every interval is half open: `[start, end)`. Two intervals that only touch,
/// for example `22:00-23:00` and `23:00-00:00`, do not overlap and are still
/// merged into one blocking interval, because no change can run in between.

///|
/// True when `left` should be ordered before `right`.
fn comes_before(left : Slot, right : Slot) -> Bool {
  if left.start != right.start {
    return left.start < right.start
  }
  left.end < right.end
}

///|
/// Copy intervals ordered by start minute, then by end minute.
///
/// A stable insertion sort keeps equal intervals in input order, which makes
/// every report reproducible without depending on a library sort.
fn sort_slots(slots : Array[Slot]) -> Array[Slot] {
  let ordered : Array[Slot] = []
  for slot in slots {
    ordered.push(slot)
  }
  let mut index = 1
  while index < ordered.length() {
    let current = ordered[index]
    let mut position = index
    while position > 0 && comes_before(current, ordered[position - 1]) {
      ordered[position] = ordered[position - 1]
      position = position - 1
    }
    ordered[position] = current
    index = index + 1
  }
  ordered
}

///|
/// Merge overlapping or touching intervals into a minimal ordered list.
fn merge_slots(slots : Array[Slot]) -> Array[Slot] {
  let merged : Array[Slot] = []
  for slot in sort_slots(slots) {
    if merged.is_empty() {
      merged.push(slot)
      continue
    }
    let last = merged[merged.length() - 1]
    if slot.start <= last.end {
      if slot.end > last.end {
        merged[merged.length() - 1] = { start: last.start, end: slot.end, }
      }
    } else {
      merged.push(slot)
    }
  }
  merged
}

///|
/// Blocking intervals of every window in the plan, merged and sorted.
///
/// Overlapping windows are counted once, so the result is the real set of
/// minutes during which at least one planned change is running.
pub fn blocked_intervals(plan : Plan) -> Array[Slot] {
  let slots : Array[Slot] = []
  for window in plan.windows {
    slots.push({ start: window.start, end: window.end, })
  }
  merge_slots(slots)
}

///|
/// Total minutes blocked by the plan, counting overlapping windows once.
pub fn blocked_minutes(plan : Plan) -> Int {
  let mut total = 0
  for slot in blocked_intervals(plan) {
    total = total + slot.duration()
  }
  total
}

///|
/// Slots inside `[from, to)` where a new change can run, each at least
/// `min_minutes` long.
///
/// Windows are clipped to the horizon, so a window that starts before `from`
/// still blocks the beginning of the horizon and a window that ends after `to`
/// blocks the end. Returns an empty array when `to <= from`.
///
/// The result ignores dependencies: a free slot is free of the windows in the
/// plan, not necessarily of the changes that would have to precede a new one.
pub fn safe_slots(
  plan : Plan,
  from : Int,
  to : Int,
  min_minutes : Int,
) -> Array[Slot] {
  if to <= from {
    return []
  }
  let clipped : Array[Slot] = []
  for window in plan.windows {
    let start = if window.start > from { window.start } else { from }
    let end = if window.end < to { window.end } else { to }
    if end > start {
      clipped.push({ start, end, })
    }
  }
  let slots : Array[Slot] = []
  let mut cursor = from
  for block in merge_slots(clipped) {
    if block.start > cursor {
      let gap = { start: cursor, end: block.start, }
      if gap.duration() >= min_minutes {
        slots.push(gap)
      }
    }
    if block.end > cursor {
      cursor = block.end
    }
  }
  if to > cursor {
    let gap = { start: cursor, end: to, }
    if gap.duration() >= min_minutes {
      slots.push(gap)
    }
  }
  slots
}
