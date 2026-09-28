///|
/// Tests for `diff_plans`, `render_diff` and the record level changes a diff
/// reports between two revisions of a plan.

///|
/// The single record change of a two revision diff. Fails when the diff reports
/// anything other than exactly one record change.
fn diff_only_change(
  before : String,
  after : String,
) -> @moon-change-window-auditor.WindowChange raise {
  let result = @moon-change-window-auditor.diff_plans(
    plan_of(before),
    plan_of(after),
  )
  if result.changes.length() != 1 {
    fail(
      "expected exactly one record change, got " +
      result.changes.length().to_string(),
    )
  }
  result.changes[0]
}

///|
test "identical plans produce an empty diff" {
  let plan = plan_of(
    "id=a;service=db;start=2026-10-01T22:00;end=2026-10-01T23:00;risk=high\n" +
    "id=b;service=api;start=2026-10-01T23:00;end=2026-10-02T00:00;risk=low\n",
  )
  let result = @moon-change-window-auditor.diff_plans(plan, plan)
  assert_true(result.is_empty())
  assert_eq(result.changes.length(), 0)
  assert_eq(result.added_windows, 0)
  assert_eq(result.removed_windows, 0)
  assert_eq(result.modified_windows, 0)
  assert_eq(result.new_overlaps.length(), 0)
  assert_eq(result.resolved_overlaps, 0)
  assert_eq(result.new_freeze_conflicts.length(), 0)
  assert_eq(result.resolved_freeze_conflicts, 0)
}

///|
test "an overlap present in both revisions is not a change" {
  let plan = plan_of(
    "id=a;start=2026-10-01T22:00;end=2026-10-01T23:00\n" +
    "id=b;start=2026-10-01T22:30;end=2026-10-01T23:30\n",
  )
  let result = @moon-change-window-auditor.diff_plans(plan, plan)
  assert_eq(result.new_overlaps.length(), 0)
  assert_eq(result.resolved_overlaps, 0)
  assert_true(result.is_empty())
}

///|
test "a freeze conflict present in both revisions is not a change" {
  let plan = plan_of(
    "id=api;start=2026-10-01T22:00;end=2026-10-01T23:00\n" +
    "id=blackout;kind=freeze;start=2026-10-01T22:30;end=2026-10-01T23:30\n",
  )
  let result = @moon-change-window-auditor.diff_plans(plan, plan)
  assert_eq(result.new_freeze_conflicts.length(), 0)
  assert_eq(result.resolved_freeze_conflicts, 0)
  assert_true(result.is_empty())
}

///|
test "render_diff of identical plans pins the empty text" {
  let plan = plan_of(
    "id=a;service=db;start=2026-10-01T22:00;end=2026-10-01T23:00;risk=high\n",
  )
  let expected = "Plan diff\n" +
    "added: 0  removed: 0  modified: 0\n" +
    "new overlaps: 0  resolved overlaps: 0\n" +
    "new freeze conflicts: 0  resolved freeze conflicts: 0\n" +
    "\n" +
    "CHANGES\n" +
    "  (none)\n" +
    "\n" +
    "NEW OVERLAPS\n" +
    "  (none)\n" +
    "\n" +
    "NEW FREEZE CONFLICTS\n" +
    "  (none)\n"
  assert_eq(
    @moon-change-window-auditor.render_diff(
      @moon-change-window-auditor.diff_plans(plan, plan),
    ),
    expected,
  )
}

///|
test "render_diff ends with exactly one newline" {
  let plan = plan_of("id=a;start=2026-10-01T22:00;end=2026-10-01T23:00\n")
  let text = @moon-change-window-auditor.render_diff(
    @moon-change-window-auditor.diff_plans(plan, plan),
  )
  assert_true(text.has_suffix("\n"))
  assert_true(!text.has_suffix("\n\n"))
  assert_true(text.has_suffix("  (none)\n"))
}

///|
test "ChangeKind::label names each kind" {
  assert_eq(@moon-change-window-auditor.ChangeKind::Added.label(), "added")
  assert_eq(@moon-change-window-auditor.ChangeKind::Removed.label(), "removed")
  assert_eq(
    @moon-change-window-auditor.ChangeKind::Modified.label(),
    "modified",
  )
}

