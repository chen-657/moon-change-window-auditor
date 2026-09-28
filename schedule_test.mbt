///|
/// Tests for the scheduling layer: candidate checks, slack, earliest starts,
/// the compressed schedule and its rendering.

///|
/// The verdict for one candidate interval of a plan given in text form.
fn schedule_check(
  source : String,
  start : String,
  end : String,
  depends : Array[String],
  min_minutes : Int,
) -> @moon-change-window-auditor.ScheduleCheck raise {
  @moon-change-window-auditor.can_schedule(
    plan_of(source),
    slot_of(start, end),
    depends,
    min_minutes,
  )
}

///|
/// The reason codes of a check, joined with `,`, to pin rule order.
fn schedule_reasons(
  check : @moon-change-window-auditor.ScheduleCheck,
) -> String {
  let builder = StringBuilder()
  for index = 0; index < check.reasons.length(); index = index + 1 {
    if index > 0 {
      builder.write_char(',')
    }
    builder.write_string(check.reasons[index])
  }
  builder.to_string()
}

///|
/// The conflicting changes of a check rendered as `id: 45m` entries.
fn schedule_conflict_text(
  check : @moon-change-window-auditor.ScheduleCheck,
) -> String {
  let builder = StringBuilder()
  for index = 0; index < check.change_conflicts.length(); index = index + 1 {
    if index > 0 {
      builder.write_string(", ")
    }
    builder.write_string(check.change_conflicts[index].to_line())
  }
  builder.to_string()
}

///|
/// The freeze ids of a check, joined with `,` in the order they were reported.
fn schedule_freeze_text(
  check : @moon-change-window-auditor.ScheduleCheck,
) -> String {
  let builder = StringBuilder()
  for index = 0; index < check.freeze_ids.length(); index = index + 1 {
    if index > 0 {
      builder.write_char(',')
    }
    builder.write_string(check.freeze_ids[index])
  }
  builder.to_string()
}

///|
/// The compressed schedule of a plan, failing when the plan is cyclic.
fn schedule_of(
  source : String,
) -> Array[@moon-change-window-auditor.ScheduledChange] raise {
  match @moon-change-window-auditor.earliest_schedule(plan_of(source)) {
    Some(schedule) => schedule
    None => fail("expected this plan to be schedulable: " + source)
  }
}

///|
/// Number of newline characters at the very end of a rendered text.
fn schedule_trailing_newlines(text : String) -> Int {
  let characters = text.iter().to_array()
  let mut total = 0
  let mut index = characters.length() - 1
  while index >= 0 && characters[index] == '\n' {
    total = total + 1
    index = index - 1
  }
  total
}

///|
test "a candidate that overlaps nothing is allowed" {
  let source = "id=db;service=orders;start=2026-10-01T20:00;end=2026-10-01T21:00\n"
  let check = schedule_check(
    source,
    "2026-10-01T18:00",
    "2026-10-01T19:00",
    [],
    0,
  )
  assert_true(check.allowed)
  assert_eq(check.reasons.length(), 0)
  assert_eq(check.change_conflicts.length(), 0)
  assert_eq(check.freeze_ids.length(), 0)
  assert_eq(check.candidate.start, instant_of("2026-10-01T18:00"))
  assert_eq(check.candidate.end, instant_of("2026-10-01T19:00"))
}

///|
test "a change that only touches the candidate is not a conflict" {
  let source = "id=db;start=2026-10-01T20:00;end=2026-10-01T21:00\n"
  // Starts exactly when the change ends.
  let after = schedule_check(
    source,
    "2026-10-01T21:00",
    "2026-10-01T22:00",
    [],
    0,
  )
  assert_true(after.allowed)
  assert_eq(after.change_conflicts.length(), 0)
  // Ends exactly when the change starts.
  let before = schedule_check(
    source,
    "2026-10-01T19:00",
    "2026-10-01T20:00",
    [],
    0,
  )
  assert_true(before.allowed)
  assert_eq(before.change_conflicts.length(), 0)
}

