///|
/// Tests for the CSV renderer.

///|
/// True when the text ends with exactly one newline.
fn csv_ends_with_one_newline(text : String) -> Bool {
  text.length() > 0 &&
  text[text.length() - 1] == '\n' &&
  (text.length() < 2 || text[text.length() - 2] != '\n')
}

///|
test "csv_escape leaves a plain field alone" {
  assert_eq(@moon-change-window-auditor.csv_escape("plain"), "plain")
  assert_eq(@moon-change-window-auditor.csv_escape(""), "")
  assert_eq(
    @moon-change-window-auditor.csv_escape("2026-10-01T22:00"),
    "2026-10-01T22:00",
  )
}

///|
test "csv_escape quotes a field with a comma" {
  assert_eq(@moon-change-window-auditor.csv_escape("a,b"), "\"a,b\"")
}

///|
test "csv_escape doubles inner quotes" {
  assert_eq(
    @moon-change-window-auditor.csv_escape("say \"hi\""),
    "\"say \"\"hi\"\"\"",
  )
  assert_eq(@moon-change-window-auditor.csv_escape("\""), "\"\"\"\"")
}

///|
test "csv_escape quotes line breaks" {
  assert_eq(@moon-change-window-auditor.csv_escape("a\nb"), "\"a\nb\"")
  assert_eq(@moon-change-window-auditor.csv_escape("a\rb"), "\"a\rb\"")
}

///|
test "csv_escape handles a mix of comma and quote" {
  assert_eq(
    @moon-change-window-auditor.csv_escape("a,\"b\""),
    "\"a,\"\"b\"\"\"",
  )
}

///|
test "render_windows_csv pins the header and two rows" {
  let plan = plan_of(
    "id=database;service=orders-db;start=2026-10-01T22:00;end=2026-10-01T23:00;risk=high\n" +
    "id=api;start=2026-10-01T22:45;end=2026-10-01T23:15;risk=medium;depends=database\n",
  )
  let expected = "id,service,kind,start,end,minutes,risk,depends\n" +
    "database,orders-db,change,2026-10-01T22:00,2026-10-01T23:00,60,high,\n" +
    "api,,change,2026-10-01T22:45,2026-10-01T23:15,30,medium,database\n"
  assert_eq(@moon-change-window-auditor.render_windows_csv(plan), expected)
}

///|
test "render_windows_csv prints only the header for an empty plan" {
  assert_eq(
    @moon-change-window-auditor.render_windows_csv(plan_of("")),
    "id,service,kind,start,end,minutes,risk,depends\n",
  )
}

///|
test "render_windows_csv orders records by start minute" {
  let plan = plan_of(
    "id=late;start=2026-10-01T23:00;end=2026-10-02T00:00\n" +
    "id=early;start=2026-10-01T22:00;end=2026-10-01T23:00\n",
  )
  assert_eq(
    @moon-change-window-auditor.render_windows_csv(plan),
    "id,service,kind,start,end,minutes,risk,depends\n" +
    "early,,change,2026-10-01T22:00,2026-10-01T23:00,60,medium,\n" +
    "late,,change,2026-10-01T23:00,2026-10-02T00:00,60,medium,\n",
  )
}

///|
test "render_windows_csv joins several dependencies with a pipe" {
  let plan = plan_of(
    "id=a;start=2026-10-01T20:00;end=2026-10-01T21:00\n" +
    "id=b;start=2026-10-01T21:00;end=2026-10-01T22:00\n" +
    "id=c;start=2026-10-01T22:00;end=2026-10-01T23:00;depends=a,b\n",
  )
  let output = @moon-change-window-auditor.render_windows_csv(plan)
  assert_true(
    output.contains(
      "c,,change,2026-10-01T22:00,2026-10-01T23:00,60,medium,a|b\n",
    ),
  )
}