///|
test "an added record reports its own window text" {
  let result = @moon-change-window-auditor.diff_plans(
    plan_of("id=api;start=2026-10-01T22:00;end=2026-10-01T23:00\n"),
    plan_of(
      "id=api;start=2026-10-01T22:00;end=2026-10-01T23:00\n" +
      "id=batch;service=jobs;start=2026-10-02T01:00;end=2026-10-02T02:30\n",
    ),
  )
  assert_eq(result.added_windows, 1)
  assert_eq(result.removed_windows, 0)
  assert_eq(result.modified_windows, 0)
  assert_eq(result.changes.length(), 1)
  assert_eq(result.changes[0].id, "batch")
  assert_eq(result.changes[0].kind.label(), "added")
  assert_eq(result.changes[0].detail, "2026-10-02T01:00 -> 2026-10-02T02:30")
  assert_eq(
    result.changes[0].to_line(),
    "added batch (2026-10-02T01:00 -> 2026-10-02T02:30)",
  )
  assert_true(!result.is_empty())
}

///|
test "a removed record reports the window it had" {
  let result = @moon-change-window-auditor.diff_plans(
    plan_of(
      "id=api;start=2026-10-01T22:00;end=2026-10-01T23:00\n" +
      "id=batch;start=2026-10-02T01:00;end=2026-10-02T02:30\n",
    ),
    plan_of("id=api;start=2026-10-01T22:00;end=2026-10-01T23:00\n"),
  )
  assert_eq(result.removed_windows, 1)
  assert_eq(result.added_windows, 0)
  assert_eq(result.changes.length(), 1)
  assert_eq(result.changes[0].id, "batch")
  assert_eq(result.changes[0].kind.label(), "removed")
  assert_eq(result.changes[0].detail, "2026-10-02T01:00 -> 2026-10-02T02:30")
  assert_eq(
    result.changes[0].to_line(),
    "removed batch (2026-10-02T01:00 -> 2026-10-02T02:30)",
  )
}

///|
test "a removed freeze counts as a removed record" {
  let result = @moon-change-window-auditor.diff_plans(
    plan_of(
      "id=api;start=2026-10-01T22:00;end=2026-10-01T23:00\n" +
      "id=blackout;kind=freeze;start=2026-12-24T00:00;end=2026-12-25T00:00\n",
    ),
    plan_of("id=api;start=2026-10-01T22:00;end=2026-10-01T23:00\n"),
  )
  assert_eq(result.removed_windows, 1)
  assert_eq(result.changes.length(), 1)
  assert_eq(result.changes[0].id, "blackout")
  assert_eq(result.changes[0].kind.label(), "removed")
  assert_eq(
    result.changes[0].to_line(),
    "removed blackout (2026-12-24T00:00 -> 2026-12-25T00:00)",
  )
}

///|
test "a changed service is one modification" {
  let added_service = diff_only_change(
    "id=api;start=2026-10-01T22:00;end=2026-10-01T23:00\n", "id=api;service=db;start=2026-10-01T22:00;end=2026-10-01T23:00\n",
  )
  assert_eq(added_service.kind.label(), "modified")
  assert_eq(added_service.detail, "service - -> db")
  assert_eq(added_service.to_line(), "modified api (service - -> db)")
  let cleared_service = diff_only_change(
    "id=api;service=db;start=2026-10-01T22:00;end=2026-10-01T23:00\n", "id=api;start=2026-10-01T22:00;end=2026-10-01T23:00\n",
  )
  assert_eq(cleared_service.detail, "service db -> -")
}

///|
test "a changed start is one modification" {
  let change = diff_only_change(
    "id=api;start=2026-10-01T22:00;end=2026-10-01T23:00\n", "id=api;start=2026-10-01T22:15;end=2026-10-01T23:00\n",
  )
  assert_eq(change.kind.label(), "modified")
  assert_eq(change.detail, "start 2026-10-01T22:00 -> 2026-10-01T22:15")
  assert_eq(
    change.to_line(),
    "modified api (start 2026-10-01T22:00 -> 2026-10-01T22:15)",
  )
}

///|
test "a changed end is one modification" {
  let change = diff_only_change(
    "id=api;start=2026-10-01T22:00;end=2026-10-01T23:00\n", "id=api;start=2026-10-01T22:00;end=2026-10-01T23:30\n",
  )
  assert_eq(change.kind.label(), "modified")
  assert_eq(change.detail, "end 2026-10-01T23:00 -> 2026-10-01T23:30")
}

///|
test "a changed risk is one modification" {
  // The record without a risk field carries the default, medium.
  let change = diff_only_change(
    "id=api;start=2026-10-01T22:00;end=2026-10-01T23:00\n", "id=api;start=2026-10-01T22:00;end=2026-10-01T23:00;risk=high\n",
  )
  assert_eq(change.kind.label(), "modified")
  assert_eq(change.detail, "risk medium -> high")
}

