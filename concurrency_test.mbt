///|
/// Tests for parallel change load: how many changes run at once, where the plan
/// is busiest and how the load profile samples the timeline.

///|
test "concurrency_at counts the changes covering a minute" {
  let plan = plan_of(
    "id=a;start=2026-10-01T22:00;end=2026-10-01T23:00\n" +
    "id=b;start=2026-10-01T22:30;end=2026-10-01T23:30\n" +
    "id=c;start=2026-10-01T22:45;end=2026-10-01T23:15\n",
  )
  assert_eq(
    @moon-change-window-auditor.concurrency_at(
      plan,
      instant_of("2026-10-01T21:59"),
    ),
    0,
  )
  assert_eq(
    @moon-change-window-auditor.concurrency_at(
      plan,
      instant_of("2026-10-01T22:00"),
    ),
    1,
  )
  assert_eq(
    @moon-change-window-auditor.concurrency_at(
      plan,
      instant_of("2026-10-01T22:30"),
    ),
    2,
  )
  assert_eq(
    @moon-change-window-auditor.concurrency_at(
      plan,
      instant_of("2026-10-01T22:45"),
    ),
    3,
  )
  assert_eq(
    @moon-change-window-auditor.concurrency_at(
      plan,
      instant_of("2026-10-01T23:15"),
    ),
    1,
  )
  assert_eq(
    @moon-change-window-auditor.concurrency_at(
      plan,
      instant_of("2026-10-01T23:30"),
    ),
    0,
  )
}

///|
test "freezes do not count as running changes" {
  let plan = plan_of(
    "id=blackout;kind=freeze;start=2026-10-01T22:00;end=2026-10-01T23:00\n" +
    "id=a;start=2026-10-01T22:30;end=2026-10-01T22:45\n",
  )
  assert_eq(
    @moon-change-window-auditor.concurrency_at(
      plan,
      instant_of("2026-10-01T22:00"),
    ),
    0,
  )
  assert_eq(
    @moon-change-window-auditor.concurrency_at(
      plan,
      instant_of("2026-10-01T22:30"),
    ),
    1,
  )
}

///|
test "peak_concurrency reports the busiest minute, earliest first" {
  let plan = plan_of(
    "id=a;start=2026-10-01T22:00;end=2026-10-01T23:00\n" +
    "id=b;start=2026-10-01T22:30;end=2026-10-01T23:30\n" +
    "id=c;start=2026-10-01T22:45;end=2026-10-01T23:15\n",
  )
  match @moon-change-window-auditor.peak_concurrency(plan) {
    Some(peak) => {
      assert_eq(peak.count, 3)
      assert_eq(peak.minute, instant_of("2026-10-01T22:45"))
      assert_eq(peak.to_line(), "3 changes at 2026-10-01T22:45")
    }
    None => fail("expected a peak")
  }
  match @moon-change-window-auditor.peak_concurrency(plan_of("")) {
    Some(_) => fail("an empty plan has no peak")
    None => ()
  }
}

///|
test "peak_concurrency breaks ties towards the earliest minute" {
  let plan = plan_of(
    "id=a;start=2026-10-01T22:00;end=2026-10-01T23:00\n" +
    "id=b;start=2026-10-01T23:00;end=2026-10-02T00:00\n",
  )
  match @moon-change-window-auditor.peak_concurrency(plan) {
    Some(peak) => {
      assert_eq(peak.count, 1)
      assert_eq(peak.minute, instant_of("2026-10-01T22:00"))
    }
    None => fail("expected a peak")
  }
}

///|
test "busiest_intervals returns the crowded periods" {
  let plan = plan_of(
    "id=a;start=2026-10-01T22:00;end=2026-10-01T23:00\n" +
    "id=b;start=2026-10-01T22:30;end=2026-10-01T23:30\n" +
    "id=c;start=2026-10-02T02:00;end=2026-10-02T03:00\n",
  )
  let crowded = @moon-change-window-auditor.busiest_intervals(plan, 2)
  assert_eq(crowded.length(), 1)
  assert_eq(crowded[0].to_line(), "2026-10-01T22:30 -> 2026-10-01T23:00 (30m)")
  let everything = @moon-change-window-auditor.busiest_intervals(plan, 1)
  assert_eq(everything.length(), 2)
  assert_eq(
    everything[0].to_line(),
    "2026-10-01T22:00 -> 2026-10-01T23:30 (1h30m)",
  )
  assert_eq(
    everything[1].to_line(),
    "2026-10-02T02:00 -> 2026-10-02T03:00 (1h)",
  )
  assert_eq(@moon-change-window-auditor.busiest_intervals(plan, 4).length(), 0)
  assert_eq(
    @moon-change-window-auditor.busiest_intervals(plan_of(""), 1).length(),
    0,
  )
}

