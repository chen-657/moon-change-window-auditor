///|
/// Minute based time handling for change windows.
///
/// An instant is the number of minutes since `1970-01-01T00:00` on a single,
/// unnamed time zone. Parsing only accepts `YYYY-MM-DDTHH:MM` (a space instead
/// of `T` is also accepted) for years 1970-2199, which keeps every instant
/// inside 32 bit `Int` range on all MoonBit backends.

///|
/// Lowest year accepted by `parse_instant`, the zero of the minute axis.
const MIN_YEAR : Int = 1970

///|
/// Highest year accepted by `parse_instant`.
const MAX_YEAR : Int = 2199

///|
/// Minutes in one day.
const MINUTES_PER_DAY : Int = 1440

///|
/// A calendar date on the minute axis, used to convert days back to text.
priv struct Civil {
  year : Int
  month : Int
  day : Int
}

///|
/// Gregorian leap year rule.
fn is_leap_year(year : Int) -> Bool {
  (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
}

///|
/// Number of days in a month, `0` for a month outside 1-12.
fn days_in_month(year : Int, month : Int) -> Int {
  match month {
    1 | 3 | 5 | 7 | 8 | 10 | 12 => 31
    4 | 6 | 9 | 11 => 30
    2 => if is_leap_year(year) { 29 } else { 28 }
    _ => 0
  }
}

///|
/// Days since 1970-01-01 for a Gregorian date.
///
/// Adapted from the public domain `days_from_civil` algorithm described by
/// Howard Hinnant in "chrono-Compatible Low-Level Date Algorithms". See
/// `SOURCES.md`. Division truncates towards zero, which is exact here because
/// every accepted year is positive.
fn days_from_civil(year : Int, month : Int, day : Int) -> Int {
  let adjusted_year = if month <= 2 { year - 1 } else { year }
  let era = adjusted_year / 400
  let year_of_era = adjusted_year - era * 400
  let month_index = (month + 9) % 12
  let day_of_year = (153 * month_index + 2) / 5 + day - 1
  let day_of_era = year_of_era * 365 +
    year_of_era / 4 -
    year_of_era / 100 +
    day_of_year
  era * 146097 + day_of_era - 719468
}

///|
/// Inverse of `days_from_civil`.
fn civil_from_days(days : Int) -> Civil {
  let shifted = days + 719468
  let era = shifted / 146097
  let day_of_era = shifted - era * 146097
  let year_of_era = (
      day_of_era - day_of_era / 1460 + day_of_era / 36524 - day_of_era / 146096
    ) /
    365
  let year = year_of_era + era * 400
  let day_of_year = day_of_era -
    (365 * year_of_era + year_of_era / 4 - year_of_era / 100)
  let month_index = (5 * day_of_year + 2) / 153
  let day = day_of_year - (153 * month_index + 2) / 5 + 1
  let month = if month_index < 10 { month_index + 3 } else { month_index - 9 }
  let shifted_year = if month <= 2 { year + 1 } else { year }
  { year: shifted_year, month, day, }
}

///|
/// Parse `YYYY-MM-DDTHH:MM` into minutes since 1970-01-01T00:00.
///
/// A single space is accepted where the `T` belongs. Everything else is
/// rejected: other lengths, separators, a year outside 1970-2199, an impossible
/// date such as `2026-02-30T10:00`, `24` as hour and `60` as minute.
pub fn parse_instant(text : String) -> Int? {
  let value = text.trim()
  if value.length() != 16 {
    return None
  }
  if value[4] != '-' || value[7] != '-' || value[13] != ':' {
    return None
  }
  let separator = value[10]
  if separator != 'T' && separator != ' ' {
    return None
  }
  let year = match parse_digits(value[0:4]) {
    Some(parsed) => parsed
    None => return None
  }
  let month = match parse_digits(value[5:7]) {
    Some(parsed) => parsed
    None => return None
  }
  let day = match parse_digits(value[8:10]) {
    Some(parsed) => parsed
    None => return None
  }
  let hour = match parse_digits(value[11:13]) {
    Some(parsed) => parsed
    None => return None
  }
  let minute = match parse_digits(value[14:16]) {
    Some(parsed) => parsed
    None => return None
  }
  if year < MIN_YEAR || year > MAX_YEAR {
    return None
  }
  if month < 1 || month > 12 {
    return None
  }
  if day < 1 || day > days_in_month(year, month) {
    return None
  }
  if hour > 23 || minute > 59 {
    return None
  }
  Some(days_from_civil(year, month, day) * MINUTES_PER_DAY + hour * 60 + minute)
}

///|
/// Render minutes since 1970-01-01T00:00 as `YYYY-MM-DDTHH:MM`.
///
/// This is the inverse of `parse_instant` for every instant it accepts.
/// Negative input is clamped to `1970-01-01T00:00`, because instants before the
/// epoch are outside the supported range.
pub fn format_instant(minutes : Int) -> String {
  let safe = if minutes < 0 { 0 } else { minutes }
  let days = safe / MINUTES_PER_DAY
  let rest = safe % MINUTES_PER_DAY
  let civil = civil_from_days(days)
  let builder = StringBuilder()
  builder.write_string(pad_left(civil.year, 4))
  builder.write_char('-')
  builder.write_string(pad_left(civil.month, 2))
  builder.write_char('-')
  builder.write_string(pad_left(civil.day, 2))
  builder.write_char('T')
  builder.write_string(pad_left(rest / 60, 2))
  builder.write_char(':')
  builder.write_string(pad_left(rest % 60, 2))
  builder.to_string()
}

///|
/// Render a duration in minutes as `45m`, `2h` or `1h30m`. The value is treated
/// as a magnitude, and `0` renders as `0m`.
pub fn format_duration(minutes : Int) -> String {
  let safe = if minutes < 0 { -minutes } else { minutes }
  let hours = safe / 60
  let rest = safe % 60
  if hours == 0 {
    rest.to_string() + "m"
  } else if rest == 0 {
    hours.to_string() + "h"
  } else {
    hours.to_string() + "h" + rest.to_string() + "m"
  }
}
