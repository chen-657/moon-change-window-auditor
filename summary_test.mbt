///|
/// Tests for `summarize`, `render_summary`, `find_service` and the service rows
/// a summary reports.

///|
/// The value of an `Int?` a test expects to be present.
fn summary_some(value : Int?, label : String) -> Int raise {
  match value {
    Some(found) => found
    None => fail("expected " + label + " to be present")
  }
}

///|
test "an empty plan summarises to zero and no services" {
  let summary = @moon-change-window-auditor.summarize(plan_of(""))
  assert_eq(summary.changes, 0)
  assert_eq(summary.freezes, 0)
  assert_eq(summary.blocked_minutes, 0)
  assert_eq(summary.change_minutes, 0)
  assert_eq(summary.low_risk, 0)
  assert_eq(summary.medium_risk, 0)
  assert_eq(summary.high_risk, 0)
  assert_true(summary.earliest is None)
  assert_true(summary.latest is None)
  assert_eq(summary.span_minutes, 0)
  assert_true(summary.peak is None)
  assert_eq(summary.services.length(), 0)
}

///|
test "changes and freezes are counted separately" {
  let plan = plan_of(
    "id=c1;service=db;start=2026-10-01T22:00;end=2026-10-01T23:00;risk=high\n" +
    "id=c2;service=db;start=2026-10-01T23:00;end=2026-10-02T00:00;risk=low\n" +
    "id=f1;kind=freeze;start=2026-12-24T00:00;end=2026-12-25T00:00\n" +
    "id=f2;kind=freeze;start=2026-12-31T00:00;end=2027-01-01T00:00\n",
  )
  assert_eq(plan.window_count(), 4)
  let summary = @moon-change-window-auditor.summarize(plan)
  assert_eq(summary.changes, 2)
  assert_eq(summary.freezes, 2)
  assert_eq(summary.changes + summary.freezes, plan.window_count())
}

///|
test "risk counts split the changes and add up" {
  let summary = @moon-change-window-auditor.summarize(
    plan_of(
      "id=a;start=2026-10-01T22:00;end=2026-10-01T23:00;risk=high\n" +
      "id=b;start=2026-10-02T22:00;end=2026-10-02T23:00;risk=high\n" +
      "id=c;start=2026-10-03T22:00;end=2026-10-03T23:00;risk=low\n" +
      "id=d;start=2026-10-04T22:00;end=2026-10-04T23:00\n" +
      "id=e;start=2026-10-05T22:00;end=2026-10-05T23:00;risk=medium\n" +
      "id=f;kind=freeze;start=2026-12-24T00:00;end=2026-12-25T00:00\n",
    ),
  )
  assert_eq(summary.changes, 5)
  assert_eq(summary.freezes, 1)
  assert_eq(summary.low_risk, 1)
  // The record without a risk field carries the default, medium.
  assert_eq(summary.medium_risk, 2)
  assert_eq(summary.high_risk, 2)
  assert_eq(summary.freezes, 1)
  assert_eq(
    summary.low_risk + summary.medium_risk + summary.high_risk,
    summary.changes,
  )
}

///|
test "blocked minutes count an overlap once but workload counts it twice" {
  let source = "id=a;service=db;start=2026-10-01T22:00;end=2026-10-01T23:00\n" +
    "id=b;service=db;start=2026-10-01T22:30;end=2026-10-01T23:30\n"
  let summary = @moon-change-window-auditor.summarize(plan_of(source))
  // 22:00-23:30 is the union, 60 + 60 is the workload.
  assert_eq(summary.blocked_minutes, 90)
  assert_eq(summary.change_minutes, 120)
  assert_eq(summary.blocked_minutes, report_of(source).blocked_minutes)
  assert_true(summary.blocked_minutes < summary.change_minutes)
}

