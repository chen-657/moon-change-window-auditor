///|
/// Compare two plans and report what changed.
///
/// A plan revision is reviewed by a human, so the diff is written the way a
/// reviewer reads it: what was added, what was removed, which record changed in
/// which field, and which conflicts the new revision introduces or clears.
///
/// Records are matched by id. Two records with the same id but different
/// content count as one modification, not as a removal plus an addition.

///|
/// What happened to one record between two revisions.
pub(all) enum ChangeKind {
  Added
  Removed
  Modified
} derive(Eq)

///|
pub extend ChangeKind with Eq::{equal}

///|
pub extend ChangeKind with Eq::{not_equal}

///|
/// Lower case label: `added`, `removed` or `modified`.
pub fn ChangeKind::label(self : ChangeKind) -> String {
  match self {
    ChangeKind::Added => "added"
    ChangeKind::Removed => "removed"
    ChangeKind::Modified => "modified"
  }
}

///|
/// One record level difference.
pub(all) struct WindowChange {
  id : String
  kind : ChangeKind
  detail : String
}

///|
/// Render as `added api (2026-10-01T22:00 -> 2026-10-01T23:00)` or as
/// `modified api (start 2026-10-01T22:00 -> 2026-10-01T22:15, risk low -> high)`.
pub fn WindowChange::to_line(self : WindowChange) -> String {
  self.kind.label() + " " + self.id + " (" + self.detail + ")"
}

///|
/// The differences between two revisions of a plan.
///
/// `new_overlaps` and `new_freeze_conflicts` carry the pairs the new revision
/// introduces; `resolved_overlaps` and `resolved_freeze_conflicts` count the
/// pairs the old revision had and the new one does not. A pair that overlaps in
/// both revisions is reported by neither, because revision review is about
/// change, not about the state of the world.
pub(all) struct PlanDiff {
  changes : Array[WindowChange]
  added_windows : Int
  removed_windows : Int
  modified_windows : Int
  new_overlaps : Array[Overlap]
  resolved_overlaps : Int
  new_freeze_conflicts : Array[FreezeConflict]
  resolved_freeze_conflicts : Int
}

///|
/// True when the two revisions are identical: no record changed and no conflict
/// appeared or disappeared.
pub fn PlanDiff::is_empty(self : PlanDiff) -> Bool {
  self.changes.length() == 0 &&
  self.new_overlaps.length() == 0 &&
  self.new_freeze_conflicts.length() == 0 &&
  self.resolved_overlaps == 0 &&
  self.resolved_freeze_conflicts == 0
}

///|
/// `depends` rendered as `a+b`, or `-` when the list is empty.
fn depends_text(depends : Array[String]) -> String {
  if depends.length() == 0 {
    "-"
  } else {
    join(depends, "+")
  }
}

///|
/// `service` rendered as `-` when it is empty.
fn service_text(service : String) -> String {
  if service == "" {
    "-"
  } else {
    service
  }
}

///|
/// Compare one field of two records and append a `<field> <old> -> <new>` note
/// when they differ. `parts` collects the notes in the order the fields are
/// visited, which is what makes the detail text stable.
fn note_change(
  parts : Array[String],
  field : String,
  before : String,
  after : String,
) -> Unit {
  if before != after {
    parts.push(field + " " + before + " -> " + after)
  }
}

///|
/// Every field of a record that differs from its earlier revision, in the fixed
/// order service, start, end, risk, depends, kind.
fn modification_detail(before : Window, after : Window) -> String {
  let parts : Array[String] = []
  note_change(
    parts,
    "service",
    service_text(before.service),
    service_text(after.service),
  )
  note_change(
    parts,
    "start",
    format_instant(before.start),
    format_instant(after.start),
  )
  note_change(
    parts,
    "end",
    format_instant(before.end),
    format_instant(after.end),
  )
  note_change(parts, "risk", before.risk.label(), after.risk.label())
  note_change(
    parts,
    "depends",
    depends_text(before.depends),
    depends_text(after.depends),
  )
  note_change(parts, "kind", before.kind.label(), after.kind.label())
  if parts.length() == 0 {
    "no field changed"
  } else {
    join(parts, ", ")
  }
}

///|
/// True when two overlap pairs name the same two records, in any order.
fn same_overlap_pair(
  overlap : Overlap,
  first : String,
  second : String,
) -> Bool {
  (overlap.first == first && overlap.second == second) ||
  (overlap.first == second && overlap.second == first)
}

///|
/// True when the pair is already an overlap of the other report.
fn overlap_known(
  overlaps : Array[Overlap],
  first : String,
  second : String,
) -> Bool {
  for overlap in overlaps {
    if same_overlap_pair(overlap, first, second) {
      return true
    }
  }
  false
}

