///|
/// Tests for the minute axis: parsing, formatting and duration rendering.

///|
test "instants round trip through parse_instant and format_instant" {
  let samples : Array[String] = [
    "1970-01-01T00:00", "1970-01-02T00:00", "1999-12-31T23:59", "2000-02-29T12:34",
    "2026-10-01T22:00", "2028-02-29T00:00", "2100-03-01T06:05", "2199-12-31T23:59",
  ]
  for sample in samples {
    assert_eq(
      @moon-change-window-auditor.format_instant(instant_of(sample)),
      sample,
    )
  }
}

///|
test "the epoch is minute zero and one day is 1440 minutes" {
  assert_eq(instant_of("1970-01-01T00:00"), 0)
  assert_eq(instant_of("1970-01-01T00:01"), 1)
  assert_eq(instant_of("1970-01-01T01:00"), 60)
  assert_eq(instant_of("1970-01-02T00:00"), 1440)
  assert_eq(instant_of("2026-10-01T23:00") - instant_of("2026-10-01T22:00"), 60)
  assert_eq(
    instant_of("2026-10-02T00:00") - instant_of("2026-10-01T00:00"),
    1440,
  )
}

///|
test "leap years follow the Gregorian rule" {
  // 2028 and 2000 are leap years, 2100 is not.
  assert_eq(
    instant_of("2028-03-01T00:00") - instant_of("2028-02-28T00:00"),
    2880,
  )
  assert_eq(
    instant_of("2100-03-01T00:00") - instant_of("2100-02-28T00:00"),
    1440,
  )
  assert_true(
    @moon-change-window-auditor.parse_instant("2028-02-30T00:00") is None,
  )
  assert_true(
    @moon-change-window-auditor.parse_instant("2100-02-29T00:00") is None,
  )
}

///|
test "a space is accepted instead of the T separator" {
  assert_eq(instant_of("2026-10-01 22:00"), instant_of("2026-10-01T22:00"))
  assert_eq(
    @moon-change-window-auditor.format_instant(instant_of("2026-10-01 22:00")),
    "2026-10-01T22:00",
  )
}

///|
test "parse_instant rejects malformed, impossible and out of range input" {
  let samples : Array[String] = [
    "", " ", "2026-10-01", "2026-10-01T22", "2026-10-01T22:00:00", "2026-10-01T22:00Z",
    "2026/10/01T22:00", "2026-1-01T22:00", "26-10-01T22:00", "2026-13-01T22:00",
    "2026-00-10T22:00", "2026-10-00T22:00", "2026-02-30T22:00", "2026-04-31T22:00",
    "2026-10-01T24:00", "2026-10-01T22:60", "2026-10-01T2a:00", "2026-10-01T-2:00",
    "1969-12-31T23:59", "2200-01-01T00:00",
  ]
  for sample in samples {
    assert_true(@moon-change-window-auditor.parse_instant(sample) is None)
  }
}

///|
test "surrounding spaces are trimmed" {
  assert_eq(instant_of("  2026-10-01T22:00  "), instant_of("2026-10-01T22:00"))
}

///|
test "format_instant clamps instants before the epoch" {
  assert_eq(@moon-change-window-auditor.format_instant(-1), "1970-01-01T00:00")
  assert_eq(
    @moon-change-window-auditor.format_instant(-100000),
    "1970-01-01T00:00",
  )
}

///|
test "format_duration renders minutes, hours and mixed values" {
  assert_eq(@moon-change-window-auditor.format_duration(0), "0m")
  assert_eq(@moon-change-window-auditor.format_duration(1), "1m")
  assert_eq(@moon-change-window-auditor.format_duration(45), "45m")
  assert_eq(@moon-change-window-auditor.format_duration(59), "59m")
  assert_eq(@moon-change-window-auditor.format_duration(60), "1h")
  assert_eq(@moon-change-window-auditor.format_duration(90), "1h30m")
  assert_eq(@moon-change-window-auditor.format_duration(1440), "24h")
  assert_eq(@moon-change-window-auditor.format_duration(-45), "45m")
}
