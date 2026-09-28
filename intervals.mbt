///|
/// Interval algebra behind blocking, free time and set operations.
///
/// Every interval is half open: `[start, end)`. Two intervals that only touch,
/// for example `22:00-23:00` and `23:00-00:00`, do not overlap, and they merge
/// into one interval because no change can run in between.
///
/// Everything here is deterministic: intervals are ordered with a stable
/// insertion sort, so equal intervals keep their input order and no report
/// depends on a library sort order.

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
pub fn sort_slots(slots : Array[Slot]) -> Array[Slot] {
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
/// Copy integers in ascending order, keeping duplicates adjacent.
fn sorted_ints(values : Array[Int]) -> Array[Int] {
  let ordered : Array[Int] = []
  for value in values {
    ordered.push(value)
  }
  let mut index = 1
  while index < ordered.length() {
    let current = ordered[index]
    let mut position = index
    while position > 0 && ordered[position - 1] > current {
      ordered[position] = ordered[position - 1]
      position = position - 1
    }
    ordered[position] = current
    index = index + 1
  }
  ordered
}

///|
/// Append the value unless it is already present.
fn push_unique_int(values : Array[Int], value : Int) -> Unit {
  if !values.contains(value) {
    values.push(value)
  }
}

///|
/// True when the minute lies inside the interval.
pub fn Slot::contains(self : Slot, minute : Int) -> Bool {
  minute >= self.start && minute < self.end
}

///|
/// True when `other` lies completely inside `self`.
pub fn Slot::contains_slot(self : Slot, other : Slot) -> Bool {
  other.start >= self.start && other.end <= self.end
}

///|
/// True when the two intervals share at least one minute.
pub fn Slot::overlaps(self : Slot, other : Slot) -> Bool {
  self.start < other.end && other.start < self.end
}

///|
/// True when the two intervals overlap or are adjacent, so that no minute can
/// be scheduled between them.
pub fn Slot::touches(self : Slot, other : Slot) -> Bool {
  other.start <= self.end && self.start <= other.end
}

///|
/// The shared part of two intervals, or `None` when they do not overlap.
pub fn Slot::intersect(self : Slot, other : Slot) -> Slot? {
  let start = if self.start > other.start { self.start } else { other.start }
  let end = if self.end < other.end { self.end } else { other.end }
  if end > start {
    Some({ start, end, })
  } else {
    None
  }
}

///|
/// The smallest interval covering both, or `None` when a gap stays between
/// them.
pub fn Slot::merge_with(self : Slot, other : Slot) -> Slot? {
  if !self.touches(other) {
    return None
  }
  let start = if self.start < other.start { self.start } else { other.start }
  let end = if self.end > other.end { self.end } else { other.end }
  Some({ start, end, })
}

///|
/// Shrink an interval to the part inside `[from, to)`.
pub fn clip_slot(slot : Slot, from : Int, to : Int) -> Slot? {
  let start = if slot.start > from { slot.start } else { from }
  let end = if slot.end < to { slot.end } else { to }
  if end > start {
    Some({ start, end, })
  } else {
    None
  }
}

///|
/// Merge overlapping or touching intervals into a minimal ordered list.
pub fn merge_slots(slots : Array[Slot]) -> Array[Slot] {
  let merged : Array[Slot] = []
  for slot in sort_slots(slots) {
    if merged.is_empty() {
      merged.push(slot)
      continue
    }
    let last = merged[merged.length() - 1]
    match last.merge_with(slot) {
      Some(cover) => merged[merged.length() - 1] = cover
      None => merged.push(slot)
    }
  }
  merged
}

///|
/// Sum of the lengths of the given intervals.
///
/// Call it on the result of `merge_slots` to measure a union; on raw intervals
/// it counts shared minutes as often as they appear.
pub fn total_duration(slots : Array[Slot]) -> Int {
  let mut total = 0
  for slot in slots {
    total = total + slot.duration()
  }
  total
}

///|
/// First interval that contains the minute, or `None`.
pub fn slot_at(slots : Array[Slot], minute : Int) -> Slot? {
  for slot in slots {
    if slot.contains(minute) {
      return Some(slot)
    }
  }
  None
}

///|
/// Parts of `[from, to)` that no interval covers.
///
/// Returns an empty array when `to <= from`.
pub fn invert_slots(slots : Array[Slot], from : Int, to : Int) -> Array[Slot] {
  if to <= from {
    return []
  }
  let clipped : Array[Slot] = []
  for slot in slots {
    match clip_slot(slot, from, to) {
      Some(part) => clipped.push(part)
      None => ()
    }
  }
  let gaps : Array[Slot] = []
  let mut cursor = from
  for block in merge_slots(clipped) {
    if block.start > cursor {
      gaps.push({ start: cursor, end: block.start, })
    }
    if block.end > cursor {
      cursor = block.end
    }
  }
  if to > cursor {
    gaps.push({ start: cursor, end: to, })
  }
  gaps
}

///|
/// Shared parts of two interval sets, both merged first.
pub fn intersect_slots(left : Array[Slot], right : Array[Slot]) -> Array[Slot] {
  let first = merge_slots(left)
  let second = merge_slots(right)
  let shared : Array[Slot] = []
  let mut left_index = 0
  let mut right_index = 0
  while left_index < first.length() && right_index < second.length() {
    let a = first[left_index]
    let b = second[right_index]
    match a.intersect(b) {
      Some(part) => shared.push(part)
      None => ()
    }
    if a.end <= b.end {
      left_index = left_index + 1
    } else {
      right_index = right_index + 1
    }
  }
  shared
}

///|
/// Interval set difference: every part of `left` that `right` does not cover.
pub fn subtract_slots(left : Array[Slot], right : Array[Slot]) -> Array[Slot] {
  let first = merge_slots(left)
  let second = merge_slots(right)
  let remaining : Array[Slot] = []
  for slot in first {
    let mut cursor = slot.start
    for cut in second {
      if cut.end <= cursor {
        continue
      }
      if cut.start >= slot.end {
        break
      }
      if cut.start > cursor {
        remaining.push({ start: cursor, end: cut.start, })
      }
      if cut.end > cursor {
        cursor = cut.end
      }
    }
    if cursor < slot.end {
      remaining.push({ start: cursor, end: slot.end, })
    }
  }
  remaining
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
  total_duration(blocked_intervals(plan))
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
  let windows : Array[Slot] = []
  for window in plan.windows {
    windows.push({ start: window.start, end: window.end, })
  }
  let slots : Array[Slot] = []
  for gap in invert_slots(windows, from, to) {
    if gap.duration() >= min_minutes {
      slots.push(gap)
    }
  }
  slots
}
