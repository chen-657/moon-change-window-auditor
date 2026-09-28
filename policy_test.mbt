///|
/// Tests for the change policy layer: thresholds, rule order, counts and text.

///|
/// A policy whose every rule is off except the ones a test switches on.
fn policy_rules(
  max_concurrent : Int,
  max_change_minutes : Int,
  min_dependency_slack_minutes : Int,
  forbid_high_risk_overlap : Bool,
  max_high_risk_per_day : Int,
  forbid_freeze_conflicts : Bool,
  require_service : Bool,
) -> @moon-change-window-auditor.Policy {
  {
    max_concurrent,
    max_change_minutes,
    min_dependency_slack_minutes,
    forbid_high_risk_overlap,
    max_high_risk_per_day,
    forbid_freeze_conflicts,
    require_service,
  }
}

///|
/// Relaxed policy with only the plan wide and per service concurrency rule on.
fn policy_only_max_concurrent(
  limit : Int,
) -> @moon-change-window-auditor.Policy {
  policy_rules(limit, 0, 0, false, 0, false, false)
}

///|
/// Relaxed policy with only the change length rule on.
fn policy_only_max_change_minutes(
  limit : Int,
) -> @moon-change-window-auditor.Policy {
  policy_rules(0, limit, 0, false, 0, false, false)
}

///|
/// Relaxed policy with only the dependency slack rule on.
fn policy_only_min_dependency_slack(
  limit : Int,
) -> @moon-change-window-auditor.Policy {
  policy_rules(0, 0, limit, false, 0, false, false)
}

///|
/// Relaxed policy with only the high risk overlap rule on.
fn policy_only_forbid_high_risk_overlap() -> @moon-change-window-auditor.Policy {
  policy_rules(0, 0, 0, true, 0, false, false)
}

///|
/// Relaxed policy with only the daily high risk budget on.
fn policy_only_max_high_risk_per_day(
  limit : Int,
) -> @moon-change-window-auditor.Policy {
  policy_rules(0, 0, 0, false, limit, false, false)
}

///|
/// Relaxed policy with only the freeze rule on.
fn policy_only_forbid_freeze_conflicts() -> @moon-change-window-auditor.Policy {
  policy_rules(0, 0, 0, false, 0, true, false)
}

///|
/// Relaxed policy with only the service requirement on.
fn policy_only_require_service() -> @moon-change-window-auditor.Policy {
  policy_rules(0, 0, 0, false, 0, false, true)
}

///|
/// Judge a plan given in text form against a policy.
fn policy_report_of(
  source : String,
  policy : @moon-change-window-auditor.Policy,
) -> @moon-change-window-auditor.PolicyReport {
  @moon-change-window-auditor.audit_with_policy(plan_of(source), policy)
}

///|
/// The violations of a plan given in text form, judged against a policy.
fn policy_violations_of(
  source : String,
  policy : @moon-change-window-auditor.Policy,
) -> Array[@moon-change-window-auditor.PolicyViolation] {
  policy_report_of(source, policy).violations
}

///|
/// The rendered line of every violation, one array entry each.
fn policy_lines(
  source : String,
  policy : @moon-change-window-auditor.Policy,
) -> Array[String] {
  let lines : Array[String] = []
  for violation in policy_violations_of(source, policy) {
    lines.push(violation.to_line())
  }
  lines
}

///|
/// The rule codes of the violations, joined with `,`, to pin rule order.
fn policy_codes(
  violations : Array[@moon-change-window-auditor.PolicyViolation],
) -> String {
  let builder = StringBuilder()
  for index = 0; index < violations.length(); index = index + 1 {
    if index > 0 {
      builder.write_char(',')
    }
    builder.write_string(violations[index].code)
  }
  builder.to_string()
}

///|
/// Number of newline characters at the very end of a rendered text.
fn policy_trailing_newlines(text : String) -> Int {
  let characters = text.iter().to_array()
  let mut total = 0
  let mut index = characters.length() - 1
  while index >= 0 && characters[index] == '\n' {
    total = total + 1
    index = index - 1
  }
  total
}

