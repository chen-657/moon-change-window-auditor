///|
/// Tests for overlap detection, dependency order and the audit summary.

///|
test "windows that only touch do not overlap" {
  let report = report_of(
    "id=a;start=2026-10-01T22:00;end=2026-10-01T23:00\n" +
    "id=b;start=2026-10-01T23:00;end=2026-10-02T00:00\n",
  )
  assert_eq(report.overlaps.length(), 0)
  assert_eq(report.blocked_minutes, 120)
  assert_eq(report.error_count(), 0)
  assert_eq(report.status(), "PASS")
}

///|
test "an overlap reports the shared minutes" {
  let report = report_of(
    "id=a;service=orders-db;start=2026-10-01T22:00;end=2026-10-01T23:00;risk=high\n" +
    "id=b;service=orders-api;start=2026-10-01T22:15;end=2026-10-01T23:45;risk=medium\n",
  )
  assert_eq(report.overlaps.length(), 1)
  let overlap = report.overlaps[0]
  assert_eq(overlap.first, "a")
  assert_eq(overlap.second, "b")
  assert_eq(overlap.minutes, 45)
  assert_eq(overlap.impact.label(), "major")
  assert_eq(overlap.to_line(), "a vs b: 45m (major)")
  assert_eq(report.blocked_minutes, 105)
}

///|
test "a window contained in another one overlaps by its own length" {
  let report = report_of(
    "id=outer;start=2026-10-01T22:00;end=2026-10-01T23:00\n" +
    "id=inner;start=2026-10-01T22:15;end=2026-10-01T22:30\n",
  )
  assert_eq(report.overlaps.length(), 1)
  assert_eq(report.overlaps[0].minutes, 15)
  assert_eq(report.blocked_minutes, 60)
}

///|
test "identical windows overlap completely" {
  let report = report_of(
    "id=a;start=2026-10-01T22:00;end=2026-10-01T23:00\n" +
    "id=b;start=2026-10-01T22:00;end=2026-10-01T23:00\n",
  )
  assert_eq(report.overlaps.length(), 1)
  assert_eq(report.overlaps[0].minutes, 60)
  assert_eq(report.overlaps[0].impact.label(), "minor")
  assert_eq(report.blocked_minutes, 60)
}

///|
test "impact follows the risk of both windows" {
  let critical = report_of(
    "id=a;start=2026-10-01T22:00;end=2026-10-01T23:00;risk=high\n" +
    "id=b;start=2026-10-01T22:30;end=2026-10-01T23:30;risk=high\n",
  )
  assert_eq(critical.overlaps[0].impact.label(), "critical")
  let major = report_of(
    "id=a;start=2026-10-01T22:00;end=2026-10-01T23:00;risk=low\n" +
    "id=b;start=2026-10-01T22:30;end=2026-10-01T23:30;risk=high\n",
  )
  assert_eq(major.overlaps[0].impact.label(), "major")
  let minor = report_of(
    "id=a;start=2026-10-01T22:00;end=2026-10-01T23:00;risk=low\n" +
    "id=b;start=2026-10-01T22:30;end=2026-10-01T23:30\n",
  )
  assert_eq(minor.overlaps[0].impact.label(), "minor")
}

///|
test "three overlapping windows produce three pairs" {
  let report = report_of(
    "id=a;start=2026-10-01T22:00;end=2026-10-01T23:00\n" +
    "id=b;start=2026-10-01T22:30;end=2026-10-01T23:30\n" +
    "id=c;start=2026-10-01T22:45;end=2026-10-01T23:15\n",
  )
  assert_eq(report.overlaps.length(), 3)
  assert_eq(report.overlaps[0].to_line(), "a vs b: 30m (minor)")
  assert_eq(report.overlaps[1].to_line(), "a vs c: 15m (minor)")
  assert_eq(report.overlaps[2].to_line(), "b vs c: 30m (minor)")
  assert_eq(report.blocked_minutes, 90)
  assert_eq(report.error_count(), 3)
  assert_eq(report.warning_count(), 0)
  assert_eq(report.status(), "FAIL")
  assert_true(report.has_errors())
}

///|
test "windows listed out of order are still paired by start time" {
  let report = report_of(
    "id=late;start=2026-10-01T23:00;end=2026-10-02T00:00\n" +
    "id=early;start=2026-10-01T22:00;end=2026-10-01T23:30\n",
  )
  assert_eq(report.overlaps.length(), 1)
  assert_eq(report.overlaps[0].to_line(), "early vs late: 30m (minor)")
}

///|
test "a satisfied dependency reports nothing" {
  let report = report_of(
    "id=database;start=2026-10-01T20:00;end=2026-10-01T21:00\n" +
    "id=api;start=2026-10-01T21:30;end=2026-10-01T22:00;depends=database\n",
  )
  assert_eq(report.dependency_issues.length(), 0)
  assert_eq(report.status(), "PASS")
}

