///|
/// Daily Health Report Generation and Posting
/// Handles the orchestration of fetching data, analyzing with Gemini, and posting to Slack

///|
/// Post daily health report to Slack
/// This is the main entry point called from scheduled worker
pub async fn post_daily_health_report() -> Unit {
  let yesterday = get_yesterday_jst()
  let db = get_db()

  // Check if already posted today
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

  // Get yesterday's summary
  let summary_row = db
    .prepare("SELECT * FROM daily_summary WHERE date = ?")
    .bind1(@core.any(yesterday))
    .first()

  match summary_row {
    None => {
      console_log("No summary data for: " + yesterday)
      return
    }
    Some(summary) => {
      // Get detailed data for Gemini analysis
      let sleep_row = db
        .prepare("SELECT * FROM sleep_data WHERE date = ?")
        .bind1(@core.any(yesterday))
        .first()

      let heart_row = db
        .prepare("SELECT * FROM heart_rate WHERE date = ?")
        .bind1(@core.any(yesterday))
        .first()

      // Build health summary for Gemini (as @core.Any object)
      let health_data = build_health_data_object(
        yesterday,
        summary,
        sleep_row,
        heart_row,
      )

      // Analyze with Gemini
      let insights = analyze_health_data(health_data)

      if is_null(insights) {
        console_log("Failed to generate insights for: " + yesterday)
      } else {
        // Post to Slack
        let posted = post_health_insights_to_slack(insights, yesterday)
        if posted {
          // Update state to prevent duplicate posts
          set_sync_state(state_key, yesterday)
          console_log("Daily health report posted for: " + yesterday)
        }
      }
    }
  }
}

///|
/// Build health data object from database rows (returns @core.Any)
fn build_health_data_object(
  date : String,
  summary : @core.Any,
  sleep_row : @core.Any?,
  heart_row : @core.Any?
) -> @core.Any {
  let obj = @core.new_object()
  obj._set("date", @core.any(date))
  obj._set("steps", summary._get("steps"))
  obj._set("calories", summary._get("calories"))
  obj._set("distance", summary._get("distance"))
  obj._set("active_minutes", summary._get("active_minutes"))
  obj._set("resting_heart_rate", summary._get("resting_heart_rate"))
  obj._set("sleep_duration_minutes", summary._get("sleep_duration_minutes"))
  obj._set("sleep_efficiency", summary._get("sleep_efficiency"))
  obj._set("weight", summary._get("weight"))
  obj._set("vo2max", summary._get("vo2max"))
  obj._set("spo2_avg", summary._get("spo2_avg"))

  // Add sleep stages if available
  match sleep_row {
    Some(sleep) => {
      let stages = @core.new_object()
      stages._set("deep", sleep._get("deep_minutes"))
      stages._set("light", sleep._get("light_minutes"))
      stages._set("rem", sleep._get("rem_minutes"))
      stages._set("wake", sleep._get("wake_minutes"))
      obj._set("sleep_stages", stages)
    }
    None => ()
  }

  // Add heart rate zones if available
  match heart_row {
    Some(heart) => {
      let zones = @core.new_object()
      zones._set("fat_burn", heart._get("fat_burn_minutes"))
      zones._set("cardio", heart._get("cardio_minutes"))
      zones._set("peak", heart._get("peak_minutes"))
      obj._set("heart_rate_zones", zones)
    }
    None => ()
  }

  obj
}
