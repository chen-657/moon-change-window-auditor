///|
/// Minimal end to end example: parse a nightly change plan, audit it, then look
/// for room to insert one more change.
///
/// The plan below shows every result the library reports:
///
/// - `api` starts before `database` ends, so the two windows overlap;
/// - `api` therefore also breaks its dependency order on `database`;
/// - `api` depends on a window that is not in the plan;
/// - `cache` starts exactly when `api` ends, which is accepted with a warning.
///
/// Run it with:
///   moon run examples/demo
fn main {
  let source = "# nightly maintenance plan\n" +
    "id=database;service=orders-db;start=2026-10-01T22:00;end=2026-10-01T23:00;risk=high;depends=\n" +
    "id=api;service=orders-api;start=2026-10-01T22:45;end=2026-10-01T23:15;risk=medium;depends=database\n" +
    "id=cache;service=session-cache;start=2026-10-01T23:15;end=2026-10-02T00:15;risk=low;depends=api,queue\n"
  let plan = @audit.parse_plan(source)
  let report = @audit.audit(plan)
  println(@audit.render_report(report))
  match
    (
      @audit.parse_instant("2026-10-01T20:00"),
      @audit.parse_instant("2026-10-02T02:00"),
    ) {
    (Some(from), Some(to)) =>
      println(@audit.render_slots(@audit.safe_slots(plan, from, to, 30)))
    _ => println("invalid horizon")
  }
}