///|
test "change minutes exclude freeze minutes" {
  let plan = plan_of(
    "id=a;start=2026-10-01T22:00;end=2026-10-01T23:00\n" +
    "id=b;start=2026-10-01T23:00;end=2026-10-02T00:00\n" +
    "id=blackout;kind=freeze;start=2026-12-24T00:00;end=2026-12-25T00:00\n",
  )
  let mut workload = 0
  for change in plan.changes() {
    workload = workload + change.duration()
  }
  assert_eq(workload, 120)
  assert_eq(@moon-change-window-auditor.freeze_minutes(plan), 1440)
  let summary = @moon-change-window-auditor.summarize(plan)
  assert_eq(summary.change_minutes, workload)
  assert_eq(summary.change_minutes, 120)
}

///|
test "blocked minutes include the freeze calendar time" {
  // `blocked_intervals` covers every window, freezes included: the two touching
  // changes merge into 2h and the one day freeze adds its 24h.
  let source = "id=a;start=2026-10-01T22:00;end=2026-10-01T23:00\n" +
    "id=b;start=2026-10-01T23:00;end=2026-10-02T00:00\n" +
    "id=blackout;kind=freeze;start=2026-12-24T00:00;end=2026-12-25T00:00\n"
  let summary = @moon-change-window-auditor.summarize(plan_of(source))
  assert_eq(summary.blocked_minutes, 1560)
  assert_eq(summary.blocked_minutes, report_of(source).blocked_minutes)
}

///|
test "earliest and latest cover changes and freezes" {
  let summary = @moon-change-window-auditor.summarize(
    plan_of(
      "id=a;start=2026-10-01T22:00;end=2026-10-01T23:00\n" +
      "id=blackout;kind=freeze;start=2026-12-24T00:00;end=2026-12-27T00:00\n",
    ),
  )
  assert_eq(
    summary_some(summary.earliest, "earliest"),
    instant_of("2026-10-01T22:00"),
  )
  assert_eq(
    summary_some(summary.latest, "latest"),
    instant_of("2026-12-27T00:00"),
  )
  assert_eq(
    summary.span_minutes,
    instant_of("2026-12-27T00:00") - instant_of("2026-10-01T22:00"),
  )
}

///|
test "a freeze can set the earliest instant" {
  let summary = @moon-change-window-auditor.summarize(
    plan_of(
      "id=prep;kind=freeze;start=2026-09-01T00:00;end=2026-09-02T00:00\n" +
      "id=a;start=2026-10-01T22:00;end=2026-10-01T23:00\n",
    ),
  )
  assert_eq(
    summary_some(summary.earliest, "earliest"),
    instant_of("2026-09-01T00:00"),
  )
  assert_eq(
    summary_some(summary.latest, "latest"),
    instant_of("2026-10-01T23:00"),
  )
}

///|
test "span minutes measure the first start to the last end" {
  let summary = @moon-change-window-auditor.summarize(
    plan_of(
      "id=b;start=2026-10-01T22:30;end=2026-10-01T23:00\n" +
      "id=a;start=2026-10-01T22:00;end=2026-10-01T23:30\n",
    ),
  )
  assert_eq(
    summary_some(summary.earliest, "earliest"),
    instant_of("2026-10-01T22:00"),
  )
  assert_eq(
    summary_some(summary.latest, "latest"),
    instant_of("2026-10-01T23:30"),
  )
  assert_eq(summary.span_minutes, 90)
}

///|
test "peak concurrency ignores freezes covering the same minutes" {
  let plan = plan_of(
    "id=blackout;kind=freeze;start=2026-10-01T21:00;end=2026-10-02T00:00\n" +
    "id=a;start=2026-10-01T22:00;end=2026-10-01T23:00\n" +
    "id=b;start=2026-10-01T22:30;end=2026-10-01T23:30\n",
  )
  let summary = @moon-change-window-auditor.summarize(plan)
  let peak = summary.peak.unwrap()
  // The freeze covers 22:30 as well, but only two changes run there.
  assert_eq(peak.count, 2)
  assert_eq(peak.minute, instant_of("2026-10-01T22:30"))
  assert_eq(peak.to_line(), "2 changes at 2026-10-01T22:30")
  assert_eq(
    @moon-change-window-auditor.concurrency_at(
      plan,
      instant_of("2026-10-01T22:30"),
    ),
    2,
  )
}