///|
test "the reason codes are reported in the documented order" {
  let source = "id=late;service=orders;start=2026-10-01T20:00;end=2026-10-01T21:30\n" +
    "kind=freeze;id=blackout;start=2026-10-01T21:00;end=2026-10-01T23:00\n"
  let strict = schedule_check(
    source,
    "2026-10-01T21:00",
    "2026-10-01T21:45",
    ["ghost", "late"],
    60,
  )
  assert_eq(
    schedule_reasons(strict),
    "too-short,blocked-by-change,inside-freeze,unknown-dependency,dependency-order",
  )
  assert_true(!strict.allowed)
  // Without the minimum the length rule drops out but the order is unchanged.
  let loose = schedule_check(
    source,
    "2026-10-01T21:00",
    "2026-10-01T21:45",
    ["ghost", "late"],
    0,
  )
  assert_eq(
    schedule_reasons(loose),
    "blocked-by-change,inside-freeze,unknown-dependency,dependency-order",
  )
}

///|
test "a candidate without duration reports no-duration first" {
  let source = "id=db;start=2026-10-01T20:00;end=2026-10-01T21:00\n"
  let empty = schedule_check(
    source,
    "2026-10-01T21:00",
    "2026-10-01T21:00",
    ["ghost"],
    0,
  )
  assert_eq(schedule_reasons(empty), "no-duration,unknown-dependency")
  assert_true(!empty.allowed)
  let reversed = schedule_check(
    source,
    "2026-10-01T22:00",
    "2026-10-01T21:00",
    [],
    0,
  )
  assert_eq(schedule_reasons(reversed), "no-duration")
  assert_eq(reversed.candidate.duration(), -60)
}

///|
test "too-short fires below the minimum and not at it" {
  let source = "id=other;start=2026-10-05T20:00;end=2026-10-05T21:00\n"
  let at_limit = schedule_check(
    source,
    "2026-10-01T21:00",
    "2026-10-01T21:30",
    [],
    30,
  )
  assert_true(at_limit.allowed)
  assert_eq(schedule_reasons(at_limit), "")
  let below = schedule_check(
    source,
    "2026-10-01T21:00",
    "2026-10-01T21:30",
    [],
    31,
  )
  assert_eq(schedule_reasons(below), "too-short")
  assert_true(!below.allowed)
}

///|
test "blocked-by-change lists every conflicting change with its minutes" {
  let source = "id=a;start=2026-10-01T20:00;end=2026-10-01T21:00\n" +
    "id=b;start=2026-10-01T20:30;end=2026-10-01T22:00\n"
  let check = schedule_check(
    source,
    "2026-10-01T20:45",
    "2026-10-01T21:30",
    [],
    0,
  )
  assert_eq(schedule_reasons(check), "blocked-by-change")
  assert_eq(check.change_conflicts.length(), 2)
  assert_eq(schedule_conflict_text(check), "a: 15m, b: 45m")
}

///|
test "a freeze is reported through freeze_ids and not as a change conflict" {
  let source = "kind=freeze;id=blackout;start=2026-10-01T21:00;end=2026-10-01T23:00\n"
  let check = schedule_check(
    source,
    "2026-10-01T21:30",
    "2026-10-01T22:00",
    [],
    0,
  )
  assert_eq(schedule_reasons(check), "inside-freeze")
  assert_eq(check.change_conflicts.length(), 0)
  assert_eq(check.freeze_ids.length(), 1)
  assert_eq(check.freeze_ids[0], "blackout")
  assert_true(!check.allowed)
}

///|
test "a candidate inside two freezes lists both in plan order" {
  let source = "kind=freeze;id=first;start=2026-10-01T21:00;end=2026-10-01T22:00\n" +
    "kind=freeze;id=second;start=2026-10-01T22:30;end=2026-10-01T23:30\n"
  let check = schedule_check(
    source,
    "2026-10-01T21:30",
    "2026-10-01T23:00",
    [],
    0,
  )
  assert_eq(schedule_reasons(check), "inside-freeze")
  assert_eq(schedule_freeze_text(check), "first,second")
}

///|
test "an unknown dependency is reported once" {
  let source = "id=db;start=2026-10-01T20:00;end=2026-10-01T21:00\n"
  let check = schedule_check(
    source,
    "2026-10-01T21:00",
    "2026-10-01T21:30",
    ["ghost", "phantom"],
    0,
  )
  assert_eq(schedule_reasons(check), "unknown-dependency")
  assert_true(!check.allowed)
}

