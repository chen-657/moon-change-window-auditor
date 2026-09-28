///|
/// Tests for the Markdown renderer.

///|
/// True when every line of the text ends with a newline.
fn markdown_ends_with_newline(text : String) -> Bool {
  text.length() > 0 && text[text.length() - 1] == '\n'
}

///|
test "render_windows_markdown pins the whole table" {
  let plan = plan_of(
    "id=database;service=orders-db;start=2026-10-01T22:00;end=2026-10-01T23:00;risk=high\n" +
    "id=api;service=orders-api;start=2026-10-01T22:45;end=2026-10-01T23:15;risk=medium;depends=database\n",
  )
  let expected = "| id | service | kind | start | end | duration | risk | depends |\n" +
    "| --- | --- | --- | --- | --- | --- | --- | --- |\n" +
    "| database | orders-db | change | 2026-10-01T22:00 | 2026-10-01T23:00 | 1h | high | - |\n" +
    "| api | orders-api | change | 2026-10-01T22:45 | 2026-10-01T23:15 | 30m | medium | database |\n"
  assert_eq(@moon-change-window-auditor.render_windows_markdown(plan), expected)
}

///|
test "an unnamed service and an empty dependency list render as dashes" {
  let plan = plan_of("id=a;start=2026-10-01T22:00;end=2026-10-01T23:00\n")
  let output = @moon-change-window-auditor.render_windows_markdown(plan)
  assert_true(
    output.contains(
      "| a | - | change | 2026-10-01T22:00 | 2026-10-01T23:00 | 1h | medium | - |\n",
    ),
  )
}

///|
test "a plan without records still renders header and separator" {
  assert_eq(
    @moon-change-window-auditor.render_windows_markdown(plan_of("")),
    "| id | service | kind | start | end | duration | risk | depends |\n" +
    "| --- | --- | --- | --- | --- | --- | --- | --- |\n",
  )
}

///|
test "records are ordered by start minute" {
  let plan = plan_of(
    "id=late;service=s;start=2026-10-01T23:00;end=2026-10-02T00:00\n" +
    "id=early;service=s;start=2026-10-01T22:00;end=2026-10-01T23:00\n",
  )
  let output = @moon-change-window-auditor.render_windows_markdown(plan)
  assert_true(
    output.contains(
      "| early | s | change | 2026-10-01T22:00 | 2026-10-01T23:00 | 1h | medium | - |\n" +
      "| late | s | change | 2026-10-01T23:00 | 2026-10-02T00:00 | 1h | medium | - |\n",
    ),
  )
}

///|
test "a freeze is listed with its kind" {
  let plan = plan_of(
    "id=blackout;service=company;kind=freeze;start=2026-12-24T00:00;end=2026-12-25T00:00\n",
  )
  let output = @moon-change-window-auditor.render_windows_markdown(plan)
  assert_true(
    output.contains(
      "| blackout | company | freeze | 2026-12-24T00:00 | 2026-12-25T00:00 | 24h | medium | - |\n",
    ),
  )
}

///|
test "a pipe inside a cell is escaped" {
  let plan = plan_of(
    "id=a;service=we|ird;start=2026-10-01T22:00;end=2026-10-01T23:00\n",
  )
  let output = @moon-change-window-auditor.render_windows_markdown(plan)
  assert_true(output.contains("| a | we\\|ird |"))
}

///|
test "render_report_markdown opens with the title and the bullet summary" {
  let report = report_of(
    "id=a;service=orders;start=2026-10-01T22:00;end=2026-10-01T23:00;risk=high\n" +
    "id=b;service=payments;start=2026-10-01T22:30;end=2026-10-01T23:30;risk=low\n",
  )
  let output = @moon-change-window-auditor.render_report_markdown(report)
  assert_true(output.has_prefix("# Moon Change Window Audit\n\n"))
  assert_true(output.contains("- status: FAIL\n"))
  assert_true(output.contains("- changes: 2\n"))
  assert_true(output.contains("- freezes: 0\n"))
  assert_true(output.contains("- errors: 1\n"))
  assert_true(output.contains("- warnings: 0\n"))
  assert_true(output.contains("- overlaps: 1\n"))
  assert_true(output.contains("- freeze conflicts: 0\n"))
  assert_true(output.contains("- dependency issues: 0\n"))
  assert_true(output.contains("- blocked: 1h30m\n"))
}

