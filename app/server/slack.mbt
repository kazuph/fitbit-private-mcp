///|
/// Slack Posting Service for Fitbit Health Insights
/// Posts health reports to Slack channels

///|
/// Slack API URL
let slack_api_url : String = "https://slack.com/api/chat.postMessage"

///|
/// Default channel
let default_channel : String = "#limitless-音声-insight"

///|
/// Bot username
let bot_username : String = "けろよん"

///|
/// Bot icon URL
let bot_icon_url : String = "https://emoji.slack-edge.com/T030A5CV2/keroyon/c3aa47f65017d188.png"

///|
/// Post a message to Slack
pub async fn post_to_slack(text : String) -> Bool {
  let token = get_env("SLACK_BOT_TOKEN")
  let channel_env = get_env("SLACK_CHANNEL")
  let channel = if channel_env == "" { default_channel } else { channel_env }
  if token == "" {
    @console.error(@core.any("SLACK_BOT_TOKEN not configured"))
    false
  } else {
    // Build form data using URLSearchParams
    let params = new_url_search_params()
    params.set("token", token)
    params.set("channel", channel)
    params.set("username", bot_username)
    params.set("icon_url", bot_icon_url)
    params.set("text", text)
    params.set("link_names", "true")
    let response = @http.fetch(
      slack_api_url,
      method_="POST",
      headers={ "Content-Type": "application/x-www-form-urlencoded" },
      body=@core.any(params.to_string()),
    )
    if not(response.ok) {
      @console.error(
        @core.any("Slack API error: " + response.status.to_string()),
      )
      false
    } else {
      let result = response.json()
      let ok = result._get("ok")
      if is_null(ok) || not(safe_bool(ok)) {
        let error_msg = result._get("error")
        let error_str = if is_null(error_msg) {
          "unknown error"
        } else {
          safe_string(error_msg)
        }
        @console.error(@core.any("Slack post failed: " + error_str))
        false
      } else {
        true
      }
    }
  }
}

///|
/// Format health insights for Slack message
pub fn format_health_insights_for_slack(
  insights : HealthInsights,
  date : String,
) -> String {
  let mut sections = "@kazuph :runner: *Fitbit 健康レポート*\n_" +
    date +
    " のサマリー_"

  // Summary
  if insights.summary != "" {
    sections = sections + "\n\n:memo: *サマリー*\n" + insights.summary
  }

  // Highlights
  if insights.highlights.length() > 0 {
    let mut items = ""
    for h in insights.highlights {
      items = items + "• " + h + "\n"
    }
    sections = sections + "\n\n:sparkles: *良かった点*\n" + items
  }

  // Improvements
  if insights.improvements.length() > 0 {
    let mut items = ""
    for i in insights.improvements {
      items = items + "• " + i + "\n"
    }
    sections = sections +
      "\n\n:chart_with_upwards_trend: *改善ポイント*\n" +
      items
  }

  // Actionable Tips
  if insights.actionable_tips.length() > 0 {
    let mut items = ""
    for t in insights.actionable_tips {
      items = items + "• " + t + "\n"
    }
    sections = sections + "\n\n:bulb: *今日のアドバイス*\n" + items
  }
  sections
}

///|
/// Post health insights to Slack (exported function)
pub async fn post_health_insights_to_slack(
  insights_js : @core.Any,
  date : String,
) -> Bool {
  // Parse insights from JS object
  let insights = parse_health_insights(insights_js)
  if not(insights.has_content()) {
    @console.info(@core.any("No health insights to post"))
    false
  } else {
    let message = format_health_insights_for_slack(insights, date)
    post_to_slack(message)
  }
}

///|
/// Post error notification to Slack
pub async fn post_error_to_slack(
  error_message : String,
  context : String?,
) -> Bool {
  let timestamp = get_current_time_jst()
  let mut text = ":warning: *Fitbit Cron処理エラー*\n_" + timestamp + "_"
  match context {
    Some(ctx) => text = text + "\n\n*コンテキスト:* " + ctx
    None => ()
  }
  text = text + "\n\n*エラー:* " + error_message
  post_to_slack(text)
}