///|
/// Number of newline characters, used to prove `describe` has no trailing one.
fn policy_newline_count(text : String) -> Int {
  let mut total = 0
  for character in text.iter() {
    if character == '\n' {
      total = total + 1
    }
  }
  total
}

///|
/// Render the violations of a plan and a policy, one per line.
fn policy_violation_text(
  source : String,
  policy : @moon-change-window-auditor.Policy,
) -> String {
  @moon-change-window-auditor.render_violations(
    policy_violations_of(source, policy),
  )
}

///|
test "Policy::standard is pinned field by field and in text" {
  let policy = @moon-change-window-auditor.Policy::standard()
  assert_eq(policy.max_concurrent, 0)
  assert_eq(policy.max_change_minutes, 0)
  assert_eq(policy.min_dependency_slack_minutes, 0)
  assert_true(!policy.forbid_high_risk_overlap)
  assert_eq(policy.max_high_risk_per_day, 0)
  assert_true(policy.forbid_freeze_conflicts)
  assert_true(!policy.require_service)
  assert_eq(
    policy.describe(),
    "max_concurrent = unlimited\n" +
    "max_change_minutes = unlimited\n" +
    "min_dependency_slack_minutes = unlimited\n" +
    "forbid_high_risk_overlap = false\n" +
    "max_high_risk_per_day = unlimited\n" +
    "forbid_freeze_conflicts = true\n" +
    "require_service = false",
  )
}

///|
test "Policy::strict is pinned field by field and in text" {
  let policy = @moon-change-window-auditor.Policy::strict()
  assert_eq(policy.max_concurrent, 2)
  assert_eq(policy.max_change_minutes, 120)
  assert_eq(policy.min_dependency_slack_minutes, 30)
  assert_true(policy.forbid_high_risk_overlap)
  assert_eq(policy.max_high_risk_per_day, 2)
  assert_true(policy.forbid_freeze_conflicts)
  assert_true(policy.require_service)
  assert_eq(
    policy.describe(),
    "max_concurrent = 2\n" +
    "max_change_minutes = 120\n" +
    "min_dependency_slack_minutes = 30\n" +
    "forbid_high_risk_overlap = true\n" +
    "max_high_risk_per_day = 2\n" +
    "forbid_freeze_conflicts = true\n" +
    "require_service = true",
  )
}

///|
test "Policy::relaxed turns every rule off" {
  let policy = @moon-change-window-auditor.Policy::relaxed()
  assert_eq(policy.max_concurrent, 0)
  assert_eq(policy.max_change_minutes, 0)
  assert_eq(policy.min_dependency_slack_minutes, 0)
  assert_true(!policy.forbid_high_risk_overlap)
  assert_eq(policy.max_high_risk_per_day, 0)
  assert_true(!policy.forbid_freeze_conflicts)
  assert_true(!policy.require_service)
  assert_eq(
    policy.describe(),
    "max_concurrent = unlimited\n" +
    "max_change_minutes = unlimited\n" +
    "min_dependency_slack_minutes = unlimited\n" +
    "forbid_high_risk_overlap = false\n" +
    "max_high_risk_per_day = unlimited\n" +
    "forbid_freeze_conflicts = false\n" +
    "require_service = false",
  )
}

///|
test "describe renders zero as unlimited and flags as words without a trailing newline" {
  let policy = policy_only_max_concurrent(3)
  let text = policy.describe()
  assert_true(text.contains("max_concurrent = 3"))
  assert_true(text.contains("max_change_minutes = unlimited"))
  assert_true(text.contains("forbid_high_risk_overlap = false"))
  assert_true(text.contains("require_service = false"))
  // Seven settings, six separators: the last line has no newline after it.
  assert_eq(policy_newline_count(text), 6)
  assert_true(!text.has_suffix("\n"))
  assert_true(text.has_suffix("require_service = false"))
}