///|
test "render_report_markdown carries every section header" {
  let output = @moon-change-window-auditor.render_report_markdown(
    report_of("id=a;start=2026-10-01T22:00;end=2026-10-01T23:00\n"),
  )
  assert_true(output.contains("\n## Windows\n\n"))
  assert_true(output.contains("\n## Freezes\n\n"))
  assert_true(output.contains("\n## Overlaps\n\n"))
  assert_true(output.contains("\n## Dependency issues\n\n"))
  assert_true(output.contains("\n## Diagnostics\n\n"))
}

///|
test "render_report_markdown writes none for every empty section" {
  let output = @moon-change-window-auditor.render_report_markdown(
    report_of("id=a;start=2026-10-01T22:00;end=2026-10-01T23:00\n"),
  )
  assert_true(output.contains("\n## Freezes\n\nnone\n"))
  assert_true(output.contains("\n## Overlaps\n\nnone\n"))
  assert_true(output.contains("\n## Dependency issues\n\nnone\n"))
  assert_true(output.contains("\n## Diagnostics\n\nnone\n"))
}

///|
test "render_report_markdown lists freezes in their own table" {
  let output = @moon-change-window-auditor.render_report_markdown(
    report_of(
      "id=blackout;service=company;kind=freeze;start=2026-10-01T22:00;end=2026-10-01T23:00\n",
    ),
  )
  assert_true(output.contains("| id | service | start | end | duration |\n"))
  assert_true(
    output.contains(
      "| blackout | company | 2026-10-01T22:00 | 2026-10-01T23:00 | 1h |\n",
    ),
  )
  assert_true(!output.contains("\n## Freezes\n\nnone\n"))
}

///|
test "render_report_markdown carries the overlap and issue rows" {
  let output = @moon-change-window-auditor.render_report_markdown(
    report_of(
      "id=a;start=2026-10-01T22:00;end=2026-10-01T23:00;risk=high\n" +
      "id=b;start=2026-10-01T22:30;end=2026-10-01T23:30;risk=low\n" +
      "id=c;start=2026-10-02T01:00;end=2026-10-02T02:00;depends=ghost\n",
    ),
  )
  assert_true(output.contains("| first | second | minutes | impact |\n"))
  assert_true(output.contains("| a | b | 30 | major |\n"))
  assert_true(
    output.contains("| window | dependency | problem | severity | detail |\n"),
  )
  assert_true(
    output.contains(
      "| c | ghost | missing-dependency | error | no window with this id exists in the plan |\n",
    ),
  )
}

///|
test "render_report_markdown lists diagnostics with their line" {
  let output = @moon-change-window-auditor.render_report_markdown(
    report_of(
      "id=a;owner=payments;start=2026-10-01T22:00;end=2026-10-01T23:00\n",
    ),
  )
  assert_true(output.contains("| severity | line | code | detail |\n"))
  assert_true(output.contains("| warning | 1 | unknown-field | owner |\n"))
}

///|
test "render_slots_markdown pins the table and the count" {
  let slots = [slot_of("2026-10-01T20:00", "2026-10-01T21:00")]
  assert_eq(
    @moon-change-window-auditor.render_slots_markdown(slots),
    "Safe change slots (1)\n\n" +
    "| start | end | duration |\n" +
    "| --- | --- | --- |\n" +
    "| 2026-10-01T20:00 | 2026-10-01T21:00 | 1h |\n",
  )
}

///|
test "render_slots_markdown writes none when there is no slot" {
  assert_eq(
    @moon-change-window-auditor.render_slots_markdown([]),
    "Safe change slots (0)\n\nnone\n",
  )
}

///|
test "every markdown document ends with exactly one newline" {
  let plan = plan_of(
    "id=a;service=svc;start=2026-10-01T22:00;end=2026-10-01T23:00\n",
  )
  let report = @moon-change-window-auditor.audit(plan)
  let documents = [
    @moon-change-window-auditor.render_windows_markdown(plan),
    @moon-change-window-auditor.render_report_markdown(report),
    @moon-change-window-auditor.render_slots_markdown([
      slot_of("2026-10-01T20:00", "2026-10-01T21:00"),
    ]),
    @moon-change-window-auditor.render_slots_markdown([]),
  ]
  for document in documents {
    assert_true(markdown_ends_with_newline(document))
    assert_true(
      document.length() < 2 || document[document.length() - 2] != '\n',
    )
  }
}
