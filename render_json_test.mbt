///|
/// Tests for the JSON renderer.
///
/// The pinned strings are checked against the layout rules the module
/// documents: two spaces per level, a comma between siblings and none after the
/// last one, empty arrays inline and exactly one trailing newline.

///|
/// Difference between opening and closing brackets outside of string literals.
/// Zero means the document is balanced.
fn json_balance(text : String) -> Int {
  let mut depth = 0
  let mut in_string = false
  let mut escaped = false
  for character in text {
    if in_string {
      if escaped {
        escaped = false
      } else if character == '\\' {
        escaped = true
      } else if character == '"' {
        in_string = false
      }
      continue
    }
    if character == '"' {
      in_string = true
    } else if character == '{' || character == '[' {
      depth = depth + 1
    } else if character == '}' || character == ']' {
      depth = depth - 1
    }
  }
  depth
}

///|
/// True when a line ends with a comma that is directly followed by a closing
/// bracket, which would make the document invalid.
fn json_has_trailing_comma(text : String) -> Bool {
  let lines = text.split("\n").to_array()
  for index = 0; index + 1 < lines.length(); index = index + 1 {
    let current = lines[index].trim().to_owned()
    let next = lines[index + 1].trim().to_owned()
    if current.length() > 0 && current[current.length() - 1] == ',' {
      if next == "]" || next == "}" {
        return true
      }
    }
  }
  false
}

///|
test "json_escape leaves plain text alone" {
  assert_eq(@moon-change-window-auditor.json_escape("plain text"), "plain text")
  assert_eq(@moon-change-window-auditor.json_escape(""), "")
  assert_eq(
    @moon-change-window-auditor.json_escape("2026-10-01T22:00"),
    "2026-10-01T22:00",
  )
}

///|
test "json_escape escapes quotes and backslashes" {
  assert_eq(@moon-change-window-auditor.json_escape("\""), "\\\"")
  assert_eq(@moon-change-window-auditor.json_escape("\\"), "\\\\")
  assert_eq(
    @moon-change-window-auditor.json_escape("start=\"nope\""),
    "start=\\\"nope\\\"",
  )
}

///|
test "json_escape escapes whitespace controls" {
  assert_eq(@moon-change-window-auditor.json_escape("\n"), "\\n")
  assert_eq(@moon-change-window-auditor.json_escape("\r"), "\\r")
  assert_eq(@moon-change-window-auditor.json_escape("\t"), "\\t")
  assert_eq(@moon-change-window-auditor.json_escape("a\nb"), "a\\nb")
}

///|
test "json_escape renders other control characters as u escapes" {
  assert_eq(@moon-change-window-auditor.json_escape("\u{0001}"), "\\u0001")
  assert_eq(@moon-change-window-auditor.json_escape("\u{001f}"), "\\u001f")
  assert_eq(@moon-change-window-auditor.json_escape("\u{0008}"), "\\b")
  assert_eq(@moon-change-window-auditor.json_escape("\u{000c}"), "\\f")
}

///|
test "json_escape keeps multi byte text readable" {
  assert_eq(@moon-change-window-auditor.json_escape("订单"), "订单")
  assert_eq(@moon-change-window-auditor.json_escape("café"), "café")
}

///|
test "render_plan_json pins the whole document of a single record" {
  let plan = plan_of(
    "id=a;service=svc;start=2026-10-01T22:00;end=2026-10-01T23:00\n",
  )
  let expected = "{\n" +
    "  \"windows\": [\n" +
    "    {\n" +
    "      \"id\": \"a\",\n" +
    "      \"service\": \"svc\",\n" +
    "      \"kind\": \"change\",\n" +
    "      \"start\": \"2026-10-01T22:00\",\n" +
    "      \"end\": \"2026-10-01T23:00\",\n" +
    "      \"minutes\": 60,\n" +
    "      \"risk\": \"medium\",\n" +
    "      \"depends\": []\n" +
    "    }\n" +
    "  ],\n" +
    "  \"diagnostics\": []\n" +
    "}\n"
  assert_eq(@moon-change-window-auditor.render_plan_json(plan), expected)
}

