///|
/// Tests for the interval algebra: membership, intersection, difference and
/// complements.

///|
test "contains works on the half open interval" {
  let interval = slot_of("2026-10-01T22:00", "2026-10-01T23:00")
  assert_true(!interval.contains(instant_of("2026-10-01T21:59")))
  assert_true(interval.contains(instant_of("2026-10-01T22:00")))
  assert_true(interval.contains(instant_of("2026-10-01T22:59")))
  assert_true(!interval.contains(instant_of("2026-10-01T23:00")))
  assert_eq(interval.duration(), 60)
}

///|
test "contains_slot accepts equal and inner intervals only" {
  let outer = slot_of("2026-10-01T22:00", "2026-10-01T23:00")
  assert_true(outer.contains_slot(outer))
  assert_true(
    outer.contains_slot(slot_of("2026-10-01T22:15", "2026-10-01T22:45")),
  )
  assert_true(
    !outer.contains_slot(slot_of("2026-10-01T21:45", "2026-10-01T22:45")),
  )
  assert_true(
    !outer.contains_slot(slot_of("2026-10-01T22:45", "2026-10-01T23:15")),
  )
}

///|
test "overlaps and touches differ at the boundary" {
  let first = slot_of("2026-10-01T22:00", "2026-10-01T23:00")
  let next = slot_of("2026-10-01T23:00", "2026-10-02T00:00")
  let inside = slot_of("2026-10-01T22:30", "2026-10-01T23:30")
  assert_true(!first.overlaps(next))
  assert_true(first.touches(next))
  assert_true(first.overlaps(inside))
  assert_true(first.touches(inside))
  assert_true(!first.touches(slot_of("2026-10-01T23:01", "2026-10-02T00:00")))
}

///|
test "intersect returns the shared part or nothing" {
  let first = slot_of("2026-10-01T22:00", "2026-10-01T23:00")
  let second = slot_of("2026-10-01T22:30", "2026-10-01T23:30")
  match first.intersect(second) {
    Some(shared) => {
      assert_eq(shared.start, instant_of("2026-10-01T22:30"))
      assert_eq(shared.end, instant_of("2026-10-01T23:00"))
      assert_eq(shared.duration(), 30)
      assert_eq(shared.to_line(), "2026-10-01T22:30 -> 2026-10-01T23:00 (30m)")
    }
    None => fail("expected an intersection")
  }
  match first.intersect(slot_of("2026-10-01T23:00", "2026-10-02T00:00")) {
    Some(_) => fail("touching intervals do not intersect")
    None => ()
  }
}

///|
test "merge_with joins touching intervals and keeps gaps apart" {
  let first = slot_of("2026-10-01T22:00", "2026-10-01T23:00")
  match first.merge_with(slot_of("2026-10-01T23:00", "2026-10-02T00:00")) {
    Some(joined) =>
      assert_eq(joined.to_line(), "2026-10-01T22:00 -> 2026-10-02T00:00 (2h)")
    None => fail("touching intervals should merge")
  }
  match first.merge_with(slot_of("2026-10-01T23:30", "2026-10-02T00:00")) {
    Some(_) => fail("intervals with a gap should not merge")
    None => ()
  }
}

///|
test "clip_slot shortens and sometimes drops an interval" {
  match
    @moon-change-window-auditor.clip_slot(
      slot_of("2026-10-01T20:00", "2026-10-01T22:00"),
      instant_of("2026-10-01T21:00"),
      instant_of("2026-10-02T00:00"),
    ) {
    Some(part) =>
      assert_eq(part.to_line(), "2026-10-01T21:00 -> 2026-10-01T22:00 (1h)")
    None => fail("expected a clipped interval")
  }
  match
    @moon-change-window-auditor.clip_slot(
      slot_of("2026-10-01T18:00", "2026-10-01T19:00"),
      instant_of("2026-10-01T21:00"),
      instant_of("2026-10-02T00:00"),
    ) {
    Some(_) => fail("an interval outside the horizon clips to nothing")
    None => ()
  }
}

///|
test "merge_slots sorts and joins overlapping and touching input" {
  let merged = @moon-change-window-auditor.merge_slots([
    slot_of("2026-10-01T23:15", "2026-10-01T23:45"),
    slot_of("2026-10-01T22:00", "2026-10-01T23:00"),
    slot_of("2026-10-01T22:30", "2026-10-01T23:15"),
    slot_of("2026-10-02T02:00", "2026-10-02T03:00"),
  ])
  assert_eq(merged.length(), 2)
  assert_eq(merged[0].to_line(), "2026-10-01T22:00 -> 2026-10-01T23:45 (1h45m)")
  assert_eq(merged[1].to_line(), "2026-10-02T02:00 -> 2026-10-02T03:00 (1h)")
  assert_eq(@moon-change-window-auditor.total_duration(merged), 165)
}

///|
test "total_duration counts raw intervals as they are" {
  let raw = [
    slot_of("2026-10-01T22:00", "2026-10-01T23:00"),
    slot_of("2026-10-01T22:30", "2026-10-01T23:30"),
  ]
  assert_eq(@moon-change-window-auditor.total_duration(raw), 120)
  assert_eq(
    @moon-change-window-auditor.total_duration(
      @moon-change-window-auditor.merge_slots(raw),
    ),
    90,
  )
}

