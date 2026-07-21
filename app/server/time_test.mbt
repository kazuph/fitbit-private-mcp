///|
test "D1 UTC timestamps are displayed in JST" {
  inspect(
    format_timestamp_jst("2026-07-20 22:00:31"),
    content="7月21日 07:00 JST",
  )
}