///|
/// Freeze conflicts of the new revision that the old one did not have.
fn new_freeze_conflicts(
  before : Array[FreezeConflict],
  after : Array[FreezeConflict],
) -> Array[FreezeConflict] {
  let fresh : Array[FreezeConflict] = []
  for conflict in after {
    let mut known = false
    for previous in before {
      if previous.window_id == conflict.window_id &&
        previous.freeze_id == conflict.freeze_id {
        known = true
      }
    }
    if !known {
      fresh.push(conflict)
    }
  }
  fresh
}

///|
/// Number of freeze conflicts the old revision had and the new one does not.
fn resolved_freeze_conflicts(
  before : Array[FreezeConflict],
  after : Array[FreezeConflict],
) -> Int {
  let mut resolved = 0
  for conflict in before {
    let mut known = false
    for current in after {
      if current.window_id == conflict.window_id &&
        current.freeze_id == conflict.freeze_id {
        known = true
      }
    }
    if !known {
      resolved = resolved + 1
    }
  }
  resolved
}

///|
/// Compare two revisions of a plan.
///
/// The records are matched by id, so a record present in both plans with any
/// different field is one modification. Removals come first, then additions,
/// then modifications, each in the order of the plan they come from.
pub fn diff_plans(before : Plan, after : Plan) -> PlanDiff {
  let changes : Array[WindowChange] = []
  let mut removed = 0
  for window in before.windows {
    match after.find(window.id) {
      Some(_) => ()
      None => {
        removed = removed + 1
        changes.push({
          id: window.id,
          kind: ChangeKind::Removed,
          detail: format_instant(window.start) +
          " -> " +
          format_instant(window.end),
        })
      }
    }
  }
  let mut added = 0
  for window in after.windows {
    match before.find(window.id) {
      Some(_) => ()
      None => {
        added = added + 1
        changes.push({
          id: window.id,
          kind: ChangeKind::Added,
          detail: format_instant(window.start) +
          " -> " +
          format_instant(window.end),
        })
      }
    }
  }
  let mut modified = 0
  for window in after.windows {
    match before.find(window.id) {
      None => ()
      Some(previous) => {
        let detail = modification_detail(previous, window)
        if detail != "no field changed" {
          modified = modified + 1
          changes.push({ id: window.id, kind: ChangeKind::Modified, detail, })
        }
      }
    }
  }
  let before_report = audit(before)
  let after_report = audit(after)
  let fresh_overlaps : Array[Overlap] = []
  for overlap in after_report.overlaps {
    if !overlap_known(before_report.overlaps, overlap.first, overlap.second) {
      fresh_overlaps.push(overlap)
    }
  }
  let mut resolved_overlaps = 0
  for overlap in before_report.overlaps {
    if !overlap_known(after_report.overlaps, overlap.first, overlap.second) {
      resolved_overlaps = resolved_overlaps + 1
    }
  }
  {
    changes,
    added_windows: added,
    removed_windows: removed,
    modified_windows: modified,
    new_overlaps: fresh_overlaps,
    resolved_overlaps,
    new_freeze_conflicts: new_freeze_conflicts(
      before_report.freeze_conflicts,
      after_report.freeze_conflicts,
    ),
    resolved_freeze_conflicts: resolved_freeze_conflicts(
      before_report.freeze_conflicts,
      after_report.freeze_conflicts,
    ),
  }
}

///|
/// Render a diff as a stable text block.
///
/// The text ends with exactly one newline.
pub fn render_diff(diff : PlanDiff) -> String {
  let builder = StringBuilder()
  builder.write_string("Plan diff\n")
  builder.write_string(
    "added: " +
    diff.added_windows.to_string() +
    "  removed: " +
    diff.removed_windows.to_string() +
    "  modified: " +
    diff.modified_windows.to_string() +
    "\n",
  )
  builder.write_string(
    "new overlaps: " +
    diff.new_overlaps.length().to_string() +
    "  resolved overlaps: " +
    diff.resolved_overlaps.to_string() +
    "\n",
  )
  builder.write_string(
    "new freeze conflicts: " +
    diff.new_freeze_conflicts.length().to_string() +
    "  resolved freeze conflicts: " +
    diff.resolved_freeze_conflicts.to_string() +
    "\n",
  )
  builder.write_string("\nCHANGES\n")
  if diff.changes.length() == 0 {
    builder.write_string("  (none)\n")
  } else {
    for change in diff.changes {
      builder.write_string("  ")
      builder.write_string(change.to_line())
      builder.write_char('\n')
    }
  }
  builder.write_string("\nNEW OVERLAPS\n")
  if diff.new_overlaps.length() == 0 {
    builder.write_string("  (none)\n")
  } else {
    for overlap in diff.new_overlaps {
      builder.write_string("  ")
      builder.write_string(overlap.to_line())
      builder.write_char('\n')
    }
  }
  builder.write_string("\nNEW FREEZE CONFLICTS\n")
  if diff.new_freeze_conflicts.length() == 0 {
    builder.write_string("  (none)\n")
  } else {
    for conflict in diff.new_freeze_conflicts {
      builder.write_string("  ")
      builder.write_string(conflict.to_line())
      builder.write_char('\n')
    }
  }
  builder.to_string()
}
