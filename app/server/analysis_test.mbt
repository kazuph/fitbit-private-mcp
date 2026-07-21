///|
fn summary_row(
  date : String,
  steps : Int,
  sleep_minutes : Int,
  resting_heart_rate : Int,
) -> @core.Any {
  let row = @core.new_object()
  row._set("date", @core.any(date))
  row._set("steps", @core.any(steps))
  row._set("sleep_duration_minutes", @core.any(sleep_minutes))
  row._set("resting_heart_rate", @core.any(resting_heart_rate))
  row
}

///|
test "personal trend analysis recommends recovery actions from the user's own records" {
  let summaries = @core.any([
    summary_row("2026-07-19", 1000, 300, 70),
    summary_row("2026-07-18", 2000, 420, 65),
    summary_row("2026-07-17", 2000, 420, 65),
  ])

  let analysis = analyze_health_trends(summaries)

  inspect(analysis.context, content="直近2件の記録と比較")
  inspect(
    analysis.actions[0].title,
    content="活動のきっかけを一つ作る",
  )
  inspect(
    analysis.actions[1].title,
    content="今夜の休息を先に確保する",
  )
  inspect(analysis.actions[2].title, content="今日は体調を優先する")
}