///|
test "a changed depends list renders with + and -" {
  let added = diff_only_change(
    "id=api;start=2026-10-01T22:00;end=2026-10-01T23:00\n", "id=api;start=2026-10-01T22:00;end=2026-10-01T23:00;depends=database\n",
  )
  assert_eq(added.kind.label(), "modified")
  assert_eq(added.detail, "depends - -> database")
  let cleared = diff_only_change(
    "id=api;start=2026-10-01T22:00;end=2026-10-01T23:00;depends=database\n", "id=api;start=2026-10-01T22:00;end=2026-10-01T23:00\n",
  )
  assert_eq(cleared.detail, "depends database -> -")
}

///|
test "a reordered depends list is a modification" {
  let result = @moon-change-window-auditor.diff_plans(
    plan_of(
      "id=api;start=2026-10-01T22:00;end=2026-10-01T23:00;depends=alpha,beta\n",
    ),
    plan_of(
      "id=api;start=2026-10-01T22:00;end=2026-10-01T23:00;depends=beta,alpha\n",
    ),
  )
  assert_eq(result.added_windows, 0)
  assert_eq(result.removed_windows, 0)
  assert_eq(result.modified_windows, 1)
  assert_eq(result.changes.length(), 1)
  assert_eq(result.changes[0].detail, "depends alpha+beta -> beta+alpha")
}

///|
test "a changed kind is one modification" {
  let change = diff_only_change(
    "id=blackout;start=2026-12-24T00:00;end=2026-12-25T00:00\n", "id=blackout;kind=freeze;start=2026-12-24T00:00;end=2026-12-25T00:00\n",
  )
  assert_eq(change.kind.label(), "modified")
  assert_eq(change.detail, "kind change -> freeze")
}

///|
test "several changed fields are listed in the fixed order" {
  let change = diff_only_change(
    "id=api;start=2026-10-01T22:00;end=2026-10-01T23:00;risk=low;depends=alpha\n",
    "id=api;service=db;start=2026-10-01T22:15;end=2026-10-01T23:30;risk=high;kind=freeze\n",
  )
  assert_eq(change.kind.label(), "modified")
  assert_eq(
    change.detail,
    "service - -> db, start 2026-10-01T22:00 -> 2026-10-01T22:15, " +
    "end 2026-10-01T23:00 -> 2026-10-01T23:30, risk low -> high, " +
    "depends alpha -> -, kind change -> freeze",
  )
}

///|
test "records are matched by id, never as a removal plus an addition" {
  let result = @moon-change-window-auditor.diff_plans(
    plan_of(
      "id=api;service=db;start=2026-10-01T22:00;end=2026-10-01T23:00;risk=low\n",
    ),
    plan_of(
      "id=api;service=search;start=2026-10-01T22:30;end=2026-10-01T23:30;risk=high\n",
    ),
  )
  assert_eq(result.added_windows, 0)
  assert_eq(result.removed_windows, 0)
  assert_eq(result.modified_windows, 1)
  assert_eq(result.changes.length(), 1)
  assert_eq(result.changes[0].id, "api")
  assert_eq(result.changes[0].kind.label(), "modified")
  assert_eq(
    result.changes[0].detail,
    "service db -> search, start 2026-10-01T22:00 -> 2026-10-01T22:30, " +
    "end 2026-10-01T23:00 -> 2026-10-01T23:30, risk low -> high",
  )
}

///|
test "record changes are ordered removals, additions, modifications" {
  let result = @moon-change-window-auditor.diff_plans(
    plan_of(
      "id=gone1;start=2026-10-01T22:00;end=2026-10-01T23:00\n" +
      "id=stay;service=db;start=2026-10-02T22:00;end=2026-10-02T23:00;risk=low\n" +
      "id=gone2;start=2026-10-03T22:00;end=2026-10-03T23:00\n",
    ),
    plan_of(
      "id=fresh1;start=2026-10-04T22:00;end=2026-10-04T23:00\n" +
      "id=stay;service=db;start=2026-10-02T22:00;end=2026-10-02T23:00;risk=high\n" +
      "id=fresh2;start=2026-10-05T22:00;end=2026-10-05T23:00\n",
    ),
  )
  assert_eq(result.removed_windows, 2)
  assert_eq(result.added_windows, 2)
  assert_eq(result.modified_windows, 1)
  assert_eq(result.changes.length(), 5)
  assert_eq(result.changes[0].id, "gone1")
  assert_eq(result.changes[0].kind.label(), "removed")
  assert_eq(result.changes[1].id, "gone2")
  assert_eq(result.changes[1].kind.label(), "removed")
  assert_eq(result.changes[2].id, "fresh1")
  assert_eq(result.changes[2].kind.label(), "added")
  assert_eq(result.changes[3].id, "fresh2")
  assert_eq(result.changes[3].kind.label(), "added")
  assert_eq(result.changes[4].id, "stay")
  assert_eq(result.changes[4].kind.label(), "modified")
  assert_eq(result.changes[4].detail, "risk low -> high")
}