///|
test "a dependency that ends exactly at the candidate start is accepted" {
  let source = "id=db;start=2026-10-01T20:00;end=2026-10-01T21:00\n"
  let check = schedule_check(
    source,
    "2026-10-01T21:00",
    "2026-10-01T21:30",
    ["db"],
    0,
  )
  assert_true(check.allowed)
  assert_eq(schedule_reasons(check), "")
  assert_eq(check.change_conflicts.length(), 0)
}

///|
test "a dependency that ends one minute after the start is out of order" {
  let source = "id=db;start=2026-10-01T20:00;end=2026-10-01T21:01\n"
  let check = schedule_check(
    source,
    "2026-10-01T21:00",
    "2026-10-01T21:30",
    ["db"],
    0,
  )
  assert_eq(schedule_reasons(check), "blocked-by-change,dependency-order")
  assert_true(!check.allowed)
  // A dependency that sits entirely after the candidate only breaks the order.
  let later = "id=later;start=2026-10-01T22:00;end=2026-10-01T23:00\n"
  let ordered = schedule_check(
    later,
    "2026-10-01T21:00",
    "2026-10-01T21:30",
    ["later"],
    0,
  )
  assert_eq(schedule_reasons(ordered), "dependency-order")
  assert_eq(ordered.change_conflicts.length(), 0)
}

///|
test "allowed is true exactly when the reason list is empty" {
  let source = "id=db;start=2026-10-01T20:00;end=2026-10-01T21:00\n" +
    "kind=freeze;id=blackout;start=2026-10-01T23:00;end=2026-10-02T00:00\n"
  let free = schedule_check(
    source,
    "2026-10-01T18:00",
    "2026-10-01T19:00",
    [],
    0,
  )
  let short = schedule_check(
    source,
    "2026-10-01T18:00",
    "2026-10-01T19:00",
    [],
    90,
  )
  let blocked = schedule_check(
    source,
    "2026-10-01T20:30",
    "2026-10-01T21:30",
    [],
    0,
  )
  let frozen = schedule_check(
    source,
    "2026-10-01T23:30",
    "2026-10-01T23:45",
    [],
    0,
  )
  let unknown = schedule_check(
    source,
    "2026-10-01T18:00",
    "2026-10-01T19:00",
    ["ghost"],
    0,
  )
  for check in [free, short, blocked, frozen, unknown] {
    assert_eq(check.allowed, check.reasons.length() == 0)
  }
}

///|
test "ScheduleCheck::to_line pins an allowed candidate" {
  let source = "id=db;start=2026-10-01T20:00;end=2026-10-01T21:00\n"
  let check = schedule_check(
    source,
    "2026-10-01T21:00",
    "2026-10-01T21:30",
    ["db"],
    0,
  )
  assert_eq(
    check.to_line(),
    "ALLOWED 2026-10-01T21:00 -> 2026-10-01T21:30 (30m)",
  )
}

///|
test "ScheduleCheck::to_line pins a rejected candidate" {
  let source = "id=a;start=2026-10-01T22:00;end=2026-10-01T23:00\n" +
    "kind=freeze;id=blackout;start=2026-10-01T22:00;end=2026-10-02T00:00\n"
  let check = schedule_check(
    source,
    "2026-10-01T22:30",
    "2026-10-01T23:30",
    [],
    0,
  )
  assert_eq(
    check.to_line(),
    "REJECTED 2026-10-01T22:30 -> 2026-10-01T23:30 (1h) (blocked-by-change,inside-freeze)",
  )
}

///|
test "schedule_check_line is the free function alias of to_line" {
  let source = "id=a;start=2026-10-01T22:00;end=2026-10-01T23:00\n"
  let allowed = schedule_check(
    source,
    "2026-10-01T23:00",
    "2026-10-01T23:30",
    [],
    0,
  )
  assert_eq(
    @moon-change-window-auditor.schedule_check_line(allowed),
    allowed.to_line(),
  )
  let rejected = schedule_check(
    source,
    "2026-10-01T22:30",
    "2026-10-01T23:30",
    [],
    0,
  )
  assert_eq(
    @moon-change-window-auditor.schedule_check_line(rejected),
    "REJECTED 2026-10-01T22:30 -> 2026-10-01T23:30 (1h) (blocked-by-change)",
  )
}