///|
test "max-concurrent does not fire when the peak is exactly the limit" {
  let source = "id=a;service=orders;start=2026-10-01T22:00;end=2026-10-01T23:00\n" +
    "id=b;service=orders;start=2026-10-01T22:30;end=2026-10-01T23:30\n"
  assert_eq(
    policy_violations_of(source, policy_only_max_concurrent(2)).length(),
    0,
  )
}

///|
test "max-concurrent fires plan wide and per service once above the limit" {
  let source = "id=a;service=orders;start=2026-10-01T22:00;end=2026-10-01T23:00\n" +
    "id=b;service=orders;start=2026-10-01T22:30;end=2026-10-01T23:30\n"
  let lines = policy_lines(source, policy_only_max_concurrent(1))
  assert_eq(lines.length(), 2)
  // The peak is reached at 22:30, when the two changes actually run together.
  assert_eq(
    lines[0],
    "error max-concurrent (all): 2 simultaneous changes at 2026-10-01T22:30 exceed the limit of 1",
  )
  assert_eq(
    lines[1],
    "error max-concurrent (orders): 2 simultaneous changes at 2026-10-01T22:30 exceed the limit of 1",
  )
}

///|
test "max-concurrent reports services in code point order at their own peak" {
  let source = "id=a;service=beta;start=2026-10-01T22:00;end=2026-10-01T23:00\n" +
    "id=b;service=alpha;start=2026-10-01T22:00;end=2026-10-01T23:00\n" +
    "id=c;service=alpha;start=2026-10-01T22:15;end=2026-10-01T22:45\n"
  // At the limit of two the plan holds three changes at 22:15 while no single
  // service reaches three, so only the plan wide entry fires.
  let at_limit = policy_lines(source, policy_only_max_concurrent(2))
  assert_eq(at_limit.length(), 1)
  assert_eq(
    at_limit[0],
    "error max-concurrent (all): 3 simultaneous changes at 2026-10-01T22:15 exceed the limit of 2",
  )
  let above = policy_lines(source, policy_only_max_concurrent(1))
  assert_eq(above.length(), 2)
  assert_eq(
    above[0],
    "error max-concurrent (all): 3 simultaneous changes at 2026-10-01T22:15 exceed the limit of 1",
  )
  assert_eq(
    above[1],
    "error max-concurrent (alpha): 2 simultaneous changes at 2026-10-01T22:15 exceed the limit of 1",
  )
}

///|
test "max-concurrent stays silent for a plan without changes" {
  assert_eq(policy_violations_of("", policy_only_max_concurrent(1)).length(), 0)
  let only_freeze = "kind=freeze;id=blackout;start=2026-12-24T00:00;end=2026-12-27T00:00\n"
  assert_eq(
    policy_violations_of(only_freeze, policy_only_max_concurrent(1)).length(),
    0,
  )
}

///|
test "max-change-minutes does not fire at the limit" {
  let source = "id=a;start=2026-10-01T22:00;end=2026-10-01T23:00\n"
  assert_eq(
    policy_violations_of(source, policy_only_max_change_minutes(60)).length(),
    0,
  )
}

///|
test "max-change-minutes fires above the limit with both durations" {
  let source = "id=a;start=2026-10-01T22:00;end=2026-10-01T23:00\n"
  let lines = policy_lines(source, policy_only_max_change_minutes(30))
  assert_eq(lines.length(), 1)
  assert_eq(
    lines[0],
    "error max-change-minutes (a): the change lasts 1h, the limit is 30m",
  )
}

///|
test "max-change-minutes never measures a freeze" {
  let source = "id=a;start=2026-10-01T22:00;end=2026-10-01T23:00\n" +
    "kind=freeze;id=blackout;start=2026-12-24T00:00;end=2026-12-27T00:00\n"
  let plan = plan_of(source)
  // The freeze is three days long, far beyond the 120 minute limit.
  assert_eq(plan.freezes()[0].duration(), 4320)
  assert_eq(
    policy_violations_of(source, policy_only_max_change_minutes(120)).length(),
    0,
  )
}

