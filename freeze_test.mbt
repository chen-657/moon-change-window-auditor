///|
/// Tests for change freezes: how they parse and how they conflict with changes.

///|
test "a freeze parses and stays out of the change list" {
  let plan = plan_of(
    "id=blackout;service=company;kind=freeze;start=2026-12-24T00:00;end=2026-12-27T00:00\n" +
    "id=api;start=2026-10-01T22:00;end=2026-10-01T23:00\n",
  )
  assert_eq(plan.window_count(), 2)
  assert_eq(plan.changes().length(), 1)
  assert_eq(plan.freezes().length(), 1)
  assert_eq(plan.diagnostics.length(), 0)
  let blackout = plan.find("blackout").unwrap()
  assert_true(blackout.is_freeze())
  assert_true(!blackout.is_change())
  assert_eq(blackout.kind.label(), "freeze")
  assert_eq(blackout.duration(), 4320)
  assert_eq(
    blackout.to_freeze_line(),
    "blackout | company | 2026-12-24T00:00 -> 2026-12-27T00:00 | 72h",
  )
  assert_true(plan.find("api").unwrap().is_change())
}

///|
test "the kind field defaults to change and accepts the window synonym" {
  let plan = plan_of(
    "id=a;start=2026-10-01T22:00;end=2026-10-01T23:00\n" +
    "id=b;kind=window;start=2026-10-01T22:00;end=2026-10-01T23:00\n" +
    "id=c;kind=change;start=2026-10-01T22:00;end=2026-10-01T23:00\n",
  )
  assert_eq(plan.changes().length(), 3)
  assert_eq(plan.freezes().length(), 0)
  assert_eq(plan.diagnostics.length(), 0)
}

///|
test "an unknown kind is an error and drops the record" {
  let plan = plan_of(
    "id=a;kind=maintenance;start=2026-10-01T22:00;end=2026-10-01T23:00\n",
  )
  assert_eq(plan.window_count(), 0)
  assert_eq(plan.diagnostics.length(), 1)
  assert_eq(plan.diagnostics[0].code, "invalid-kind")
  assert_eq(plan.diagnostics[0].detail, "maintenance")
}

///|
test "a freeze may not declare dependencies" {
  let plan = plan_of(
    "id=api;start=2026-10-01T22:00;end=2026-10-01T23:00\n" +
    "id=blackout;kind=freeze;start=2026-12-24T00:00;end=2026-12-25T00:00;depends=api\n",
  )
  assert_eq(plan.changes().length(), 1)
  assert_eq(plan.freezes().length(), 0)
  assert_eq(plan.diagnostics.length(), 1)
  assert_eq(plan.diagnostics[0].code, "freeze-with-dependency")
  assert_eq(plan.diagnostics[0].detail, "api")
}

///|
test "a risk level on a freeze is ignored with a warning" {
  let plan = plan_of(
    "id=blackout;kind=freeze;risk=high;start=2026-12-24T00:00;end=2026-12-25T00:00\n",
  )
  assert_eq(plan.freezes().length(), 1)
  assert_eq(plan.diagnostics.length(), 1)
  assert_eq(plan.diagnostics[0].severity.label(), "warning")
  assert_eq(plan.diagnostics[0].code, "ignored-field-on-freeze")
  assert_eq(plan.diagnostics[0].detail, "risk")
  assert_true(!plan.has_errors())
}

///|
test "a change that runs inside a freeze is a conflict" {
  let report = report_of(
    "id=blackout;kind=freeze;service=company;start=2026-12-24T00:00;end=2026-12-27T00:00\n" +
    "id=api;start=2026-12-24T22:00;end=2026-12-25T02:00\n",
  )
  assert_eq(report.change_count(), 1)
  assert_eq(report.freeze_count(), 1)
  assert_eq(report.freeze_conflicts.length(), 1)
  let conflict = report.freeze_conflicts[0]
  assert_eq(conflict.window_id, "api")
  assert_eq(conflict.freeze_id, "blackout")
  assert_eq(conflict.minutes, 240)
  assert_eq(conflict.to_line(), "api runs inside blackout: 4h")
  assert_eq(report.overlaps.length(), 0)
  assert_eq(report.error_count(), 1)
  assert_eq(report.warning_count(), 0)
  assert_eq(report.status(), "FAIL")
}