///|
test "render_plan_json escapes a diagnostic detail" {
  let plan = plan_of(
    "id=a;start=2026-10-01T22:00;end=2026-10-01T23:00\n" +
    "id=b;start=nope;end=2026-10-01T23:00\n",
  )
  let output = @moon-change-window-auditor.render_plan_json(plan)
  assert_true(output.contains("  \"diagnostics\": [\n"))
  assert_true(output.contains("      \"severity\": \"error\",\n"))
  assert_true(output.contains("      \"line\": 2,\n"))
  assert_true(output.contains("      \"code\": \"invalid-instant\",\n"))
  assert_true(output.contains("      \"detail\": \"start=\\\"nope\\\"\"\n"))
  assert_true(!output.contains("\"id\": \"b\""))
}

///|
test "render_plan_json renders a dependency array on its own lines" {
  let plan = plan_of(
    "id=base;start=2026-10-01T20:00;end=2026-10-01T21:00\n" +
    "id=api;start=2026-10-01T21:00;end=2026-10-01T22:00;depends=base\n",
  )
  let output = @moon-change-window-auditor.render_plan_json(plan)
  assert_true(
    output.contains("      \"depends\": [\n        \"base\"\n      ]\n"),
  )
  assert_true(output.contains("      \"depends\": []\n"))
}

///|
test "render_plan_json marks a freeze record" {
  let plan = plan_of(
    "id=blackout;service=company;kind=freeze;start=2026-12-24T00:00;end=2026-12-25T00:00\n",
  )
  let output = @moon-change-window-auditor.render_plan_json(plan)
  assert_true(output.contains("      \"kind\": \"freeze\",\n"))
  assert_true(output.contains("      \"minutes\": 1440,\n"))
  assert_true(output.contains("      \"depends\": []\n"))
}

///|
test "render_plan_json orders records by start minute" {
  let plan = plan_of(
    "id=late;start=2026-10-01T23:00;end=2026-10-02T00:00\n" +
    "id=early;start=2026-10-01T22:00;end=2026-10-01T23:00\n",
  )
  let expected = "{\n" +
    "  \"windows\": [\n" +
    "    {\n" +
    "      \"id\": \"early\",\n" +
    "      \"service\": \"\",\n" +
    "      \"kind\": \"change\",\n" +
    "      \"start\": \"2026-10-01T22:00\",\n" +
    "      \"end\": \"2026-10-01T23:00\",\n" +
    "      \"minutes\": 60,\n" +
    "      \"risk\": \"medium\",\n" +
    "      \"depends\": []\n" +
    "    },\n" +
    "    {\n" +
    "      \"id\": \"late\",\n" +
    "      \"service\": \"\",\n" +
    "      \"kind\": \"change\",\n" +
    "      \"start\": \"2026-10-01T23:00\",\n" +
    "      \"end\": \"2026-10-02T00:00\",\n" +
    "      \"minutes\": 60,\n" +
    "      \"risk\": \"medium\",\n" +
    "      \"depends\": []\n" +
    "    }\n" +
    "  ],\n" +
    "  \"diagnostics\": []\n" +
    "}\n"
  assert_eq(@moon-change-window-auditor.render_plan_json(plan), expected)
}

///|
test "render_plan_json of an empty plan inlines both arrays" {
  assert_eq(
    @moon-change-window-auditor.render_plan_json(plan_of("")),
    "{\n  \"windows\": [],\n  \"diagnostics\": []\n}\n",
  )
}

///|
test "render_report_json carries the summary and the collections" {
  let report = report_of(
    "id=a;service=orders;start=2026-10-01T22:00;end=2026-10-01T23:00;risk=high\n" +
    "id=b;service=payments;start=2026-10-01T22:30;end=2026-10-01T23:30;risk=low\n",
  )
  let output = @moon-change-window-auditor.render_report_json(report)
  assert_true(output.contains("  \"status\": \"FAIL\",\n"))
  assert_true(output.contains("  \"errors\": 1,\n"))
  assert_true(output.contains("  \"warnings\": 0,\n"))
  assert_true(output.contains("  \"blocked_minutes\": 90,\n"))
  assert_true(
    output.contains(
      "      \"first\": \"a\",\n      \"second\": \"b\",\n      \"minutes\": 30,\n      \"impact\": \"major\"\n",
    ),
  )
  assert_true(output.contains("  \"freeze_conflicts\": [],\n"))
  assert_true(output.contains("  \"dependency_issues\": [],\n"))
  assert_eq(json_balance(output), 0)
}