///|
test "candidate_slot builds a half open interval" {
  let slot = @moon-change-window-auditor.candidate_slot(
    instant_of("2026-10-01T22:00"),
    instant_of("2026-10-01T23:30"),
  )
  assert_eq(slot.start, instant_of("2026-10-01T22:00"))
  assert_eq(slot.end, instant_of("2026-10-01T23:30"))
  assert_eq(slot.duration(), 90)
  assert_eq(slot.to_line(), "2026-10-01T22:00 -> 2026-10-01T23:30 (1h30m)")
}

///|
test "slack_minutes is zero when a dependency ends at the start" {
  let plan = plan_of(
    "id=db;start=2026-10-01T20:00;end=2026-10-01T21:00\n" +
    "id=api;start=2026-10-01T21:00;end=2026-10-01T21:30;depends=db\n",
  )
  assert_eq(@moon-change-window-auditor.slack_minutes(plan, "api"), Some(0))
}

///|
test "slack_minutes is positive when the dependency finishes early" {
  let plan = plan_of(
    "id=db;start=2026-10-01T20:00;end=2026-10-01T21:00\n" +
    "id=api;start=2026-10-01T21:30;end=2026-10-01T22:00;depends=db\n",
  )
  assert_eq(@moon-change-window-auditor.slack_minutes(plan, "api"), Some(30))
}

///|
test "slack_minutes is negative when the dependency outlives the start" {
  let plan = plan_of(
    "id=db;start=2026-10-01T22:00;end=2026-10-01T23:30\n" +
    "id=api;start=2026-10-01T22:45;end=2026-10-01T23:15;depends=db\n",
  )
  assert_eq(@moon-change-window-auditor.slack_minutes(plan, "api"), Some(-45))
}

///|
test "slack_minutes reports the smallest of several dependencies" {
  let source = "id=db;start=2026-10-01T20:00;end=2026-10-01T21:00\n" +
    "id=cache;start=2026-10-01T20:00;end=2026-10-01T21:20\n" +
    "id=api;start=2026-10-01T21:30;end=2026-10-01T22:00;depends=db,cache\n"
  let plan = plan_of(source)
  assert_eq(@moon-change-window-auditor.slack_minutes(plan, "api"), Some(10))
  // The declaration order of the dependencies does not change the answer.
  let swapped = plan_of(
    "id=db;start=2026-10-01T20:00;end=2026-10-01T21:00\n" +
    "id=cache;start=2026-10-01T20:00;end=2026-10-01T21:20\n" +
    "id=api;start=2026-10-01T21:30;end=2026-10-01T22:00;depends=cache,db\n",
  )
  assert_eq(@moon-change-window-auditor.slack_minutes(swapped, "api"), Some(10))
}

///|
test "slack_minutes is none without an existing dependency" {
  let plan = plan_of(
    "id=alone;start=2026-10-01T20:00;end=2026-10-01T21:00\n" +
    "id=api;start=2026-10-01T21:00;end=2026-10-01T21:30;depends=ghost\n",
  )
  assert_eq(@moon-change-window-auditor.slack_minutes(plan, "alone"), None)
  assert_eq(@moon-change-window-auditor.slack_minutes(plan, "api"), None)
}

///|
test "slack_minutes is none for a record outside the plan" {
  let plan = plan_of("id=db;start=2026-10-01T20:00;end=2026-10-01T21:00\n")
  assert_eq(@moon-change-window-auditor.slack_minutes(plan, "ghost"), None)
}

///|
test "earliest_start returns the original start when it is free" {
  let plan = plan_of("id=db;start=2026-10-01T22:00;end=2026-10-01T23:00\n")
  let candidate = @moon-change-window-auditor.candidate_slot(
    instant_of("2026-10-01T20:00"),
    instant_of("2026-10-01T21:00"),
  )
  assert_eq(
    @moon-change-window-auditor.earliest_start(plan, candidate, 0, 120),
    Some(instant_of("2026-10-01T20:00")),
  )
}