///|
test "a plan with only a freeze has no peak" {
  let summary = @moon-change-window-auditor.summarize(
    plan_of(
      "id=blackout;kind=freeze;start=2026-12-24T00:00;end=2026-12-25T00:00\n",
    ),
  )
  assert_eq(summary.changes, 0)
  assert_eq(summary.freezes, 1)
  assert_true(summary.peak is None)
  assert_eq(summary.change_minutes, 0)
  assert_eq(summary.services.length(), 0)
  // A freeze still occupies calendar time.
  assert_eq(summary.span_minutes, 1440)
  assert_eq(summary.blocked_minutes, 1440)
  assert_eq(
    summary_some(summary.earliest, "earliest"),
    instant_of("2026-12-24T00:00"),
  )
  assert_eq(
    summary_some(summary.latest, "latest"),
    instant_of("2026-12-25T00:00"),
  )
}

///|
test "services are one row per change service in code point order" {
  let summary = @moon-change-window-auditor.summarize(
    plan_of(
      "id=one;service=zeta;start=2026-10-01T22:00;end=2026-10-01T23:00\n" +
      "id=two;service=Alpha;start=2026-10-02T22:00;end=2026-10-02T23:00\n" +
      "id=three;service=alpha;start=2026-10-03T22:00;end=2026-10-03T23:00\n" +
      "id=four;service=zeta;start=2026-10-04T22:00;end=2026-10-04T23:00\n",
    ),
  )
  assert_eq(summary.services.length(), 3)
  // Upper case letters have lower code points than lower case ones.
  assert_eq(summary.services[0].service, "Alpha")
  assert_eq(summary.services[1].service, "alpha")
  assert_eq(summary.services[2].service, "zeta")
  assert_eq(
    @moon-change-window-auditor.find_service(summary, "zeta").unwrap().changes,
    2,
  )
}

///|
test "the empty service sorts first and renders as (none)" {
  let summary = @moon-change-window-auditor.summarize(
    plan_of(
      "id=one;service=zeta;start=2026-10-01T22:00;end=2026-10-01T23:00\n" +
      "id=two;start=2026-10-02T22:00;end=2026-10-02T23:00\n",
    ),
  )
  assert_eq(summary.services.length(), 2)
  assert_eq(summary.services[0].service, "")
  assert_eq(summary.services[1].service, "zeta")
  assert_true(summary.services[0].to_line().contains("(none):"))
}

///|
test "per service blocked minutes union only that service" {
  let summary = @moon-change-window-auditor.summarize(
    plan_of(
      "id=a;service=db;start=2026-10-01T22:00;end=2026-10-01T23:00\n" +
      "id=b;service=db;start=2026-10-01T22:30;end=2026-10-01T23:30\n" +
      "id=c;service=api;start=2026-10-01T22:00;end=2026-10-02T00:00\n",
    ),
  )
  let db = @moon-change-window-auditor.find_service(summary, "db").unwrap()
  let api = @moon-change-window-auditor.find_service(summary, "api").unwrap()
  assert_eq(db.changes, 2)
  assert_eq(db.blocked_minutes, 90)
  assert_eq(api.changes, 1)
  assert_eq(api.blocked_minutes, 120)
  // The whole plan is the union of both services.
  assert_eq(summary.blocked_minutes, 120)
}

///|
test "per service peak concurrency counts only that service" {
  let summary = @moon-change-window-auditor.summarize(
    plan_of(
      "id=a;service=db;start=2026-10-01T22:00;end=2026-10-01T23:00\n" +
      "id=b;service=db;start=2026-10-01T22:30;end=2026-10-01T23:30\n" +
      "id=c;service=db;start=2026-10-02T22:00;end=2026-10-02T23:00\n" +
      "id=d;service=api;start=2026-10-01T22:00;end=2026-10-01T23:00\n",
    ),
  )
  let db = @moon-change-window-auditor.find_service(summary, "db").unwrap()
  let api = @moon-change-window-auditor.find_service(summary, "api").unwrap()
  assert_eq(db.changes, 3)
  assert_eq(db.peak_concurrency, 2)
  // api runs beside db, which is a plan level peak, not an api one.
  assert_eq(api.peak_concurrency, 1)
}

