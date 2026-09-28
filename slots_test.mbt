///|
/// Tests for blocking intervals and safe change slots.

///|
test "blocking intervals merge overlaps and touching windows" {
  let plan = plan_of(
    "id=a;start=2026-10-01T22:00;end=2026-10-01T23:00\n" +
    "id=b;start=2026-10-01T22:30;end=2026-10-01T23:15\n" +
    "id=c;start=2026-10-01T23:15;end=2026-10-01T23:45\n" +
    "id=d;start=2026-10-02T02:00;end=2026-10-02T03:00\n",
  )
  let blocks = @moon-change-window-auditor.blocked_intervals(plan)
  assert_eq(blocks.length(), 2)
  assert_eq(blocks[0].start, instant_of("2026-10-01T22:00"))
  assert_eq(blocks[0].end, instant_of("2026-10-01T23:45"))
  assert_eq(blocks[1].start, instant_of("2026-10-02T02:00"))
  assert_eq(blocks[1].end, instant_of("2026-10-02T03:00"))
  assert_eq(@moon-change-window-auditor.blocked_minutes(plan), 165)
}

///|
test "a plan without windows leaves the whole horizon free" {
  let plan = plan_of("")
  let slots = @moon-change-window-auditor.safe_slots(
    plan,
    instant_of("2026-10-01T20:00"),
    instant_of("2026-10-02T02:00"),
    30,
  )
  assert_eq(slots.length(), 1)
  assert_eq(slots[0].to_line(), "2026-10-01T20:00 -> 2026-10-02T02:00 (6h)")
}

///|
test "safe slots are the gaps between windows" {
  let plan = plan_of(
    "id=a;start=2026-10-01T22:00;end=2026-10-01T23:00\n" +
    "id=b;start=2026-10-02T00:00;end=2026-10-02T01:00\n",
  )
  let slots = @moon-change-window-auditor.safe_slots(
    plan,
    instant_of("2026-10-01T20:00"),
    instant_of("2026-10-02T02:00"),
    30,
  )
  assert_eq(slots.length(), 3)
  assert_eq(slots[0].to_line(), "2026-10-01T20:00 -> 2026-10-01T22:00 (2h)")
  assert_eq(slots[1].to_line(), "2026-10-01T23:00 -> 2026-10-02T00:00 (1h)")
  assert_eq(slots[2].to_line(), "2026-10-02T01:00 -> 2026-10-02T02:00 (1h)")
}

///|
test "slots shorter than the requested length are dropped" {
  let plan = plan_of(
    "id=a;start=2026-10-01T22:00;end=2026-10-01T23:00\n" +
    "id=b;start=2026-10-01T23:20;end=2026-10-02T01:00\n",
  )
  // The horizon is chosen so that the only gaps are 20 and 30 minutes wide.
  let horizon_from = instant_of("2026-10-01T22:00")
  let horizon_to = instant_of("2026-10-02T01:30")
  let loose = @moon-change-window-auditor.safe_slots(
    plan, horizon_from, horizon_to, 15,
  )
  assert_eq(loose.length(), 2)
  assert_eq(loose[0].to_line(), "2026-10-01T23:00 -> 2026-10-01T23:20 (20m)")
  assert_eq(loose[1].to_line(), "2026-10-02T01:00 -> 2026-10-02T01:30 (30m)")
  let strict = @moon-change-window-auditor.safe_slots(
    plan, horizon_from, horizon_to, 25,
  )
  // Only the 30 minute gap survives.
  assert_eq(strict.length(), 1)
  assert_eq(strict[0].to_line(), "2026-10-02T01:00 -> 2026-10-02T01:30 (30m)")
  let impossible = @moon-change-window-auditor.safe_slots(
    plan, horizon_from, horizon_to, 31,
  )
  assert_eq(impossible.length(), 0)
}

///|
test "windows are clipped to the horizon" {
  let plan = plan_of(
    "id=before;start=2026-10-01T18:00;end=2026-10-01T21:00\n" +
    "id=after;start=2026-10-02T01:30;end=2026-10-02T04:00\n",
  )
  let slots = @moon-change-window-auditor.safe_slots(
    plan,
    instant_of("2026-10-01T20:00"),
    instant_of("2026-10-02T02:00"),
    30,
  )
  assert_eq(slots.length(), 1)
  assert_eq(slots[0].to_line(), "2026-10-01T21:00 -> 2026-10-02T01:30 (4h30m)")
}

///|
test "windows outside the horizon are ignored" {
  let plan = plan_of(
    "id=other-day;start=2026-10-05T22:00;end=2026-10-05T23:00\n",
  )
  let slots = @moon-change-window-auditor.safe_slots(
    plan,
    instant_of("2026-10-01T20:00"),
    instant_of("2026-10-01T22:00"),
    30,
  )
  assert_eq(slots.length(), 1)
  assert_eq(slots[0].to_line(), "2026-10-01T20:00 -> 2026-10-01T22:00 (2h)")
}

///|
test "a fully blocked horizon has no safe slot" {
  let plan = plan_of(
    "id=a;start=2026-10-01T20:00;end=2026-10-01T22:00\n" +
    "id=b;start=2026-10-01T22:00;end=2026-10-02T02:00\n",
  )
  let slots = @moon-change-window-auditor.safe_slots(
    plan,
    instant_of("2026-10-01T20:00"),
    instant_of("2026-10-02T02:00"),
    1,
  )
  assert_eq(slots.length(), 0)
}

///|
test "an empty or reversed horizon has no slot" {
  let plan = plan_of("id=a;start=2026-10-01T22:00;end=2026-10-01T23:00\n")
  let same = instant_of("2026-10-01T22:00")
  assert_eq(
    @moon-change-window-auditor.safe_slots(plan, same, same, 1).length(),
    0,
  )
  let reversed = @moon-change-window-auditor.safe_slots(
    plan,
    instant_of("2026-10-02T00:00"),
    instant_of("2026-10-01T00:00"),
    1,
  )
  assert_eq(reversed.length(), 0)
}

///|
test "a minimum of zero minutes keeps every gap" {
  let plan = plan_of(
    "id=a;start=2026-10-01T21:00;end=2026-10-01T22:00\n" +
    "id=b;start=2026-10-01T23:00;end=2026-10-02T00:00\n",
  )
  let slots = @moon-change-window-auditor.safe_slots(
    plan,
    instant_of("2026-10-01T20:00"),
    instant_of("2026-10-02T01:00"),
    0,
  )
  assert_eq(slots.length(), 3)
}

///|
test "safe slots are ordered even when windows are not" {
  let plan = plan_of(
    "id=late;start=2026-10-01T23:00;end=2026-10-01T23:30\n" +
    "id=early;start=2026-10-01T21:00;end=2026-10-01T21:30\n",
  )
  let slots = @moon-change-window-auditor.safe_slots(
    plan,
    instant_of("2026-10-01T20:00"),
    instant_of("2026-10-02T00:00"),
    10,
  )
  assert_eq(slots.length(), 3)
  assert_eq(slots[0].to_line(), "2026-10-01T20:00 -> 2026-10-01T21:00 (1h)")
  assert_eq(slots[1].to_line(), "2026-10-01T21:30 -> 2026-10-01T23:00 (1h30m)")
  assert_eq(slots[2].to_line(), "2026-10-01T23:30 -> 2026-10-02T00:00 (30m)")
}
