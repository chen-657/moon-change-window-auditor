///|
/// Policy gate example: decide whether a nightly plan may go ahead.
///
/// The plan below is internally consistent enough to be worth reading, but it
/// still breaks a strict policy in three ways:
///
/// - `api` starts before `database` ends, so the dependency has negative slack;
/// - two high risk changes run at the same time;
/// - `cache` runs inside the company freeze.
///
/// The example prints the policy report, the plan summary and the earliest
/// dependency aware schedule of the same plan.
///
/// Run it with:
///   moon run examples/policy-gate
fn main {
  let source = "# nightly maintenance plan\n" +
    "id=database;service=orders-db;start=2026-10-01T22:00;end=2026-10-01T23:00;risk=high\n" +
    "id=api;service=orders-api;start=2026-10-01T22:30;end=2026-10-02T00:30;risk=high;depends=database\n" +
    "id=blackout;service=company;kind=freeze;start=2026-10-02T01:00;end=2026-10-02T03:00\n" +
    "id=cache;service=session-cache;start=2026-10-02T02:00;end=2026-10-02T03:30;risk=low;depends=api\n"
  let plan = @audit.parse_plan(source)
  let report = @audit.audit_with_policy(plan, @audit.Policy::strict())
  println(@audit.render_policy_report(report))
  println(@audit.render_summary(@audit.summarize(plan)))
  println(@audit.render_schedule_result(@audit.earliest_schedule(plan)))
  println(
    @audit.render_timeline(
      plan,
      @audit.parse_instant("2026-10-01T21:00").unwrap(),
      @audit.parse_instant("2026-10-02T04:00").unwrap(),
      28,
    ),
  )
}
