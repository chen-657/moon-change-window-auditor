///|
/// Tests for the ASCII timeline renderer.

///|
/// A horizon helper: the same instant text both as minutes and as arguments.
fn timeline_horizon(from : String, to : String, columns : Int) -> String raise {
  @moon-change-window-auditor.render_timeline(
    plan_of(""),
    instant_of(from),
    instant_of(to),
    columns,
  )
}

///|
test "render_timeline pins the whole diagram of two changes" {
  let plan = plan_of(
    "id=aa;start=2026-10-01T22:00;end=2026-10-01T23:00\n" +
    "id=b;start=2026-10-01T23:00;end=2026-10-02T00:00\n",
  )
  let expected = "Timeline 2026-10-01T22:00 -> 2026-10-02T00:00 (2h, 4 columns, 1 column = 30m)\n" +
    "aa |##..|\n" +
    "b  |..##|\n" +
    "legend: . free, # change, = freeze, ! change inside freeze\n"
  assert_eq(
    @moon-change-window-auditor.render_timeline(
      plan,
      instant_of("2026-10-01T22:00"),
      instant_of("2026-10-02T00:00"),
      4,
    ),
    expected,
  )
}

///|
test "each row shows only its own record" {
  let plan = plan_of(
    "id=first;start=2026-10-01T22:00;end=2026-10-01T22:30\n" +
    "id=second;start=2026-10-01T23:00;end=2026-10-01T23:30\n",
  )
  let output = @moon-change-window-auditor.render_timeline(
    plan,
    instant_of("2026-10-01T22:00"),
    instant_of("2026-10-02T00:00"),
    4,
  )
  assert_true(output.contains("first  |#...|\n"))
  assert_true(output.contains("second |..#.|\n"))
}

///|
test "a change inside a freeze renders as an exclamation mark" {
  let plan = plan_of(
    "id=api;start=2026-10-01T22:00;end=2026-10-01T23:00\n" +
    "id=blackout;kind=freeze;start=2026-10-01T22:30;end=2026-10-01T23:30\n",
  )
  let expected = "Timeline 2026-10-01T22:00 -> 2026-10-01T23:00 (1h, 4 columns, 1 column = 15m)\n" +
    "api      |##!!|\n" +
    "blackout |..!!|\n" +
    "legend: . free, # change, = freeze, ! change inside freeze\n"
  assert_eq(
    @moon-change-window-auditor.render_timeline(
      plan,
      instant_of("2026-10-01T22:00"),
      instant_of("2026-10-01T23:00"),
      4,
    ),
    expected,
  )
}

///|
test "a freeze alone renders equals signs" {
  let plan = plan_of(
    "id=blackout;kind=freeze;start=2026-10-01T22:00;end=2026-10-01T23:00\n",
  )
  let output = @moon-change-window-auditor.render_timeline(
    plan,
    instant_of("2026-10-01T22:00"),
    instant_of("2026-10-01T23:00"),
    4,
  )
  assert_true(output.contains("blackout |====|\n"))
}

///|
test "a record outside the horizon renders free cells" {
  let plan = plan_of("id=other;start=2026-10-05T22:00;end=2026-10-05T23:00\n")
  let output = @moon-change-window-auditor.render_timeline(
    plan,
    instant_of("2026-10-01T22:00"),
    instant_of("2026-10-01T23:00"),
    4,
  )
  assert_true(output.contains("other |....|\n"))
}

///|
test "a record that starts before the horizon still fills the first cells" {
  let plan = plan_of("id=long;start=2026-10-01T21:00;end=2026-10-01T22:30\n")
  let output = @moon-change-window-auditor.render_timeline(
    plan,
    instant_of("2026-10-01T22:00"),
    instant_of("2026-10-01T23:00"),
    4,
  )
  assert_true(output.contains("long |##..|\n"))
}

///|
test "a record that covers part of the horizon stops in the right cell" {
  let plan = plan_of("id=tail;start=2026-10-01T22:00;end=2026-10-01T22:45\n")
  let output = @moon-change-window-auditor.render_timeline(
    plan,
    instant_of("2026-10-01T22:00"),
    instant_of("2026-10-01T23:00"),
    4,
  )
  assert_true(output.contains("tail |###.|\n"))
}

///|
test "the column count rounds the cell width up" {
  assert_eq(
    timeline_horizon("2026-10-01T22:00", "2026-10-01T23:00", 7),
    "Timeline 2026-10-01T22:00 -> 2026-10-01T23:00 (1h, 7 columns, 1 column = 9m)\n" +
    "legend: . free, # change, = freeze, ! change inside freeze\n",
  )
}

///|
test "ids of different lengths are padded to the same width" {
  let plan = plan_of(
    "id=a;start=2026-10-01T22:00;end=2026-10-01T22:30\n" +
    "id=longer;start=2026-10-01T22:30;end=2026-10-01T23:00\n",
  )
  let output = @moon-change-window-auditor.render_timeline(
    plan,
    instant_of("2026-10-01T22:00"),
    instant_of("2026-10-01T23:00"),
    2,
  )
  assert_true(output.contains("a      |#.|\n"))
  assert_true(output.contains("longer |.#|\n"))
}

///|
test "records are ordered by start minute" {
  let plan = plan_of(
    "id=late;start=2026-10-01T22:30;end=2026-10-01T23:00\n" +
    "id=early;start=2026-10-01T22:00;end=2026-10-01T22:30\n",
  )
  let output = @moon-change-window-auditor.render_timeline(
    plan,
    instant_of("2026-10-01T22:00"),
    instant_of("2026-10-01T23:00"),
    2,
  )
  assert_true(output.contains("early |#.|\nlate  |.#|\n"))
}

///|
test "an empty horizon or a non positive column count renders one line" {
  assert_eq(
    @moon-change-window-auditor.render_timeline(
      plan_of(""),
      instant_of("2026-10-01T23:00"),
      instant_of("2026-10-01T22:00"),
      4,
    ),
    "Timeline (empty horizon)\n",
  )
  assert_eq(
    @moon-change-window-auditor.render_timeline(
      plan_of(""),
      instant_of("2026-10-01T22:00"),
      instant_of("2026-10-01T22:00"),
      4,
    ),
    "Timeline (empty horizon)\n",
  )
  assert_eq(
    @moon-change-window-auditor.render_timeline(
      plan_of(""),
      instant_of("2026-10-01T22:00"),
      instant_of("2026-10-01T23:00"),
      0,
    ),
    "Timeline (empty horizon)\n",
  )
}

///|
test "a plan without records still prints the header and the legend" {
  assert_eq(
    timeline_horizon("2026-10-01T22:00", "2026-10-01T23:00", 4),
    "Timeline 2026-10-01T22:00 -> 2026-10-01T23:00 (1h, 4 columns, 1 column = 15m)\n" +
    "legend: . free, # change, = freeze, ! change inside freeze\n",
  )
}