///|
test "an overlap the new revision introduces is a new overlap" {
  let result = @moon-change-window-auditor.diff_plans(
    plan_of(
      "id=a;service=db;start=2026-10-01T22:00;end=2026-10-01T23:00;risk=high\n" +
      "id=b;service=api;start=2026-10-01T23:00;end=2026-10-02T00:00;risk=low\n",
    ),
    plan_of(
      "id=a;service=db;start=2026-10-01T22:00;end=2026-10-01T23:00;risk=high\n" +
      "id=b;service=api;start=2026-10-01T22:30;end=2026-10-01T23:30;risk=low\n",
    ),
  )
  assert_eq(result.new_overlaps.length(), 1)
  assert_eq(result.resolved_overlaps, 0)
  assert_eq(result.new_overlaps[0].first, "a")
  assert_eq(result.new_overlaps[0].second, "b")
  assert_eq(result.new_overlaps[0].minutes, 30)
  assert_eq(result.new_overlaps[0].impact.label(), "major")
  assert_eq(result.new_overlaps[0].to_line(), "a vs b: 30m (major)")
  assert_eq(result.modified_windows, 1)
}

///|
test "an overlap the new revision clears is a resolved overlap" {
  let result = @moon-change-window-auditor.diff_plans(
    plan_of(
      "id=a;service=db;start=2026-10-01T22:00;end=2026-10-01T23:00;risk=high\n" +
      "id=b;service=api;start=2026-10-01T22:30;end=2026-10-01T23:30;risk=low\n",
    ),
    plan_of(
      "id=a;service=db;start=2026-10-01T22:00;end=2026-10-01T23:00;risk=high\n" +
      "id=b;service=api;start=2026-10-01T23:00;end=2026-10-02T00:00;risk=low\n",
    ),
  )
  assert_eq(result.new_overlaps.length(), 0)
  assert_eq(result.resolved_overlaps, 1)
  assert_eq(result.modified_windows, 1)
}

///|
test "an overlap that stays across revisions is neither new nor resolved" {
  let result = @moon-change-window-auditor.diff_plans(
    plan_of(
      "id=a;start=2026-10-01T22:00;end=2026-10-01T23:00\n" +
      "id=b;start=2026-10-01T22:30;end=2026-10-01T23:30\n",
    ),
    plan_of(
      "id=a;start=2026-10-01T22:15;end=2026-10-01T23:15\n" +
      "id=b;start=2026-10-01T22:30;end=2026-10-01T23:30\n",
    ),
  )
  // The pair still overlaps, only the shared minutes changed.
  assert_eq(result.new_overlaps.length(), 0)
  assert_eq(result.resolved_overlaps, 0)
  assert_eq(result.modified_windows, 1)
  assert_true(!result.is_empty())
}

///|
test "a freeze conflict the new revision introduces is reported" {
  let result = @moon-change-window-auditor.diff_plans(
    plan_of("id=api;start=2026-10-01T22:00;end=2026-10-01T23:00\n"),
    plan_of(
      "id=api;start=2026-10-01T22:00;end=2026-10-01T23:00\n" +
      "id=blackout;kind=freeze;start=2026-10-01T22:30;end=2026-10-01T23:30\n",
    ),
  )
  assert_eq(result.added_windows, 1)
  assert_eq(result.new_freeze_conflicts.length(), 1)
  assert_eq(result.new_freeze_conflicts[0].window_id, "api")
  assert_eq(result.new_freeze_conflicts[0].freeze_id, "blackout")
  assert_eq(result.new_freeze_conflicts[0].minutes, 30)
  assert_eq(
    result.new_freeze_conflicts[0].to_line(),
    "api runs inside blackout: 30m",
  )
  assert_eq(result.resolved_freeze_conflicts, 0)
  assert_true(!result.is_empty())
}

///|
test "a freeze conflict the new revision clears is resolved" {
  let result = @moon-change-window-auditor.diff_plans(
    plan_of(
      "id=api;start=2026-10-01T22:00;end=2026-10-01T23:00\n" +
      "id=blackout;kind=freeze;start=2026-10-01T22:30;end=2026-10-01T23:30\n",
    ),
    plan_of(
      "id=api;start=2026-10-01T23:30;end=2026-10-02T00:30\n" +
      "id=blackout;kind=freeze;start=2026-10-01T22:30;end=2026-10-01T23:30\n",
    ),
  )
  assert_eq(result.new_freeze_conflicts.length(), 0)
  assert_eq(result.resolved_freeze_conflicts, 1)
  assert_eq(result.modified_windows, 1)
}