///|
test "earliest_start moves past a blocked change" {
  let plan = plan_of("id=db;start=2026-10-01T22:00;end=2026-10-01T23:00\n")
  let candidate = @moon-change-window-auditor.candidate_slot(
    instant_of("2026-10-01T22:30"),
    instant_of("2026-10-01T23:00"),
  )
  // The probe jumps to the end of the blocking change, which is still inside
  // the thirty minute search range.
  assert_eq(
    @moon-change-window-auditor.earliest_start(plan, candidate, 0, 30),
    Some(instant_of("2026-10-01T23:00")),
  )
  assert_eq(
    @moon-change-window-auditor.earliest_start(plan, candidate, 0, 29),
    None,
  )
}

///|
test "earliest_start jumps over a whole freeze in one step" {
  let plan = plan_of(
    "kind=freeze;id=blackout;start=2026-10-01T21:00;end=2026-10-02T06:00\n",
  )
  let candidate = @moon-change-window-auditor.candidate_slot(
    instant_of("2026-10-01T22:00"),
    instant_of("2026-10-01T23:00"),
  )
  let freeze_end = instant_of("2026-10-02T06:00")
  let freeze_start = instant_of("2026-10-01T22:00")
  // Eight hours of freeze are skipped at once, so the range has to reach its end.
  assert_eq(
    @moon-change-window-auditor.earliest_start(plan, candidate, 0, 480),
    Some(freeze_end),
  )
  assert_eq(
    @moon-change-window-auditor.earliest_start(plan, candidate, 0, 479),
    None,
  )
  assert_eq(freeze_end - freeze_start, 480)
}

///|
test "earliest_start refuses a minimum longer than the candidate" {
  let plan = plan_of("id=db;start=2026-10-01T22:00;end=2026-10-01T23:00\n")
  let candidate = @moon-change-window-auditor.candidate_slot(
    instant_of("2026-10-01T20:00"),
    instant_of("2026-10-01T20:30"),
  )
  assert_eq(
    @moon-change-window-auditor.earliest_start(plan, candidate, 30, 600),
    Some(instant_of("2026-10-01T20:00")),
  )
  assert_eq(
    @moon-change-window-auditor.earliest_start(plan, candidate, 31, 600),
    None,
  )
}

///|
test "earliest_start with a zero search only tests the original position" {
  let plan = plan_of("id=db;start=2026-10-01T22:00;end=2026-10-01T23:00\n")
  let free = @moon-change-window-auditor.candidate_slot(
    instant_of("2026-10-01T20:00"),
    instant_of("2026-10-01T20:30"),
  )
  assert_eq(
    @moon-change-window-auditor.earliest_start(plan, free, 0, 0),
    Some(instant_of("2026-10-01T20:00")),
  )
  let blocked = @moon-change-window-auditor.candidate_slot(
    instant_of("2026-10-01T22:30"),
    instant_of("2026-10-01T23:00"),
  )
  assert_eq(
    @moon-change-window-auditor.earliest_start(plan, blocked, 0, 0),
    None,
  )
}

///|
test "earliest_start returns none when nothing fits in the range" {
  let plan = plan_of("id=db;start=2026-10-01T22:00;end=2026-10-01T23:00\n")
  let candidate = @moon-change-window-auditor.candidate_slot(
    instant_of("2026-10-01T22:00"),
    instant_of("2026-10-01T23:00"),
  )
  // The change blocks its own length and the range stops one minute short of
  // the first free position.
  assert_eq(
    @moon-change-window-auditor.earliest_start(plan, candidate, 0, 59),
    None,
  )
  assert_eq(
    @moon-change-window-auditor.earliest_start(plan, candidate, 0, 60),
    Some(instant_of("2026-10-01T23:00")),
  )
}

