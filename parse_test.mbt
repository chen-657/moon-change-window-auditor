///|
/// Tests for the plan text format and for every diagnostic it can report.

///|
test "every field is read" {
  let plan = plan_of(
    "id=database;service=orders-db;start=2026-10-01T22:00;end=2026-10-01T23:30;risk=high;depends=\n" +
    "id=api;service=orders-api;start=2026-10-01T23:30;end=2026-10-02T00:00;risk=low;depends=database\n",
  )
  assert_eq(plan.window_count(), 2)
  assert_eq(plan.diagnostics.length(), 0)
  assert_true(!plan.has_errors())
  let database = match plan.find("database") {
    Some(window) => window
    None => fail("database window missing")
  }
  assert_eq(database.service, "orders-db")
  assert_eq(database.risk.label(), "high")
  assert_eq(database.duration(), 90)
  assert_eq(database.depends.length(), 0)
  let api = match plan.find("api") {
    Some(window) => window
    None => fail("api window missing")
  }
  assert_eq(api.service, "orders-api")
  assert_eq(api.risk.label(), "low")
  assert_eq(api.depends, ["database"])
  assert_eq(api.start, database.end)
  assert_true(plan.find("missing") is None)
}

///|
test "risk defaults to medium and rejects other spellings" {
  let plan = plan_of(
    "id=a;start=2026-10-01T22:00;end=2026-10-01T23:00\n" +
    "id=b;start=2026-10-01T22:00;end=2026-10-01T23:00;risk=HIGH\n" +
    "id=c;start=2026-10-01T22:00;end=2026-10-01T23:00;risk=medium\n",
  )
  assert_eq(plan.window_count(), 2)
  assert_eq(plan.find("a").unwrap().risk.label(), "medium")
  assert_eq(plan.find("c").unwrap().risk.label(), "medium")
  assert_eq(plan.diagnostics.length(), 1)
  assert_eq(plan.diagnostics[0].code, "invalid-risk")
  assert_eq(plan.diagnostics[0].detail, "HIGH")
  assert_eq(plan.diagnostics[0].line, 2)
}

///|
test "comments, blank lines and empty fields are ignored" {
  let plan = plan_of(
    "# nightly plan\n" +
    "\n" +
    "id=a;start=2026-10-01T22:00;end=2026-10-01T23:00;;\n" +
    "   # indented comment\n" +
    "id=b;service=;risk=low;depends=;start=2026-10-01T23:00;end=2026-10-02T00:00;\n",
  )
  assert_eq(plan.window_count(), 2)
  assert_eq(plan.diagnostics.length(), 0)
  assert_eq(plan.find("b").unwrap().service, "")
  assert_eq(
    plan.find("b").unwrap().to_line(),
    "b | - | 2026-10-01T23:00 -> 2026-10-02T00:00 | 1h | low | -",
  )
}

///|
test "missing required fields drop the record and report each one" {
  let plan = plan_of("service=orders;id=a;start=2026-10-01T22:00\n")
  assert_eq(plan.window_count(), 0)
  assert_eq(plan.diagnostics.length(), 1)
  assert_eq(plan.diagnostics[0].severity.label(), "error")
  assert_eq(plan.diagnostics[0].code, "missing-field")
  assert_eq(plan.diagnostics[0].detail, "end")
  assert_true(plan.has_errors())
}

///|
test "an empty line is not a record with missing fields" {
  let plan = plan_of("\n\n")
  assert_eq(plan.window_count(), 0)
  assert_eq(plan.diagnostics.length(), 0)
}

///|
test "invalid instants are reported with their field and text" {
  let plan = plan_of(
    "id=a;start=2026-13-01T22:00;end=2026-10-01T23:00\n" +
    "id=b;start=2026-10-01T22:00;end=tomorrow\n",
  )
  assert_eq(plan.window_count(), 0)
  assert_eq(plan.diagnostics.length(), 2)
  assert_eq(plan.diagnostics[0].code, "invalid-instant")
  assert_eq(plan.diagnostics[0].detail, "start=\"2026-13-01T22:00\"")
  assert_eq(plan.diagnostics[1].code, "invalid-instant")
  assert_eq(plan.diagnostics[1].detail, "end=\"tomorrow\"")
  assert_eq(plan.diagnostics[1].line, 2)
}

///|
test "a window must end after it starts" {
  let plan = plan_of(
    "id=a;start=2026-10-01T23:00;end=2026-10-01T23:00\n" +
    "id=b;start=2026-10-01T23:00;end=2026-10-01T22:00\n",
  )
  assert_eq(plan.window_count(), 0)
  assert_eq(plan.diagnostics.length(), 2)
  assert_eq(plan.diagnostics[0].code, "end-not-after-start")
  assert_eq(plan.diagnostics[0].detail, "2026-10-01T23:00 -> 2026-10-01T23:00")
  assert_eq(plan.diagnostics[1].detail, "2026-10-01T23:00 -> 2026-10-01T22:00")
}