///|
test "a freeze conflict that stays across revisions counts as neither" {
  let result = @moon-change-window-auditor.diff_plans(
    plan_of(
      "id=api;start=2026-10-01T22:00;end=2026-10-01T23:00\n" +
      "id=blackout;kind=freeze;start=2026-10-01T22:30;end=2026-10-01T23:30\n",
    ),
    plan_of(
      "id=api;start=2026-10-01T22:15;end=2026-10-01T23:15\n" +
      "id=blackout;kind=freeze;start=2026-10-01T22:30;end=2026-10-01T23:30\n",
    ),
  )
  assert_eq(result.new_freeze_conflicts.length(), 0)
  assert_eq(result.resolved_freeze_conflicts, 0)
  assert_eq(result.modified_windows, 1)
  assert_true(!result.is_empty())
}

///|
test "is_empty is false when only a conflict appeared" {
  let conflict = @moon-change-window-auditor.diff_plans(
    plan_of(
      "id=api;start=2026-10-01T22:00;end=2026-10-01T23:00\n" +
      "id=blackout;kind=freeze;start=2026-10-01T20:00;end=2026-10-01T21:00\n",
    ),
    plan_of(
      "id=api;start=2026-10-01T22:00;end=2026-10-01T23:00\n" +
      "id=blackout;kind=freeze;start=2026-10-01T22:30;end=2026-10-01T23:30\n",
    ),
  )
  assert_eq(conflict.new_freeze_conflicts.length(), 1)
  assert_true(!conflict.is_empty())
  // A diff carrying only a conflict is not empty either.
  let only_conflict : @moon-change-window-auditor.PlanDiff = {
    changes: [],
    added_windows: 0,
    removed_windows: 0,
    modified_windows: 0,
    new_overlaps: [],
    resolved_overlaps: 0,
    new_freeze_conflicts: [
      { window_id: "api", freeze_id: "blackout", minutes: 30, },
    ],
    resolved_freeze_conflicts: 0,
  }
  assert_true(!only_conflict.is_empty())
  // A diff carrying only a resolved overlap is not empty either.
  let only_resolved : @moon-change-window-auditor.PlanDiff = {
    changes: [],
    added_windows: 0,
    removed_windows: 0,
    modified_windows: 0,
    new_overlaps: [],
    resolved_overlaps: 1,
    new_freeze_conflicts: [],
    resolved_freeze_conflicts: 0,
  }
  assert_true(!only_resolved.is_empty())
}

///|
test "is_empty is false when only a record was removed" {
  let result = @moon-change-window-auditor.diff_plans(
    plan_of("id=a;start=2026-10-01T22:00;end=2026-10-01T23:00\n"),
    plan_of(""),
  )
  assert_eq(result.removed_windows, 1)
  assert_eq(result.changes.length(), 1)
  assert_true(!result.is_empty())
}

///|
test "render_diff pins the whole text of a small revision pair" {
  let result = @moon-change-window-auditor.diff_plans(
    plan_of(
      "id=a;service=db;start=2026-10-01T22:00;end=2026-10-01T23:00;risk=high\n",
    ),
    plan_of(
      "id=a;service=db;start=2026-10-01T22:00;end=2026-10-01T23:00;risk=high\n" +
      "id=b;service=api;start=2026-10-01T22:30;end=2026-10-01T23:30;risk=low\n" +
      "id=blackout;kind=freeze;start=2026-10-01T23:00;end=2026-10-02T00:00\n",
    ),
  )
  let expected = "Plan diff\n" +
    "added: 2  removed: 0  modified: 0\n" +
    "new overlaps: 1  resolved overlaps: 0\n" +
    "new freeze conflicts: 1  resolved freeze conflicts: 0\n" +
    "\n" +
    "CHANGES\n" +
    "  added b (2026-10-01T22:30 -> 2026-10-01T23:30)\n" +
    "  added blackout (2026-10-01T23:00 -> 2026-10-02T00:00)\n" +
    "\n" +
    "NEW OVERLAPS\n" +
    "  a vs b: 30m (major)\n" +
    "\n" +
    "NEW FREEZE CONFLICTS\n" +
    "  b runs inside blackout: 30m\n"
  assert_eq(@moon-change-window-auditor.render_diff(result), expected)
}