///|
test "earliest_start refuses an empty candidate and a negative range" {
  let plan = plan_of("id=db;start=2026-10-01T22:00;end=2026-10-01T23:00\n")
  let start = instant_of("2026-10-01T20:00")
  let empty = @moon-change-window-auditor.candidate_slot(start, start)
  assert_eq(
    @moon-change-window-auditor.earliest_start(plan, empty, 0, 600),
    None,
  )
  let reversed = @moon-change-window-auditor.candidate_slot(
    instant_of("2026-10-01T21:00"),
    instant_of("2026-10-01T20:00"),
  )
  assert_eq(
    @moon-change-window-auditor.earliest_start(plan, reversed, 0, 600),
    None,
  )
  let normal = @moon-change-window-auditor.candidate_slot(
    start,
    instant_of("2026-10-01T20:30"),
  )
  assert_eq(
    @moon-change-window-auditor.earliest_start(plan, normal, 0, -1),
    None,
  )
}

///|
test "earliest_schedule leaves an already ordered chain unshifted" {
  let schedule = schedule_of(
    "id=db;start=2026-10-01T19:00;end=2026-10-01T20:00\n" +
    "id=api;start=2026-10-01T20:00;end=2026-10-01T20:30;depends=db\n",
  )
  assert_eq(schedule.length(), 2)
  assert_eq(schedule[0].id, "db")
  assert_eq(schedule[0].start, instant_of("2026-10-01T19:00"))
  assert_eq(schedule[0].end, instant_of("2026-10-01T20:00"))
  assert_eq(schedule[0].original_start, instant_of("2026-10-01T19:00"))
  assert_eq(schedule[0].shift_minutes, 0)
  assert_eq(schedule[1].id, "api")
  assert_eq(schedule[1].start, instant_of("2026-10-01T20:00"))
  assert_eq(schedule[1].end, instant_of("2026-10-01T20:30"))
  assert_eq(schedule[1].original_start, instant_of("2026-10-01T20:00"))
  assert_eq(schedule[1].shift_minutes, 0)
}

///|
test "earliest_schedule pushes a dependent to the end of its dependency" {
  let schedule = schedule_of(
    "id=db;start=2026-10-01T22:00;end=2026-10-01T23:00\n" +
    "id=api;start=2026-10-01T22:15;end=2026-10-01T22:45;depends=db\n",
  )
  assert_eq(schedule.length(), 2)
  assert_eq(schedule[1].id, "api")
  assert_eq(schedule[1].start, instant_of("2026-10-01T23:00"))
  assert_eq(schedule[1].end, instant_of("2026-10-01T23:30"))
  assert_eq(schedule[1].original_start, instant_of("2026-10-01T22:15"))
  assert_eq(schedule[1].shift_minutes, 45)
  assert_eq(
    schedule[1].to_line(),
    "api 2026-10-01T23:00 -> 2026-10-01T23:30 (+45m)",
  )
}

///|
test "earliest_schedule waits for both branches of a diamond" {
  let schedule = schedule_of(
    "id=db;start=2026-10-01T20:00;end=2026-10-01T21:00\n" +
    "id=api;start=2026-10-01T20:30;end=2026-10-01T21:00;depends=db\n" +
    "id=web;start=2026-10-01T20:30;end=2026-10-01T22:00;depends=db\n" +
    "id=cache;start=2026-10-01T20:45;end=2026-10-01T21:15;depends=api,web\n",
  )
  assert_eq(schedule.length(), 4)
  // The two branches both wait for db and both start at its end.
  assert_eq(schedule[0].id, "db")
  assert_eq(schedule[0].start, instant_of("2026-10-01T20:00"))
  assert_eq(schedule[0].shift_minutes, 0)
  assert_eq(schedule[1].id, "api")
  assert_eq(schedule[1].start, instant_of("2026-10-01T21:00"))
  assert_eq(schedule[1].end, instant_of("2026-10-01T21:30"))
  assert_eq(schedule[2].id, "web")
  assert_eq(schedule[2].start, instant_of("2026-10-01T21:00"))
  assert_eq(schedule[2].end, instant_of("2026-10-01T22:30"))
  // The join waits for the end of the longer branch, not the nearer one.
  assert_eq(schedule[3].id, "cache")
  assert_eq(schedule[3].start, instant_of("2026-10-01T22:30"))
  assert_eq(schedule[3].end, instant_of("2026-10-01T23:00"))
  assert_eq(schedule[3].shift_minutes, 105)
}

