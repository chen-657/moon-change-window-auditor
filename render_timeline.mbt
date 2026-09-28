///|
/// ASCII timeline of one horizon: a Gantt style view that fits in a terminal or
/// a log.
///
/// Each record becomes one row of fixed width cells. A cell is judged at the
/// minute it starts, which keeps the rendering cheap and completely
/// reproducible: widening the horizon changes the resolution, never the
/// algorithm.

///|
/// Pad a string on the right with spaces up to `width` characters.
fn pad_right(text : String, width : Int) -> String {
  let builder = StringBuilder()
  builder.write_string(text)
  let mut padding = width - text.length()
  while padding > 0 {
    builder.write_char(' ')
    padding = padding - 1
  }
  builder.to_string()
}

///|
/// Widest record id of the plan, used as the label column width.
fn widest_id(plan : Plan) -> Int {
  let mut width = 0
  for window in plan.windows {
    if window.id.length() > width {
      width = window.id.length()
    }
  }
  width
}

///|
/// True when a change or a freeze covers the minute. `freeze` selects which of
/// the two collections is searched.
fn covers_minute(records : Array[Window], minute : Int) -> Bool {
  for record in records {
    if minute >= record.start && minute < record.end {
      return true
    }
  }
  false
}

///|
/// The cell of one column: `!` when a change and a freeze both cover it, `#`
/// for a change, `=` for a freeze and `.` for free time.
fn timeline_cell(
  changes : Array[Window],
  freezes : Array[Window],
  minute : Int,
) -> Char {
  let in_change = covers_minute(changes, minute)
  let in_freeze = covers_minute(freezes, minute)
  if in_change && in_freeze {
    '!'
  } else if in_change {
    '#'
  } else if in_freeze {
    '='
  } else {
    '.'
  }
}

///|
/// Render the timeline of `[from, to)` with `columns` cells per row.
///
/// `cell_minutes` is the ceiling of the horizon divided by the column count, so
/// the last cell may reach past `to`; the header prints the resolution so the
/// rounding is never a surprise. Records are ordered by start minute.
///
/// When the horizon is empty (`to <= from`) or `columns <= 0`, the result is
/// the single line `Timeline (empty horizon)` with one trailing newline.
pub fn render_timeline(
  plan : Plan,
  from : Int,
  to : Int,
  columns : Int,
) -> String {
  if to <= from || columns <= 0 {
    return "Timeline (empty horizon)\n"
  }
  let span = to - from
  let cell_minutes = if span % columns == 0 {
    span / columns
  } else {
    span / columns + 1
  }
  let builder = StringBuilder()
  builder.write_string(
    "Timeline " +
    format_instant(from) +
    " -> " +
    format_instant(to) +
    " (" +
    format_duration(span) +
    ", " +
    columns.to_string() +
    " columns, 1 column = " +
    cell_minutes.to_string() +
    "m)\n",
  )
  let changes = plan.changes()
  let freezes = plan.freezes()
  let width = widest_id(plan)
  for window in sort_windows_by_start(plan.windows) {
    builder.write_string(pad_right(window.id, width))
    builder.write_string(" |")
    for column = 0; column < columns; column = column + 1 {
      builder.write_char(
        timeline_cell(changes, freezes, from + column * cell_minutes),
      )
    }
    builder.write_string("|\n")
  }
  builder.write_string(
    "legend: . free, # change, = freeze, ! change inside freeze\n",
  )
  builder.to_string()
}