///|
test "render_windows_csv quotes a service that contains a comma" {
  let plan = plan_of(
    "id=a;service=we,ird;start=2026-10-01T22:00;end=2026-10-01T23:00\n",
  )
  let output = @moon-change-window-auditor.render_windows_csv(plan)
  assert_true(output.contains("a,\"we,ird\",change,"))
}

///|
test "render_overlaps_csv pins the header and a row" {
  let report = report_of(
    "id=a;start=2026-10-01T22:00;end=2026-10-01T23:00\n" +
    "id=b;start=2026-10-01T22:30;end=2026-10-01T23:30\n",
  )
  assert_eq(
    @moon-change-window-auditor.render_overlaps_csv(report),
    "first,second,minutes,impact\n" + "a,b,30,minor\n",
  )
}

///|
test "render_overlaps_csv prints the header when there is no overlap" {
  let report = report_of("id=a;start=2026-10-01T22:00;end=2026-10-01T23:00\n")
  assert_eq(
    @moon-change-window-auditor.render_overlaps_csv(report),
    "first,second,minutes,impact\n",
  )
}

///|
test "render_freeze_conflicts_csv pins the header and a row" {
  let report = report_of(
    "id=blackout;kind=freeze;start=2026-10-01T22:00;end=2026-10-01T23:00\n" +
    "id=api;start=2026-10-01T22:30;end=2026-10-01T23:30\n",
  )
  assert_eq(
    @moon-change-window-auditor.render_freeze_conflicts_csv(report),
    "window,freeze,minutes\n" + "api,blackout,30\n",
  )
}

///|
test "render_freeze_conflicts_csv prints the header when there is no conflict" {
  let report = report_of("id=api;start=2026-10-01T22:00;end=2026-10-01T23:00\n")
  assert_eq(
    @moon-change-window-auditor.render_freeze_conflicts_csv(report),
    "window,freeze,minutes\n",
  )
}

///|
test "render_dependency_issues_csv pins the header and a row" {
  let report = report_of(
    "id=api;start=2026-10-01T22:00;end=2026-10-01T23:00;depends=ghost\n",
  )
  assert_eq(
    @moon-change-window-auditor.render_dependency_issues_csv(report),
    "window,dependency,problem,severity,detail\n" +
    "api,ghost,missing-dependency,error,no window with this id exists in the plan\n",
  )
}

///|
test "render_dependency_issues_csv prints the header without an issue" {
  let report = report_of("id=api;start=2026-10-01T22:00;end=2026-10-01T23:00\n")
  assert_eq(
    @moon-change-window-auditor.render_dependency_issues_csv(report),
    "window,dependency,problem,severity,detail\n",
  )
}

///|
test "render_slots_csv pins the rows and the empty case" {
  let slots = [
    slot_of("2026-10-01T20:00", "2026-10-01T21:00"),
    slot_of("2026-10-01T22:00", "2026-10-01T22:30"),
  ]
  assert_eq(
    @moon-change-window-auditor.render_slots_csv(slots),
    "start,end,minutes\n" +
    "2026-10-01T20:00,2026-10-01T21:00,60\n" +
    "2026-10-01T22:00,2026-10-01T22:30,30\n",
  )
  assert_eq(
    @moon-change-window-auditor.render_slots_csv([]),
    "start,end,minutes\n",
  )
}

///|
test "every csv document ends with exactly one newline" {
  let plan = plan_of(
    "id=a;service=svc;start=2026-10-01T22:00;end=2026-10-01T23:00\n" +
    "id=b;start=2026-10-01T22:30;end=2026-10-01T23:30\n",
  )
  let report = @moon-change-window-auditor.audit(plan)
  let documents = [
    @moon-change-window-auditor.render_windows_csv(plan),
    @moon-change-window-auditor.render_overlaps_csv(report),
    @moon-change-window-auditor.render_freeze_conflicts_csv(report),
    @moon-change-window-auditor.render_dependency_issues_csv(report),
    @moon-change-window-auditor.render_slots_csv([]),
  ]
  for document in documents {
    assert_true(csv_ends_with_one_newline(document))
  }
}