///|
test "min-dependency-slack does not fire at the limit" {
  let source = "id=db;start=2026-10-01T20:00;end=2026-10-01T21:00\n" +
    "id=api;start=2026-10-01T21:30;end=2026-10-01T22:00;depends=db\n"
  assert_eq(
    policy_violations_of(source, policy_only_min_dependency_slack(30)).length(),
    0,
  )
}

///|
test "min-dependency-slack fires below the limit and reports the magnitude" {
  let source = "id=db;start=2026-10-01T20:00;end=2026-10-01T21:00\n" +
    "id=api;start=2026-10-01T21:30;end=2026-10-01T22:00;depends=db\n"
  let lines = policy_lines(source, policy_only_min_dependency_slack(31))
  assert_eq(lines.length(), 1)
  assert_eq(
    lines[0],
    "warning min-dependency-slack (api): only 30m of slack after db, the minimum is 31m",
  )
}

///|
test "min-dependency-slack reports a back to back dependency as zero slack" {
  let source = "id=db;start=2026-10-01T20:00;end=2026-10-01T21:00\n" +
    "id=api;start=2026-10-01T21:00;end=2026-10-01T21:30;depends=db\n"
  let lines = policy_lines(source, policy_only_min_dependency_slack(1))
  assert_eq(lines.length(), 1)
  assert_eq(
    lines[0],
    "warning min-dependency-slack (api): only 0m of slack after db, the minimum is 1m",
  )
}

///|
test "min-dependency-slack reports a negative slack as an overlap" {
  let source = "id=db;start=2026-10-01T22:00;end=2026-10-01T23:30\n" +
    "id=api;start=2026-10-01T22:45;end=2026-10-01T23:15;depends=db\n"
  let lines = policy_lines(source, policy_only_min_dependency_slack(30))
  assert_eq(lines.length(), 1)
  assert_eq(
    lines[0],
    "warning min-dependency-slack (api): overlaps db and misses the minimum slack of 30m by 45m",
  )
}

///|
test "min-dependency-slack ignores a self dependency" {
  let source = "id=api;start=2026-10-01T22:00;end=2026-10-01T23:00;depends=api\n"
  assert_eq(
    policy_violations_of(source, policy_only_min_dependency_slack(60)).length(),
    0,
  )
}

///|
test "min-dependency-slack ignores a dependency that is not in the plan" {
  let source = "id=api;start=2026-10-01T22:00;end=2026-10-01T23:00;depends=ghost\n"
  assert_eq(
    policy_violations_of(source, policy_only_min_dependency_slack(60)).length(),
    0,
  )
}

///|
test "min-dependency-slack reports one entry per dependency in dependency order" {
  let source = "id=db;start=2026-10-01T20:00;end=2026-10-01T21:00\n" +
    "id=cache;start=2026-10-01T20:00;end=2026-10-01T21:20\n" +
    "id=api;start=2026-10-01T21:30;end=2026-10-01T22:00;depends=db,cache\n"
  let lines = policy_lines(source, policy_only_min_dependency_slack(45))
  assert_eq(lines.length(), 2)
  assert_eq(
    lines[0],
    "warning min-dependency-slack (api): only 30m of slack after db, the minimum is 45m",
  )
  assert_eq(
    lines[1],
    "warning min-dependency-slack (api): only 10m of slack after cache, the minimum is 45m",
  )
}

///|
test "high-risk-overlap fires once per pair that involves a high risk change" {
  let source = "id=a;start=2026-10-01T22:00;end=2026-10-01T23:00;risk=high\n" +
    "id=b;start=2026-10-01T22:30;end=2026-10-01T23:30;risk=low\n"
  let lines = policy_lines(source, policy_only_forbid_high_risk_overlap())
  assert_eq(lines.length(), 1)
  assert_eq(
    lines[0],
    "error high-risk-overlap (a): high risk a overlaps b for 30m",
  )
}