///|
test "unknown fields warn but keep the record" {
  let plan = plan_of(
    "id=a;owner=payments;start=2026-10-01T22:00;end=2026-10-01T23:00\n",
  )
  assert_eq(plan.window_count(), 1)
  assert_eq(plan.diagnostics.length(), 1)
  assert_eq(plan.diagnostics[0].severity.label(), "warning")
  assert_eq(plan.diagnostics[0].code, "unknown-field")
  assert_eq(plan.diagnostics[0].detail, "owner")
  assert_eq(plan.diagnostics[0].line, 1)
  assert_true(!plan.has_errors())
}

///|
test "repeated fields, malformed fields and invalid ids are errors" {
  let repeated = plan_of(
    "id=a;id=b;start=2026-10-01T22:00;end=2026-10-01T23:00\n",
  )
  assert_eq(repeated.window_count(), 0)
  assert_eq(repeated.diagnostics[0].code, "duplicate-field")
  assert_eq(repeated.diagnostics[0].detail, "id")
  let malformed = plan_of(
    "id=a;start=2026-10-01T22:00;end=2026-10-01T23:00;oops\n",
  )
  assert_eq(malformed.window_count(), 0)
  assert_eq(malformed.diagnostics[0].code, "malformed-field")
  assert_eq(malformed.diagnostics[0].detail, "oops")
  let bad_id = plan_of(
    "id=bad id;start=2026-10-01T22:00;end=2026-10-01T23:00\n",
  )
  assert_eq(bad_id.window_count(), 0)
  assert_eq(bad_id.diagnostics[0].code, "invalid-id")
  assert_eq(bad_id.diagnostics[0].detail, "bad id")
}

///|
test "duplicate ids are reported but both windows are kept" {
  let plan = plan_of(
    "id=a;start=2026-10-01T22:00;end=2026-10-01T23:00\n" +
    "id=a;start=2026-10-02T22:00;end=2026-10-02T23:00\n",
  )
  assert_eq(plan.window_count(), 2)
  assert_eq(plan.diagnostics.length(), 1)
  assert_eq(plan.diagnostics[0].code, "duplicate-id")
  assert_eq(plan.diagnostics[0].detail, "a")
  assert_eq(plan.diagnostics[0].line, 2)
  // Lookups keep using the first record, so a dependency stays unambiguous.
  assert_eq(plan.find("a").unwrap().start, instant_of("2026-10-01T22:00"))
}

///|
test "dependency lists are split, trimmed and validated" {
  let plan = plan_of(
    "id=a;start=2026-10-01T20:00;end=2026-10-01T21:00\n" +
    "id=b;start=2026-10-01T21:00;end=2026-10-01T22:00\n" +
    "id=c;start=2026-10-01T22:00;end=2026-10-01T23:00;depends=a, b ,\n",
  )
  assert_eq(plan.window_count(), 3)
  assert_eq(plan.diagnostics.length(), 0)
  assert_eq(plan.find("c").unwrap().depends, ["a", "b"])
}

///|
test "a repeated dependency warns once and keeps one entry" {
  let plan = plan_of(
    "id=a;start=2026-10-01T20:00;end=2026-10-01T21:00\n" +
    "id=b;start=2026-10-01T21:00;end=2026-10-01T22:00;depends=a,a\n",
  )
  assert_eq(plan.window_count(), 2)
  assert_eq(plan.diagnostics.length(), 1)
  assert_eq(plan.diagnostics[0].code, "duplicate-dependency")
  assert_eq(plan.diagnostics[0].detail, "a")
  assert_eq(plan.find("b").unwrap().depends, ["a"])
}

///|
test "an invalid dependency id is an error and drops the record" {
  let plan = plan_of(
    "id=a;start=2026-10-01T20:00;end=2026-10-01T21:00\n" +
    "id=b;start=2026-10-01T21:00;end=2026-10-01T22:00;depends=bad dep\n",
  )
  assert_eq(plan.window_count(), 1)
  assert_eq(plan.diagnostics.length(), 1)
  assert_eq(plan.diagnostics[0].code, "invalid-dependency")
  assert_eq(plan.diagnostics[0].detail, "bad dep")
}

///|
test "windows keep their own line numbers when earlier lines fail" {
  let plan = plan_of(
    "id=a;start=nope;end=2026-10-01T23:00\n" +
    "id=b;start=2026-10-02T22:00;end=2026-10-02T23:00\n",
  )
  assert_eq(plan.window_count(), 1)
  assert_eq(plan.diagnostics[0].line, 1)
  assert_eq(plan.find("b").unwrap().service, "")
}

///|
test "carriage returns are handled" {
  let plan = plan_of(
    "id=a;start=2026-10-01T22:00;end=2026-10-01T23:00\r\nid=b;start=2026-10-01T23:00;end=2026-10-02T00:00\r\n",
  )
  assert_eq(plan.window_count(), 2)
  assert_eq(plan.diagnostics.length(), 0)
}