///|
test "per service high risk changes count only high risk changes" {
  let summary = @moon-change-window-auditor.summarize(
    plan_of(
      "id=a;service=db;start=2026-10-01T22:00;end=2026-10-01T23:00;risk=high\n" +
      "id=b;service=db;start=2026-10-02T22:00;end=2026-10-02T23:00;risk=medium\n" +
      "id=c;service=db;start=2026-10-03T22:00;end=2026-10-03T23:00;risk=high\n" +
      "id=d;service=api;start=2026-10-01T22:00;end=2026-10-01T23:00;risk=high\n",
    ),
  )
  let db = @moon-change-window-auditor.find_service(summary, "db").unwrap()
  let api = @moon-change-window-auditor.find_service(summary, "api").unwrap()
  assert_eq(db.changes, 3)
  assert_eq(db.high_risk_changes, 2)
  assert_eq(api.high_risk_changes, 1)
  assert_eq(summary.high_risk, 3)
  assert_eq(summary.high_risk, db.high_risk_changes + api.high_risk_changes)
}

///|
test "ServiceSummary::to_line renders the fixed text" {
  let summary = @moon-change-window-auditor.summarize(
    plan_of(
      "id=a;service=db;start=2026-10-01T22:00;end=2026-10-01T23:30;risk=high\n" +
      "id=b;service=db;start=2026-10-01T22:30;end=2026-10-01T23:00;risk=high\n" +
      "id=c;start=2026-10-01T22:00;end=2026-10-01T22:45\n",
    ),
  )
  assert_eq(
    @moon-change-window-auditor.find_service(summary, "db").unwrap().to_line(),
    "db: 2 changes, 1h30m blocked, peak 2, 2 high risk changes",
  )
  assert_eq(
    @moon-change-window-auditor.find_service(summary, "").unwrap().to_line(),
    "(none): 1 change, 45m blocked, peak 1, 0 high risk changes",
  )
}

///|
test "find_service finds a service and reports a miss" {
  let summary = @moon-change-window-auditor.summarize(
    plan_of(
      "id=a;service=db;start=2026-10-01T22:00;end=2026-10-01T23:00\n" +
      "id=b;start=2026-10-01T22:00;end=2026-10-01T23:00\n" +
      "id=blackout;service=company;kind=freeze;start=2026-12-24T00:00;end=2026-12-25T00:00\n",
    ),
  )
  let found = @moon-change-window-auditor.find_service(summary, "db")
  assert_true(found is Some(_))
  assert_eq(found.unwrap().changes, 1)
  assert_true(@moon-change-window-auditor.find_service(summary, "") is Some(_))
  assert_true(
    @moon-change-window-auditor.find_service(summary, "search") is None,
  )
  // The freeze names a service, but only changes create a service row.
  assert_true(
    @moon-change-window-auditor.find_service(summary, "company") is None,
  )
}

///|
test "render_summary pins the whole text of a small plan" {
  let summary = @moon-change-window-auditor.summarize(
    plan_of(
      "id=db;service=db;start=2026-10-01T22:00;end=2026-10-01T23:00;risk=high\n" +
      "id=api;service=api;start=2026-10-01T22:30;end=2026-10-01T23:30;risk=low\n",
    ),
  )
  let expected = "Plan summary\n" +
    "changes: 2\n" +
    "freezes: 0\n" +
    "risks: low 1, medium 0, high 1\n" +
    "blocked: 1h30m\n" +
    "workload: 2h\n" +
    "span: 2026-10-01T22:00 -> 2026-10-01T23:30\n" +
    "peak: 2 changes at 2026-10-01T22:30\n" +
    "services: 2\n" +
    "\n" +
    "SERVICES\n" +
    "  api: 1 change, 1h blocked, peak 1, 0 high risk changes\n" +
    "  db: 1 change, 1h blocked, peak 1, 1 high risk change\n"
  assert_eq(@moon-change-window-auditor.render_summary(summary), expected)
}

