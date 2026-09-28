///|
/// Small wrappers shared by the test files. Test files form one package, so the
/// helpers are declared once here.
/// `moon test` runs every file that ends with `_test.mbt`.

///|
/// Parse a plan, failing the test when the module refuses to load.
fn plan_of(source : String) -> @moon-change-window-auditor.Plan {
  @moon-change-window-auditor.parse_plan(source)
}

///|
/// Minutes of an instant that is expected to be valid.
fn instant_of(text : String) -> Int raise {
  match @moon-change-window-auditor.parse_instant(text) {
    Some(value) => value
    None => fail("expected " + text + " to parse")
  }
}

///|
/// Audit a plan given in text form.
fn report_of(source : String) -> @moon-change-window-auditor.AuditReport {
  @moon-change-window-auditor.audit(plan_of(source))
}

///|
/// Render the audit of a plan given in text form.
fn rendered(source : String) -> String {
  @moon-change-window-auditor.render_report(report_of(source))
}

///|
/// Interval between two instants that are expected to be valid.
fn slot_of(
  start : String,
  end : String,
) -> @moon-change-window-auditor.Slot raise {
  { start: instant_of(start), end: instant_of(end), }
}