///|
test "high-risk-overlap names the high risk side of the pair" {
  let source = "id=a;start=2026-10-01T22:00;end=2026-10-01T23:00;risk=low\n" +
    "id=b;start=2026-10-01T22:30;end=2026-10-01T23:30;risk=high\n"
  let lines = policy_lines(source, policy_only_forbid_high_risk_overlap())
  assert_eq(lines.length(), 1)
  assert_eq(
    lines[0],
    "error high-risk-overlap (b): high risk b overlaps a for 30m",
  )
}

///|
test "high-risk-overlap reports each pair once even when one change has two neighbours" {
  let source = "id=a;start=2026-10-01T22:00;end=2026-10-01T23:00;risk=low\n" +
    "id=b;start=2026-10-01T22:30;end=2026-10-01T23:30;risk=low\n" +
    "id=c;start=2026-10-01T22:35;end=2026-10-01T22:50;risk=high\n"
  let lines = policy_lines(source, policy_only_forbid_high_risk_overlap())
  // c overlaps a and b, and the pair a/b carries no high risk change.
  assert_eq(lines.length(), 2)
  assert_eq(
    lines[0],
    "error high-risk-overlap (c): high risk c overlaps a for 15m",
  )
  assert_eq(
    lines[1],
    "error high-risk-overlap (c): high risk c overlaps b for 15m",
  )
}

///|
test "high-risk-overlap ignores a pair of ordinary changes" {
  let source = "id=a;start=2026-10-01T22:00;end=2026-10-01T23:00;risk=low\n" +
    "id=b;start=2026-10-01T22:30;end=2026-10-01T23:30;risk=medium\n"
  assert_eq(
    policy_violations_of(source, policy_only_forbid_high_risk_overlap()).length(),
    0,
  )
}

///|
test "high-risk-overlap is silent when the flag is off" {
  let source = "id=a;start=2026-10-01T22:00;end=2026-10-01T23:00;risk=high\n" +
    "id=b;start=2026-10-01T22:30;end=2026-10-01T23:30;risk=high\n"
  assert_eq(
    policy_violations_of(source, @moon-change-window-auditor.Policy::relaxed()).length(),
    0,
  )
}

///|
test "max-high-risk-per-day does not fire at the limit" {
  let source = "id=a;start=2026-10-01T08:00;end=2026-10-01T09:00;risk=high\n" +
    "id=b;start=2026-10-01T10:00;end=2026-10-01T11:00;risk=high\n"
  assert_eq(
    policy_violations_of(source, policy_only_max_high_risk_per_day(2)).length(),
    0,
  )
}

///|
test "max-high-risk-per-day groups two changes of the same day into one entry" {
  let source = "id=a;start=2026-10-01T08:00;end=2026-10-01T09:00;risk=high\n" +
    "id=b;start=2026-10-01T10:00;end=2026-10-01T11:00;risk=high\n"
  let lines = policy_lines(source, policy_only_max_high_risk_per_day(1))
  assert_eq(lines.length(), 1)
  assert_eq(
    lines[0],
    "error max-high-risk-per-day (2026-10-01T00:00): 2 high risk changes on this day, the limit is 1",
  )
}

///|
test "max-high-risk-per-day reports one entry per day in calendar order" {
  let source = "id=a;start=2026-10-02T08:00;end=2026-10-02T09:00;risk=high\n" +
    "id=b;start=2026-10-02T10:00;end=2026-10-02T11:00;risk=high\n" +
    "id=c;start=2026-10-01T08:00;end=2026-10-01T09:00;risk=high\n" +
    "id=d;start=2026-10-01T10:00;end=2026-10-01T11:00;risk=high\n"
  let lines = policy_lines(source, policy_only_max_high_risk_per_day(1))
  assert_eq(lines.length(), 2)
  assert_eq(
    lines[0],
    "error max-high-risk-per-day (2026-10-01T00:00): 2 high risk changes on this day, the limit is 1",
  )
  assert_eq(
    lines[1],
    "error max-high-risk-per-day (2026-10-02T00:00): 2 high risk changes on this day, the limit is 1",
  )
}