///|
test "sort_slots orders by start and keeps equal starts by end" {
  let ordered = @moon-change-window-auditor.sort_slots([
    slot_of("2026-10-01T23:00", "2026-10-02T00:00"),
    slot_of("2026-10-01T22:00", "2026-10-01T23:30"),
    slot_of("2026-10-01T22:00", "2026-10-01T22:30"),
  ])
  assert_eq(ordered[0].to_line(), "2026-10-01T22:00 -> 2026-10-01T22:30 (30m)")
  assert_eq(
    ordered[1].to_line(),
    "2026-10-01T22:00 -> 2026-10-01T23:30 (1h30m)",
  )
  assert_eq(ordered[2].to_line(), "2026-10-01T23:00 -> 2026-10-02T00:00 (1h)")
}

///|
test "slot_at finds the interval containing a minute" {
  let slots = [
    slot_of("2026-10-01T20:00", "2026-10-01T21:00"),
    slot_of("2026-10-01T22:00", "2026-10-01T23:00"),
  ]
  match
    @moon-change-window-auditor.slot_at(slots, instant_of("2026-10-01T22:30")) {
    Some(found) =>
      assert_eq(found.to_line(), "2026-10-01T22:00 -> 2026-10-01T23:00 (1h)")
    None => fail("expected to find the interval")
  }
  assert_true(
    @moon-change-window-auditor.slot_at(slots, instant_of("2026-10-01T21:30"))
    is None,
  )
  assert_true(
    @moon-change-window-auditor.slot_at(slots, instant_of("2026-10-01T23:00"))
    is None,
  )
}

///|
test "invert_slots returns the gaps inside a horizon" {
  let gaps = @moon-change-window-auditor.invert_slots(
    [
      slot_of("2026-10-01T19:00", "2026-10-01T21:00"),
      slot_of("2026-10-01T22:00", "2026-10-02T01:00"),
    ],
    instant_of("2026-10-01T20:00"),
    instant_of("2026-10-02T02:00"),
  )
  assert_eq(gaps.length(), 2)
  assert_eq(gaps[0].to_line(), "2026-10-01T21:00 -> 2026-10-01T22:00 (1h)")
  assert_eq(gaps[1].to_line(), "2026-10-02T01:00 -> 2026-10-02T02:00 (1h)")
  assert_eq(
    @moon-change-window-auditor.invert_slots(
      [],
      instant_of("2026-10-01T20:00"),
      instant_of("2026-10-01T21:00"),
    ).length(),
    1,
  )
  assert_eq(
    @moon-change-window-auditor.invert_slots(
      [],
      instant_of("2026-10-01T21:00"),
      instant_of("2026-10-01T20:00"),
    ).length(),
    0,
  )
}

///|
test "intersect_slots keeps only the shared minutes" {
  let shared = @moon-change-window-auditor.intersect_slots(
    [
      slot_of("2026-10-01T22:00", "2026-10-01T23:00"),
      slot_of("2026-10-02T02:00", "2026-10-02T03:00"),
    ],
    [
      slot_of("2026-10-01T22:30", "2026-10-01T22:45"),
      slot_of("2026-10-02T02:30", "2026-10-02T04:00"),
    ],
  )
  assert_eq(shared.length(), 2)
  assert_eq(shared[0].to_line(), "2026-10-01T22:30 -> 2026-10-01T22:45 (15m)")
  assert_eq(shared[1].to_line(), "2026-10-02T02:30 -> 2026-10-02T03:00 (30m)")
  assert_eq(
    @moon-change-window-auditor.intersect_slots(
      [slot_of("2026-10-01T22:00", "2026-10-01T23:00")],
      [slot_of("2026-10-02T02:00", "2026-10-02T03:00")],
    ).length(),
    0,
  )
}

///|
test "subtract_slots cuts holes out of an interval set" {
  let remaining = @moon-change-window-auditor.subtract_slots(
    [slot_of("2026-10-01T20:00", "2026-10-02T00:00")],
    [slot_of("2026-10-01T21:00", "2026-10-01T22:00")],
  )
  assert_eq(remaining.length(), 2)
  assert_eq(remaining[0].to_line(), "2026-10-01T20:00 -> 2026-10-01T21:00 (1h)")
  assert_eq(remaining[1].to_line(), "2026-10-01T22:00 -> 2026-10-02T00:00 (2h)")
  // A cut that covers the whole interval leaves nothing behind.
  assert_eq(
    @moon-change-window-auditor.subtract_slots(
      [slot_of("2026-10-01T21:00", "2026-10-01T22:00")],
      [slot_of("2026-10-01T20:00", "2026-10-01T23:00")],
    ).length(),
    0,
  )
  // A cut that misses the interval changes nothing.
  assert_eq(
    @moon-change-window-auditor.subtract_slots(
      [slot_of("2026-10-01T21:00", "2026-10-01T22:00")],
      [slot_of("2026-10-02T20:00", "2026-10-02T23:00")],
    ).length(),
    1,
  )
}

///|
test "safe_slots agrees with inverting the blocked intervals" {
  let plan = plan_of(
    "id=a;start=2026-10-01T22:00;end=2026-10-01T23:00\n" +
    "id=b;start=2026-10-02T00:00;end=2026-10-02T01:00\n",
  )
  let from = instant_of("2026-10-01T20:00")
  let to = instant_of("2026-10-02T02:00")
  let windows : Array[@moon-change-window-auditor.Slot] = []
  for window in plan.windows {
    windows.push({ start: window.start, end: window.end, })
  }
  let manual = @moon-change-window-auditor.invert_slots(windows, from, to)
  let automatic = @moon-change-window-auditor.safe_slots(plan, from, to, 0)
  assert_eq(manual.length(), automatic.length())
  let mut index = 0
  while index < manual.length() {
    assert_eq(manual[index].to_line(), automatic[index].to_line())
    index = index + 1
  }
}