///|
test "render_report_json renders freeze conflicts and dependency issues" {
  let report = report_of(
    "id=blackout;service=company;kind=freeze;start=2026-10-01T22:00;end=2026-10-01T23:00\n" +
    "id=api;start=2026-10-01T22:30;end=2026-10-01T23:30;depends=ghost\n",
  )
  let output = @moon-change-window-auditor.render_report_json(report)
  assert_true(
    output.contains(
      "      \"window\": \"api\",\n      \"freeze\": \"blackout\",\n      \"minutes\": 30\n",
    ),
  )
  assert_true(output.contains("      \"problem\": \"missing-dependency\",\n"))
  assert_true(output.contains("      \"severity\": \"error\",\n"))
  assert_true(
    output.contains(
      "      \"detail\": \"no window with this id exists in the plan\"\n",
    ),
  )
}

///|
test "render_report_json separates every change and freeze" {
  let report = report_of(
    "id=api;service=orders;start=2026-10-01T22:00;end=2026-10-01T23:00\n" +
    "id=blackout;kind=freeze;start=2026-12-24T00:00;end=2026-12-25T00:00\n",
  )
  let output = @moon-change-window-auditor.render_report_json(report)
  assert_true(output.contains("  \"changes\": [\n"))
  assert_true(output.contains("  \"freezes\": [\n"))
  assert_true(output.contains("      \"id\": \"api\",\n"))
  assert_true(output.contains("      \"id\": \"blackout\",\n"))
}

///|
test "render_report_json keeps the diagnostics of the plan" {
  let report = report_of(
    "id=a;owner=payments;start=2026-10-01T22:00;end=2026-10-01T23:00\n",
  )
  let output = @moon-change-window-auditor.render_report_json(report)
  assert_true(output.contains("      \"severity\": \"warning\",\n"))
  assert_true(output.contains("      \"code\": \"unknown-field\",\n"))
  assert_true(output.contains("      \"detail\": \"owner\"\n"))
}

///|
test "render_slots_json pins two slots in input order" {
  let slots = [
    slot_of("2026-10-01T20:00", "2026-10-01T21:00"),
    slot_of("2026-10-01T22:00", "2026-10-01T23:00"),
  ]
  let expected = "[\n" +
    "  {\n" +
    "    \"start\": \"2026-10-01T20:00\",\n" +
    "    \"end\": \"2026-10-01T21:00\",\n" +
    "    \"minutes\": 60\n" +
    "  },\n" +
    "  {\n" +
    "    \"start\": \"2026-10-01T22:00\",\n" +
    "    \"end\": \"2026-10-01T23:00\",\n" +
    "    \"minutes\": 60\n" +
    "  }\n" +
    "]\n"
  assert_eq(@moon-change-window-auditor.render_slots_json(slots), expected)
}

///|
test "render_slots_json of no slots is an inline empty array" {
  assert_eq(@moon-change-window-auditor.render_slots_json([]), "[]\n")
}

///|
test "every rendered document is balanced and free of trailing commas" {
  let plan = plan_of(
    "id=database;service=orders-db;start=2026-10-01T22:00;end=2026-10-01T23:00;risk=high\n" +
    "id=api;service=orders-api;start=2026-10-01T22:45;end=2026-10-01T23:15;depends=database\n" +
    "id=blackout;kind=freeze;start=2026-10-01T22:50;end=2026-10-02T01:00\n" +
    "id=broken;start=nope;end=2026-10-01T23:00\n",
  )
  let report = @moon-change-window-auditor.audit(plan)
  let documents = [
    @moon-change-window-auditor.render_plan_json(plan),
    @moon-change-window-auditor.render_report_json(report),
    @moon-change-window-auditor.render_slots_json(
      @moon-change-window-auditor.safe_slots(
        plan,
        instant_of("2026-10-01T20:00"),
        instant_of("2026-10-02T04:00"),
        30,
      ),
    ),
  ]
  for document in documents {
    assert_eq(json_balance(document), 0)
    assert_true(!json_has_trailing_comma(document))
    assert_true(document.length() > 0)
    assert_eq(document[document.length() - 1], '\n')
  }
}

///|
test "every object field line but the last one ends with a comma" {
  let plan = plan_of(
    "id=a;service=svc;start=2026-10-01T22:00;end=2026-10-01T23:00\n",
  )
  let output = @moon-change-window-auditor.render_plan_json(plan)
  assert_true(output.contains("      \"id\": \"a\",\n"))
  assert_true(output.contains("      \"service\": \"svc\",\n"))
  assert_true(output.contains("      \"minutes\": 60,\n"))
  assert_true(output.contains("      \"depends\": []\n    }\n"))
}