///|
test "earliest_schedule returns none for a cyclic plan" {
  let plan = plan_of(
    "id=a;start=2026-10-01T22:00;end=2026-10-01T23:00;depends=b\n" +
    "id=b;start=2026-10-01T20:00;end=2026-10-01T21:00;depends=a\n",
  )
  assert_true(@moon-change-window-auditor.earliest_schedule(plan) is None)
}

///|
test "earliest_schedule follows the execution order" {
  let schedule = schedule_of(
    "id=api;start=2026-10-01T20:00;end=2026-10-01T20:30;depends=db\n" +
    "id=db;start=2026-10-01T19:00;end=2026-10-01T20:00\n",
  )
  // The declaration order is api first, but the dependency has to be planned first.
  assert_eq(schedule.length(), 2)
  assert_eq(schedule[0].id, "db")
  assert_eq(schedule[1].id, "api")
  let plan = plan_of(
    "id=api;start=2026-10-01T20:00;end=2026-10-01T20:30;depends=db\n" +
    "id=db;start=2026-10-01T19:00;end=2026-10-01T20:00\n",
  )
  match @moon-change-window-auditor.execution_order(plan) {
    Some(ids) => {
      assert_eq(ids.length(), 2)
      assert_eq(ids[0], schedule[0].id)
      assert_eq(ids[1], schedule[1].id)
    }
    None => fail("expected an order for this plan")
  }
}

///|
test "earliest_schedule never moves a change earlier and keeps its duration" {
  let source = "id=db;start=2026-10-01T20:00;end=2026-10-01T21:00\n" +
    "id=api;start=2026-10-01T20:30;end=2026-10-01T21:00;depends=db\n" +
    "id=web;start=2026-10-01T20:30;end=2026-10-01T22:00;depends=db\n" +
    "id=cache;start=2026-10-01T20:45;end=2026-10-01T21:15;depends=api,web\n"
  let plan = plan_of(source)
  for entry in schedule_of(source) {
    assert_eq(entry.shift_minutes, entry.start - entry.original_start)
    assert_true(entry.shift_minutes >= 0)
    match plan.find(entry.id) {
      Some(window) => {
        assert_eq(entry.original_start, window.start)
        assert_eq(entry.end - entry.start, window.duration())
      }
      None => fail("missing window " + entry.id)
    }
  }
}

///|
test "next_slots respects the limit" {
  let source = "id=a;start=2026-10-01T22:00;end=2026-10-01T23:00\n" +
    "id=b;start=2026-10-02T00:00;end=2026-10-02T01:00\n"
  let plan = plan_of(source)
  let from = instant_of("2026-10-01T20:00")
  let to = instant_of("2026-10-02T02:00")
  let two = @moon-change-window-auditor.next_slots(plan, from, to, 30, 2)
  assert_eq(two.length(), 2)
  assert_eq(two[0].to_line(), "2026-10-01T20:00 -> 2026-10-01T22:00 (2h)")
  assert_eq(two[1].to_line(), "2026-10-01T23:00 -> 2026-10-02T00:00 (1h)")
  // The horizon is not extended to fill a larger limit.
  let five = @moon-change-window-auditor.next_slots(plan, from, to, 30, 5)
  assert_eq(five.length(), 3)
  assert_eq(five[2].to_line(), "2026-10-02T01:00 -> 2026-10-02T02:00 (1h)")
  assert_eq(
    @moon-change-window-auditor.next_slots(plan, from, to, 30, 1).length(),
    1,
  )
}

///|
test "next_slots returns nothing for a non positive limit" {
  let plan = plan_of("id=a;start=2026-10-01T22:00;end=2026-10-01T23:00\n")
  let from = instant_of("2026-10-01T20:00")
  let to = instant_of("2026-10-02T02:00")
  assert_eq(
    @moon-change-window-auditor.next_slots(plan, from, to, 30, 0).length(),
    0,
  )
  assert_eq(
    @moon-change-window-auditor.next_slots(plan, from, to, 30, -3).length(),
    0,
  )
}