///|
test "render_summary of an empty plan pins the placeholders" {
  let expected = "Plan summary\n" +
    "changes: 0\n" +
    "freezes: 0\n" +
    "risks: low 0, medium 0, high 0\n" +
    "blocked: 0m\n" +
    "workload: 0m\n" +
    "span: (empty)\n" +
    "peak: (none)\n" +
    "services: 0\n" +
    "\n" +
    "SERVICES\n" +
    "  (none)\n"
  assert_eq(
    @moon-change-window-auditor.render_summary(
      @moon-change-window-auditor.summarize(plan_of("")),
    ),
    expected,
  )
}

///|
test "render_summary ends with exactly one newline" {
  let text = @moon-change-window-auditor.render_summary(
    @moon-change-window-auditor.summarize(
      plan_of("id=a;service=db;start=2026-10-01T22:00;end=2026-10-01T23:00\n"),
    ),
  )
  assert_true(text.has_suffix("\n"))
  assert_true(!text.has_suffix("\n\n"))
  assert_true(
    text.has_suffix("  db: 1 change, 1h blocked, peak 1, 0 high risk changes\n"),
  )
  let empty_text = @moon-change-window-auditor.render_summary(
    @moon-change-window-auditor.summarize(plan_of("")),
  )
  assert_true(empty_text.has_suffix("\n"))
  assert_true(!empty_text.has_suffix("\n\n"))
  assert_true(empty_text.has_suffix("  (none)\n"))
}

///|
test "render_summary lists no service for a freeze only plan" {
  let text = @moon-change-window-auditor.render_summary(
    @moon-change-window-auditor.summarize(
      plan_of(
        "id=blackout;service=company;kind=freeze;start=2026-12-24T00:00;end=2026-12-25T00:00\n",
      ),
    ),
  )
  assert_true(text.contains("services: 0\n"))
  assert_true(text.has_suffix("\nSERVICES\n  (none)\n"))
  assert_true(!text.contains("company"))
}

///|
test "summary agrees with the audit and the concurrency helpers" {
  let plan = plan_of(
    "id=a;start=2026-10-01T22:00;end=2026-10-01T23:00\n" +
    "id=blackout;kind=freeze;start=2026-10-01T22:30;end=2026-10-01T23:30\n",
  )
  let report = @moon-change-window-auditor.audit(plan)
  let summary = @moon-change-window-auditor.summarize(plan)
  assert_eq(summary.blocked_minutes, report.blocked_minutes)
  assert_eq(summary.blocked_minutes, 90)
  assert_eq(summary.changes, report.change_count())
  assert_eq(summary.freezes, report.freeze_count())
  assert_eq(
    summary.peak.unwrap().count,
    @moon-change-window-auditor.concurrency_at(
      plan,
      instant_of("2026-10-01T22:00"),
    ),
  )
  assert_eq(summary.peak.unwrap().count, 1)
}

///|
test "summarize does not depend on the input order" {
  let forwards = "id=a;service=zeta;start=2026-10-01T22:00;end=2026-10-01T23:00\n" +
    "id=b;service=api;start=2026-10-01T22:30;end=2026-10-01T23:30\n"
  let backwards = "id=b;service=api;start=2026-10-01T22:30;end=2026-10-01T23:30\n" +
    "id=a;service=zeta;start=2026-10-01T22:00;end=2026-10-01T23:00\n"
  let first = @moon-change-window-auditor.render_summary(
    @moon-change-window-auditor.summarize(plan_of(forwards)),
  )
  let second = @moon-change-window-auditor.render_summary(
    @moon-change-window-auditor.summarize(plan_of(backwards)),
  )
  assert_eq(first, second)
}