///|
test "max_concurrency_in looks only inside the interval" {
  let plan = plan_of(
    "id=a;start=2026-10-01T22:00;end=2026-10-01T23:00\n" +
    "id=b;start=2026-10-01T22:30;end=2026-10-01T23:30\n",
  )
  let morning = slot_of("2026-10-01T10:00", "2026-10-01T11:00")
  assert_eq(@moon-change-window-auditor.max_concurrency_in(plan, morning), 0)
  let overlap = slot_of("2026-10-01T22:45", "2026-10-01T22:50")
  assert_eq(@moon-change-window-auditor.max_concurrency_in(plan, overlap), 2)
  let first_only = slot_of("2026-10-01T22:00", "2026-10-01T22:30")
  assert_eq(@moon-change-window-auditor.max_concurrency_in(plan, first_only), 1)
}

///|
test "service_concurrency_at filters by service" {
  let plan = plan_of(
    "id=a;service=orders;start=2026-10-01T22:00;end=2026-10-01T23:00\n" +
    "id=b;service=orders;start=2026-10-01T22:30;end=2026-10-01T23:30\n" +
    "id=c;service=payments;start=2026-10-01T22:30;end=2026-10-01T23:00\n",
  )
  let minute = instant_of("2026-10-01T22:45")
  assert_eq(
    @moon-change-window-auditor.service_concurrency_at(plan, "orders", minute),
    2,
  )
  assert_eq(
    @moon-change-window-auditor.service_concurrency_at(plan, "payments", minute),
    1,
  )
  assert_eq(
    @moon-change-window-auditor.service_concurrency_at(plan, "missing", minute),
    0,
  )
}

///|
test "load_profile samples the horizon at the requested step" {
  let plan = plan_of("id=a;start=2026-10-01T22:00;end=2026-10-01T23:00\n")
  let points = @moon-change-window-auditor.load_profile(
    plan,
    instant_of("2026-10-01T21:00"),
    instant_of("2026-10-01T23:00"),
    30,
  )
  assert_eq(points.length(), 4)
  assert_eq(points[0].to_line(), "2026-10-01T21:00 load 0")
  assert_eq(points[1].to_line(), "2026-10-01T21:30 load 0")
  assert_eq(points[2].to_line(), "2026-10-01T22:00 load 1")
  assert_eq(points[3].to_line(), "2026-10-01T22:30 load 1")
}

///|
test "load_profile refuses a step of zero and an empty horizon" {
  let plan = plan_of("id=a;start=2026-10-01T22:00;end=2026-10-01T23:00\n")
  assert_eq(
    @moon-change-window-auditor.load_profile(
      plan,
      instant_of("2026-10-01T21:00"),
      instant_of("2026-10-01T23:00"),
      0,
    ).length(),
    0,
  )
  assert_eq(
    @moon-change-window-auditor.load_profile(
      plan,
      instant_of("2026-10-01T23:00"),
      instant_of("2026-10-01T21:00"),
      5,
    ).length(),
    0,
  )
}

///|
test "change_minutes counts work while blocked_minutes counts calendar time" {
  let plan = plan_of(
    "id=a;start=2026-10-01T22:00;end=2026-10-01T23:00\n" +
    "id=b;start=2026-10-01T22:30;end=2026-10-01T23:30\n",
  )
  assert_eq(@moon-change-window-auditor.change_minutes(plan), 120)
  assert_eq(@moon-change-window-auditor.blocked_minutes(plan), 90)
  assert_eq(@moon-change-window-auditor.freeze_minutes(plan), 0)
}

///|
test "freeze_minutes adds up freezes only" {
  let plan = plan_of(
    "id=blackout;kind=freeze;start=2026-12-24T00:00;end=2026-12-25T00:00\n" +
    "id=other;kind=freeze;start=2026-12-26T00:00;end=2026-12-26T12:00\n" +
    "id=a;start=2026-10-01T22:00;end=2026-10-01T23:00\n",
  )
  assert_eq(@moon-change-window-auditor.freeze_minutes(plan), 2160)
  assert_eq(@moon-change-window-auditor.change_minutes(plan), 60)
}