///|
test "next_slots agrees with the first entries of safe_slots" {
  let plan = plan_of(
    "id=a;start=2026-10-01T22:00;end=2026-10-01T23:00\n" +
    "id=b;start=2026-10-02T00:00;end=2026-10-02T01:00\n",
  )
  let from = instant_of("2026-10-01T20:00")
  let to = instant_of("2026-10-02T02:00")
  let all = @moon-change-window-auditor.safe_slots(plan, from, to, 30)
  let limited = @moon-change-window-auditor.next_slots(plan, from, to, 30, 2)
  assert_eq(all.length(), 3)
  assert_eq(limited.length(), 2)
  assert_eq(limited[0].start, all[0].start)
  assert_eq(limited[0].end, all[0].end)
  assert_eq(limited[1].start, all[1].start)
  assert_eq(limited[1].end, all[1].end)
  assert_eq(limited[0].to_line(), all[0].to_line())
  assert_eq(limited[1].to_line(), all[1].to_line())
}

///|
test "render_schedule pins the normal case" {
  let schedule = schedule_of(
    "id=db;start=2026-10-01T19:00;end=2026-10-01T20:00\n" +
    "id=api;start=2026-10-01T20:00;end=2026-10-01T20:30;depends=db\n",
  )
  let text = @moon-change-window-auditor.render_schedule(schedule)
  assert_eq(
    text,
    "Earliest dependency aware schedule (2 changes)\n" +
    "  db 2026-10-01T19:00 -> 2026-10-01T20:00 (+0m)\n" +
    "  api 2026-10-01T20:00 -> 2026-10-01T20:30 (+0m)\n",
  )
  assert_eq(schedule_trailing_newlines(text), 1)
}

///|
test "render_schedule counts a single change in the singular" {
  let schedule = schedule_of(
    "id=db;start=2026-10-01T19:00;end=2026-10-01T20:00\n",
  )
  assert_eq(
    @moon-change-window-auditor.render_schedule(schedule),
    "Earliest dependency aware schedule (1 change)\n" +
    "  db 2026-10-01T19:00 -> 2026-10-01T20:00 (+0m)\n",
  )
}

///|
test "render_schedule pins the empty schedule" {
  let empty : Array[@moon-change-window-auditor.ScheduledChange] = []
  let text = @moon-change-window-auditor.render_schedule(empty)
  assert_eq(
    text, "Earliest dependency aware schedule (0 changes)\n  (no changes)\n",
  )
  assert_eq(schedule_trailing_newlines(text), 1)
  // A plan without windows produces exactly that array.
  let from_empty_plan = @moon-change-window-auditor.render_schedule_result(
    @moon-change-window-auditor.earliest_schedule(plan_of("")),
  )
  assert_eq(from_empty_plan, text)
}

///|
test "render_schedule_result pins the cyclic case" {
  let none : Array[@moon-change-window-auditor.ScheduledChange]? = None
  let text = @moon-change-window-auditor.render_schedule_result(none)
  assert_eq(text, "Earliest dependency aware schedule\n  (cyclic)\n")
  assert_eq(schedule_trailing_newlines(text), 1)
  let cyclic = plan_of(
    "id=a;start=2026-10-01T22:00;end=2026-10-01T23:00;depends=b\n" +
    "id=b;start=2026-10-01T20:00;end=2026-10-01T21:00;depends=a\n",
  )
  assert_eq(
    @moon-change-window-auditor.render_schedule_result(
      @moon-change-window-auditor.earliest_schedule(cyclic),
    ),
    text,
  )
}

///|
test "render_schedule_result wraps a schedule and ends with one newline" {
  let source = "id=db;start=2026-10-01T22:00;end=2026-10-01T23:00\n" +
    "id=api;start=2026-10-01T22:15;end=2026-10-01T22:45;depends=db\n"
  let plan = plan_of(source)
  let result = @moon-change-window-auditor.earliest_schedule(plan)
  let text = @moon-change-window-auditor.render_schedule_result(result)
  assert_eq(
    text,
    @moon-change-window-auditor.render_schedule(schedule_of(source)),
  )
  assert_eq(
    text,
    "Earliest dependency aware schedule (2 changes)\n" +
    "  db 2026-10-01T22:00 -> 2026-10-01T23:00 (+0m)\n" +
    "  api 2026-10-01T23:00 -> 2026-10-01T23:30 (+45m)\n",
  )
  assert_eq(schedule_trailing_newlines(text), 1)
}