///|
test "max-high-risk-per-day sorts a change that crosses midnight to its start day" {
  let source = "id=a;start=2026-10-01T23:00;end=2026-10-02T01:00;risk=high\n" +
    "id=b;start=2026-10-01T20:00;end=2026-10-01T21:00;risk=high\n" +
    "id=c;start=2026-10-02T10:00;end=2026-10-02T11:00;risk=high\n"
  let lines = policy_lines(source, policy_only_max_high_risk_per_day(1))
  // Only the first of October reaches two high risk changes.
  assert_eq(lines.length(), 1)
  assert_eq(
    lines[0],
    "error max-high-risk-per-day (2026-10-01T00:00): 2 high risk changes on this day, the limit is 1",
  )
}

///|
test "max-high-risk-per-day counts only high risk changes" {
  let source = "id=a;start=2026-10-01T08:00;end=2026-10-01T09:00;risk=high\n" +
    "id=b;start=2026-10-01T10:00;end=2026-10-01T11:00;risk=medium\n" +
    "id=c;start=2026-10-01T12:00;end=2026-10-01T13:00;risk=low\n"
  assert_eq(
    policy_violations_of(source, policy_only_max_high_risk_per_day(1)).length(),
    0,
  )
}

///|
test "freeze-conflict fires once per change and freeze pair" {
  let source = "id=api;start=2026-10-01T22:00;end=2026-10-01T23:00\n" +
    "kind=freeze;id=blackout;start=2026-10-01T22:30;end=2026-10-01T23:30\n"
  let lines = policy_lines(source, policy_only_forbid_freeze_conflicts())
  assert_eq(lines.length(), 1)
  assert_eq(
    lines[0],
    "error freeze-conflict (api): runs inside freeze blackout for 30m",
  )
}

///|
test "freeze-conflict reports one entry per freeze a change runs inside" {
  let source = "id=api;start=2026-10-01T22:00;end=2026-10-02T00:00\n" +
    "kind=freeze;id=blackout;start=2026-10-01T22:30;end=2026-10-01T23:00\n" +
    "kind=freeze;id=holiday;start=2026-10-01T23:00;end=2026-10-01T23:30\n"
  let lines = policy_lines(source, policy_only_forbid_freeze_conflicts())
  assert_eq(lines.length(), 2)
  assert_eq(
    lines[0],
    "error freeze-conflict (api): runs inside freeze blackout for 30m",
  )
  assert_eq(
    lines[1],
    "error freeze-conflict (api): runs inside freeze holiday for 30m",
  )
}

///|
test "freeze-conflict does not fire when a change only touches a freeze" {
  let source = "id=api;start=2026-10-01T22:00;end=2026-10-01T23:00\n" +
    "kind=freeze;id=blackout;start=2026-10-01T23:00;end=2026-10-02T00:00\n"
  assert_eq(
    policy_violations_of(source, policy_only_forbid_freeze_conflicts()).length(),
    0,
  )
}

///|
test "service-missing fires for every unnamed change in plan order" {
  let source = "id=a;service=orders;start=2026-10-01T22:00;end=2026-10-01T23:00\n" +
    "id=b;start=2026-10-02T22:00;end=2026-10-02T23:00\n" +
    "id=c;start=2026-10-03T22:00;end=2026-10-03T23:00\n"
  let lines = policy_lines(source, policy_only_require_service())
  assert_eq(lines.length(), 2)
  assert_eq(
    lines[0],
    "warning service-missing (b): no service is named for this change",
  )
  assert_eq(
    lines[1],
    "warning service-missing (c): no service is named for this change",
  )
}

///|
test "service-missing does not fire when the requirement is off" {
  let unnamed = "id=a;start=2026-10-01T22:00;end=2026-10-01T23:00\n"
  assert_eq(
    policy_violations_of(unnamed, @moon-change-window-auditor.Policy::relaxed()).length(),
    0,
  )
  assert_eq(
    policy_violations_of(unnamed, policy_only_require_service()).length(),
    1,
  )
  let named = "id=a;service=orders;start=2026-10-01T22:00;end=2026-10-01T23:00\n"
  assert_eq(
    policy_violations_of(named, policy_only_require_service()).length(),
    0,
  )
}