///|
test "a change that clears the freeze reports nothing" {
  let report = report_of(
    "id=blackout;kind=freeze;start=2026-12-24T00:00;end=2026-12-27T00:00\n" +
    "id=api;start=2026-12-27T00:00;end=2026-12-27T02:00\n",
  )
  assert_eq(report.freeze_conflicts.length(), 0)
  assert_eq(report.status(), "PASS")
}

///|
test "overlapping freezes are not conflicts" {
  let report = report_of(
    "id=first;kind=freeze;start=2026-12-24T00:00;end=2026-12-26T00:00\n" +
    "id=second;kind=freeze;start=2026-12-25T00:00;end=2026-12-27T00:00\n",
  )
  assert_eq(report.overlaps.length(), 0)
  assert_eq(report.freeze_conflicts.length(), 0)
  assert_eq(report.status(), "PASS")
  assert_eq(report.blocked_minutes, 4320)
}

///|
test "every change and freeze pair is reported once" {
  let report = report_of(
    "id=first;kind=freeze;start=2026-12-24T00:00;end=2026-12-25T00:00\n" +
    "id=second;kind=freeze;start=2026-12-24T12:00;end=2026-12-26T00:00\n" +
    "id=api;start=2026-12-24T22:00;end=2026-12-24T23:00\n",
  )
  assert_eq(report.freeze_conflicts.length(), 2)
  assert_eq(report.freeze_conflicts[0].to_line(), "api runs inside first: 1h")
  assert_eq(report.freeze_conflicts[1].to_line(), "api runs inside second: 1h")
  assert_eq(report.error_count(), 2)
}

///|
test "safe slots treat a freeze as blocked time" {
  let plan = plan_of(
    "id=blackout;kind=freeze;start=2026-10-01T22:00;end=2026-10-01T23:00\n",
  )
  let slots = @moon-change-window-auditor.safe_slots(
    plan,
    instant_of("2026-10-01T20:00"),
    instant_of("2026-10-02T00:00"),
    30,
  )
  assert_eq(slots.length(), 2)
  assert_eq(slots[0].to_line(), "2026-10-01T20:00 -> 2026-10-01T22:00 (2h)")
  assert_eq(slots[1].to_line(), "2026-10-01T23:00 -> 2026-10-02T00:00 (1h)")
}

///|
test "freezes_hit_by lists the freezes a candidate interval meets" {
  let plan = plan_of(
    "id=first;kind=freeze;start=2026-10-01T22:00;end=2026-10-01T23:00\n" +
    "id=second;kind=freeze;start=2026-10-02T22:00;end=2026-10-02T23:00\n",
  )
  let candidate : @moon-change-window-auditor.Slot = {
    start: instant_of("2026-10-01T22:30"),
    end: instant_of("2026-10-01T23:30"),
  }
  let hits = @moon-change-window-auditor.freezes_hit_by(plan, candidate)
  assert_eq(hits.length(), 1)
  assert_eq(hits[0].id, "first")
  let clear : @moon-change-window-auditor.Slot = {
    start: instant_of("2026-10-01T23:00"),
    end: instant_of("2026-10-01T23:30"),
  }
  assert_eq(@moon-change-window-auditor.freezes_hit_by(plan, clear).length(), 0)
}

///|
test "freezes appear in their own report section" {
  let output = rendered(
    "id=blackout;service=company;kind=freeze;start=2026-12-24T00:00;end=2026-12-25T00:00\n" +
    "id=api;start=2026-12-24T22:00;end=2026-12-24T23:00\n",
  )
  assert_true(output.contains("windows: 1\n"))
  assert_true(output.contains("freezes: 1\n"))
  assert_true(output.contains("freeze conflicts: 1\n"))
  assert_true(
    output.contains(
      "  blackout | company | 2026-12-24T00:00 -> 2026-12-25T00:00 | 24h\n",
    ),
  )
  assert_true(output.contains("  api runs inside blackout: 1h\n"))
  assert_true(output.contains("status: FAIL"))
}

///|
test "freeze records still need a valid window" {
  let plan = plan_of(
    "id=blackout;kind=freeze;start=2026-12-27T00:00;end=2026-12-24T00:00\n",
  )
  assert_eq(plan.freezes().length(), 0)
  assert_eq(plan.diagnostics[0].code, "end-not-after-start")
}
