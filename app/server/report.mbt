///|
/// Daily Health Report Generation and Posting
/// Shares the same personal trend analysis with the dashboard.

///|
/// Post daily health report to Slack
/// This is the main entry point called from scheduled worker
pub async fn post_daily_health_report() -> Unit {
  let yesterday = get_yesterday_jst()
  let state_key = "slack:dailyReportDate"
  let last_posted = get_sync_state(state_key)
  match last_posted {
    Some(posted) =>
      if posted == yesterday {
        console_log("Daily report already posted for: " + yesterday)
        return
      }
    None => ()
  }

  let summaries = db_get_daily_summaries_until(
    yesterday,
    health_analysis_history_limit(),
  )
  if array_len(summaries) == 0 {
    console_log("No summary data for: " + yesterday)
    return
  }
  let analysis = analyze_health_trends(summaries)
  let posted = post_to_slack(format_health_analysis_for_slack(analysis))
  if posted {
    set_sync_state(state_key, yesterday)
    console_log("Daily health action report posted for: " + yesterday)
  }
}