///|
test "violations follow the fixed rule order" {
  let source = "id=db;service=orders;start=2026-10-01T22:00;end=2026-10-02T02:00;risk=high\n" +
    "id=api;start=2026-10-01T22:30;end=2026-10-02T03:00;risk=high;depends=db\n" +
    "kind=freeze;id=blackout;start=2026-10-01T23:00;end=2026-10-02T00:00\n"
  let policy = policy_rules(1, 60, 30, true, 1, true, true)
  let violations = policy_violations_of(source, policy)
  assert_eq(
    policy_codes(violations),
    "max-concurrent,max-change-minutes,max-change-minutes,min-dependency-slack," +
    "high-risk-overlap,max-high-risk-per-day,freeze-conflict,freeze-conflict," +
    "service-missing",
  )
}

///|
test "Policy::relaxed reports nothing on a plan full of problems" {
  let source = "id=db;start=2026-10-01T22:00;end=2026-10-02T04:00;risk=high\n" +
    "id=api;start=2026-10-01T22:30;end=2026-10-01T23:30;risk=high;depends=db,ghost\n" +
    "kind=freeze;id=blackout;start=2026-10-01T23:00;end=2026-10-02T01:00\n"
  let plan = plan_of(source)
  let audited = @moon-change-window-auditor.audit(plan)
  // The plan is genuinely broken; the relaxed policy still adds nothing.
  assert_true(audited.error_count() > 0)
  let judged = policy_report_of(
    source,
    @moon-change-window-auditor.Policy::relaxed(),
  )
  assert_eq(judged.violation_count(), 0)
  assert_eq(judged.error_count(), audited.error_count())
  assert_eq(judged.status(), "FAIL")
}

///|
test "PolicyViolation::to_line pins both severities" {
  let error : @moon-change-window-auditor.PolicyViolation = {
    code: "max-concurrent",
    severity: @moon-change-window-auditor.Severity::Error,
    subject: "all",
    detail: "3 simultaneous changes exceed the limit of 2",
  }
  assert_eq(
    error.to_line(),
    "error max-concurrent (all): 3 simultaneous changes exceed the limit of 2",
  )
  let warning : @moon-change-window-auditor.PolicyViolation = {
    code: "service-missing",
    severity: @moon-change-window-auditor.Severity::Warning,
    subject: "api",
    detail: "no service is named for this change",
  }
  assert_eq(
    warning.to_line(),
    "warning service-missing (api): no service is named for this change",
  )
}

///|
test "PolicyReport counts add policy findings to the audit findings" {
  let source = "id=api;start=2026-10-01T22:00;end=2026-10-01T23:00\n" +
    "id=web;start=2026-10-01T22:30;end=2026-10-01T23:30\n"
  let report = policy_report_of(source, policy_only_require_service())
  assert_eq(report.audit.overlaps.length(), 1)
  assert_eq(report.violation_count(), 2)
  assert_eq(report.error_count(), 1)
  assert_eq(report.warning_count(), 2)
  assert_true(report.has_errors())
  assert_eq(report.status(), "FAIL")
}

///|
test "PolicyReport stays PASS when audit and policy only warn" {
  let source = "id=db;service=orders;start=2026-10-01T20:00;end=2026-10-01T21:00\n" +
    "id=api;start=2026-10-01T21:00;end=2026-10-01T22:00;depends=db\n"
  let report = policy_report_of(source, policy_only_require_service())
  // The audit warns about the back to back dependency, the policy about the
  // unnamed service, and neither is an error.
  assert_eq(report.audit.error_count(), 0)
  assert_eq(report.audit.warning_count(), 1)
  assert_eq(report.violation_count(), 1)
  assert_eq(report.error_count(), 0)
  assert_eq(report.warning_count(), 2)
  assert_true(!report.has_errors())
  assert_eq(report.status(), "PASS")
}

