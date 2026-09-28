///|
/// Tests that pin the rendered report and slot listing.

///|
test "a clean plan renders a passing report with empty sections" {
  let plan = plan_of(
    "id=a;service=svc;start=2026-10-01T22:00;end=2026-10-01T23:30;risk=high\n",
  )
  let expected = "Moon Change Window Audit\n" +
    "windows: 1\n" +
    "freezes: 0\n" +
    "errors: 0\n" +
    "warnings: 0\n" +
    "overlaps: 0\n" +
    "freeze conflicts: 0\n" +
    "dependency issues: 0\n" +
    "blocked: 1h30m\n" +
    "status: PASS\n" +
    "\n" +
    "WINDOWS\n" +
    "  a | svc | 2026-10-01T22:00 -> 2026-10-01T23:30 | 1h30m | high | -\n" +
    "\n" +
    "FREEZES\n" +
    "  (none)\n" +
    "\n" +
    "OVERLAPS\n" +
    "  (none)\n" +
    "\n" +
    "FREEZE CONFLICTS\n" +
    "  (none)\n" +
    "\n" +
    "DEPENDENCY ISSUES\n" +
    "  (none)\n" +
    "\n" +
    "DIAGNOSTICS\n" +
    "  (none)\n"
  assert_eq(
    @moon-change-window-auditor.render_report(
      @moon-change-window-auditor.audit(plan),
    ),
    expected,
  )
}

///|
test "a failing plan renders every section" {
  let source = "id=database;service=orders-db;start=2026-10-01T22:00;end=2026-10-01T23:00;risk=high;depends=\n" +
    "id=api;service=orders-api;start=2026-10-01T22:45;end=2026-10-01T23:15;risk=medium;depends=database\n" +
    "id=cache;start=2026-10-01T23:15;end=2026-10-02T00:15;risk=low;depends=api,missing\n"
  let expected = "Moon Change Window Audit\n" +
    "windows: 3\n" +
    "freezes: 0\n" +
    "errors: 3\n" +
    "warnings: 1\n" +
    "overlaps: 1\n" +
    "freeze conflicts: 0\n" +
    "dependency issues: 3\n" +
    "blocked: 2h15m\n" +
    "status: FAIL\n" +
    "\n" +
    "WINDOWS\n" +
    "  database | orders-db | 2026-10-01T22:00 -> 2026-10-01T23:00 | 1h | high | -\n" +
    "  api | orders-api | 2026-10-01T22:45 -> 2026-10-01T23:15 | 30m | medium | database\n" +
    "  cache | - | 2026-10-01T23:15 -> 2026-10-02T00:15 | 1h | low | api, missing\n" +
    "\n" +
    "FREEZES\n" +
    "  (none)\n" +
    "\n" +
    "OVERLAPS\n" +
    "  database vs api: 15m (major)\n" +
    "\n" +
    "FREEZE CONFLICTS\n" +
    "  (none)\n" +
    "\n" +
    "DEPENDENCY ISSUES\n" +
    "  error api -> database: out-of-order (the dependency ends 15m after the dependent starts)\n" +
    "  warning cache -> api: back-to-back (no slack between the dependency end and the dependent start)\n" +
    "  error cache -> missing: missing-dependency (no window with this id exists in the plan)\n" +
    "\n" +
    "DIAGNOSTICS\n" +
    "  (none)\n"
  assert_eq(rendered(source), expected)
}

///|
test "parse diagnostics appear in the report with their line numbers" {
  let output = rendered(
    "id=a;start=2026-10-01T22:00;end=2026-10-01T23:00;owner=payments\n" +
    "id=b;start=nope;end=2026-10-01T23:00\n",
  )
  assert_true(output.contains("status: FAIL"))
  assert_true(output.contains("errors: 1"))
  assert_true(output.contains("warnings: 1"))
  assert_true(output.contains("  warning line 1: unknown-field (owner)\n"))
  assert_true(
    output.contains("  error line 2: invalid-instant (start=\"nope\")\n"),
  )
}

///|
test "render_diagnostics returns an empty string for a clean plan" {
  assert_eq(
    @moon-change-window-auditor.render_diagnostics(
      plan_of("id=a;start=2026-10-01T22:00;end=2026-10-01T23:00").diagnostics,
    ),
    "",
  )
}

///|
test "render_slots lists each slot with its length" {
  let plan = plan_of("id=a;start=2026-10-01T22:00;end=2026-10-01T23:00\n")
  let slots = @moon-change-window-auditor.safe_slots(
    plan,
    instant_of("2026-10-01T20:00"),
    instant_of("2026-10-02T00:00"),
    30,
  )
  assert_eq(
    @moon-change-window-auditor.render_slots(slots),
    "Safe change slots (2)\n" +
    "  2026-10-01T20:00 -> 2026-10-01T22:00 (2h)\n" +
    "  2026-10-01T23:00 -> 2026-10-02T00:00 (1h)\n",
  )
}

///|
test "render_slots marks an empty result" {
  let plan = plan_of("id=a;start=2026-10-01T20:00;end=2026-10-02T00:00\n")
  let slots = @moon-change-window-auditor.safe_slots(
    plan,
    instant_of("2026-10-01T20:00"),
    instant_of("2026-10-02T00:00"),
    30,
  )
  assert_eq(
    @moon-change-window-auditor.render_slots(slots),
    "Safe change slots (0)\n  (none)\n",
  )
}