///|
test "a dependency that ends exactly at the start warns about zero slack" {
  let report = report_of(
    "id=database;start=2026-10-01T20:00;end=2026-10-01T21:00\n" +
    "id=api;start=2026-10-01T21:00;end=2026-10-01T22:00;depends=database\n",
  )
  assert_eq(report.dependency_issues.length(), 1)
  let issue = report.dependency_issues[0]
  assert_eq(issue.problem.label(), "back-to-back")
  assert_eq(issue.severity.label(), "warning")
  assert_eq(issue.window_id, "api")
  assert_eq(issue.dependency, "database")
  assert_eq(
    issue.to_line(),
    "warning api -> database: back-to-back (no slack between the dependency end and the dependent start)",
  )
  assert_eq(report.error_count(), 0)
  assert_eq(report.warning_count(), 1)
  assert_eq(report.status(), "PASS")
}

///|
test "a dependency that outlives the dependent start is an error" {
  let report = report_of(
    "id=database;start=2026-10-01T22:00;end=2026-10-01T23:30\n" +
    "id=api;start=2026-10-01T22:45;end=2026-10-01T23:15;depends=database\n",
  )
  assert_eq(report.dependency_issues.length(), 1)
  let issue = report.dependency_issues[0]
  assert_eq(issue.problem.label(), "out-of-order")
  assert_eq(issue.severity.label(), "error")
  assert_eq(issue.detail, "the dependency ends 45m after the dependent starts")
  // A dependency that ends after the dependent starts always shares minutes
  // with it, so the same plan also reports one overlap. Both are errors.
  assert_eq(report.overlaps.length(), 1)
  assert_eq(report.overlaps[0].to_line(), "database vs api: 30m (minor)")
  assert_eq(report.error_count(), 2)
  assert_eq(report.status(), "FAIL")
}

///|
test "missing and self dependencies are errors" {
  let report = report_of(
    "id=api;start=2026-10-01T22:00;end=2026-10-01T23:00;depends=api,ghost\n",
  )
  assert_eq(report.dependency_issues.length(), 2)
  assert_eq(report.dependency_issues[0].problem.label(), "self-dependency")
  assert_eq(report.dependency_issues[0].detail, "the window depends on itself")
  assert_eq(report.dependency_issues[1].problem.label(), "missing-dependency")
  assert_eq(
    report.dependency_issues[1].detail,
    "no window with this id exists in the plan",
  )
  assert_eq(report.error_count(), 2)
}

///|
test "a dependency resolves to the first window with a duplicated id" {
  let report = report_of(
    "id=base;start=2026-10-01T18:00;end=2026-10-01T19:00\n" +
    "id=base;start=2026-10-01T20:00;end=2026-10-01T21:00\n" +
    "id=api;start=2026-10-01T21:30;end=2026-10-01T22:00;depends=base\n",
  )
  // The duplicate id is a parse error, but the dependency itself is satisfied
  // by the first record, so no extra dependency issue is added.
  assert_eq(report.dependency_issues.length(), 0)
  assert_eq(report.plan.diagnostics.length(), 1)
  assert_eq(report.plan.diagnostics[0].code, "duplicate-id")
  assert_eq(report.error_count(), 1)
  assert_eq(report.status(), "FAIL")
}

///|
test "records that failed to parse cannot overlap or be depended on" {
  let report = report_of(
    "id=broken;start=nope;end=2026-10-01T23:00\n" +
    "id=api;start=2026-10-01T22:00;end=2026-10-01T23:00;depends=broken\n",
  )
  assert_eq(report.window_count(), 1)
  assert_eq(report.overlaps.length(), 0)
  assert_eq(report.dependency_issues.length(), 1)
  assert_eq(report.dependency_issues[0].problem.label(), "missing-dependency")
  assert_eq(report.status(), "FAIL")
  assert_eq(report.blocked_minutes, 60)
}

///|
test "an empty plan audits to a passing report" {
  let report = report_of("")
  assert_eq(report.window_count(), 0)
  assert_eq(report.overlaps.length(), 0)
  assert_eq(report.dependency_issues.length(), 0)
  assert_eq(report.blocked_minutes, 0)
  assert_eq(report.status(), "PASS")
}

///|
test "blocked time counts overlapping windows once" {
  let report = report_of(
    "id=a;start=2026-10-01T22:00;end=2026-10-01T23:00\n" +
    "id=b;start=2026-10-01T22:30;end=2026-10-01T23:30\n" +
    "id=c;start=2026-10-02T01:00;end=2026-10-02T02:00\n",
  )
  assert_eq(report.blocked_minutes, 150)
}