///|
test "audit_with_policy keeps the underlying audit unchanged" {
  let source = "id=db;service=orders;start=2026-10-01T22:00;end=2026-10-02T02:00;risk=high\n" +
    "id=api;start=2026-10-01T22:30;end=2026-10-02T03:00;risk=high;depends=db\n" +
    "kind=freeze;id=blackout;start=2026-10-01T23:00;end=2026-10-02T00:00\n"
  let plan = plan_of(source)
  let plain = @moon-change-window-auditor.audit(plan)
  let judged = policy_report_of(
    source,
    @moon-change-window-auditor.Policy::strict(),
  )
  assert_true(judged.violation_count() > 0)
  assert_eq(
    @moon-change-window-auditor.render_report(judged.audit),
    @moon-change-window-auditor.render_report(plain),
  )
  assert_eq(judged.audit.error_count(), plain.error_count())
  assert_eq(judged.audit.warning_count(), plain.warning_count())
  assert_eq(judged.audit.blocked_minutes, plain.blocked_minutes)
  assert_eq(judged.audit.overlaps.length(), plain.overlaps.length())
  assert_eq(
    judged.audit.freeze_conflicts.length(),
    plain.freeze_conflicts.length(),
  )
  assert_eq(
    judged.audit.dependency_issues.length(),
    plain.dependency_issues.length(),
  )
  assert_eq(judged.audit.status(), plain.status())
  assert_eq(
    judged.policy.describe(),
    @moon-change-window-auditor.Policy::strict().describe(),
  )
}

///|
test "render_policy_report pins the whole text of a small report" {
  let source = "id=api;start=2026-10-01T22:00;end=2026-10-01T23:00\n"
  let text = @moon-change-window-auditor.render_policy_report(
    policy_report_of(source, policy_only_require_service()),
  )
  assert_eq(
    text,
    "Moon Change Window Policy Report\n" +
    "Moon Change Window Audit\n" +
    "windows: 1\n" +
    "freezes: 0\n" +
    "errors: 0\n" +
    "warnings: 0\n" +
    "overlaps: 0\n" +
    "freeze conflicts: 0\n" +
    "dependency issues: 0\n" +
    "blocked: 1h\n" +
    "status: PASS\n" +
    "\n" +
    "WINDOWS\n" +
    "  api | - | 2026-10-01T22:00 -> 2026-10-01T23:00 | 1h | medium | -\n" +
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
    "  (none)\n" +
    "\n" +
    "POLICY VIOLATIONS\n" +
    "  warning service-missing (api): no service is named for this change\n" +
    "policy: PASS\n",
  )
}

///|
test "render_policy_report marks an empty policy section and ends with one newline" {
  let source = "id=api;service=orders;start=2026-10-01T22:00;end=2026-10-01T23:00\n"
  let text = @moon-change-window-auditor.render_policy_report(
    policy_report_of(source, @moon-change-window-auditor.Policy::relaxed()),
  )
  assert_eq(policy_trailing_newlines(text), 1)
  assert_true(text.has_suffix("POLICY VIOLATIONS\n  (none)\npolicy: PASS\n"))
}

///|
test "render_violations joins lines without a trailing newline" {
  let empty : Array[@moon-change-window-auditor.PolicyViolation] = []
  assert_eq(@moon-change-window-auditor.render_violations(empty), "")
  let source = "id=a;service=orders;start=2026-10-01T22:00;end=2026-10-01T23:00\n" +
    "id=b;start=2026-10-01T22:00;end=2026-10-01T23:00\n"
  let lines = policy_lines(source, policy_only_require_service())
  assert_eq(lines.length(), 1)
  assert_eq(
    policy_violation_text(source, policy_only_require_service()),
    "warning service-missing (b): no service is named for this change",
  )
  let two = policy_violation_text(
    "id=a;start=2026-10-01T22:00;end=2026-10-01T23:00\n" +
    "id=b;start=2026-10-02T22:00;end=2026-10-02T23:00\n",
    policy_only_require_service(),
  )
  assert_eq(
    two,
    "warning service-missing (a): no service is named for this change\n" +
    "warning service-missing (b): no service is named for this change",
  )
}
