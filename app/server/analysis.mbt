///|
/// Personal health trend analysis for the dashboard and daily Slack report.

///|
/// An ISO week is the comparison window for a person's own recent records.
let weekly_comparison_days : Int = 7

///|
pub struct HealthAction {
  title : String
  detail : String
}

///|
pub struct HealthAnalysis {
  date : String
  context : String
  headline : String
  actions : Array[HealthAction]
}

///|
pub fn health_analysis_history_limit() -> Int {
  weekly_comparison_days + 1
}

///|
fn history_average(rows : Array[@core.Any], field : String) -> Int? {
  let mut total = 0
  let mut count = 0
  for i in 1..<rows.length() {
    let raw_value = rows[i]._get(field)
    if !is_null(raw_value) {
      total = total + get_int(rows[i], field)
      count = count + 1
    }
  }
  if count == 0 {
    None
  } else {
    Some(total / count)
  }
}

///|
fn action_for_activity(latest : @core.Any, baseline : Int?) -> HealthAction {
  let steps = get_int(latest, "steps")
  match baseline {
    Some(average) if steps < average =>
      {
        title: "活動のきっかけを一つ作る",
        detail: "歩数は最近の記録より少なめです。次の移動で、無理のない散歩や階段を選びましょう。",
      }
    Some(_) =>
      {
        title: "動けた流れを明日につなぐ",
        detail: "歩数は最近の記録を維持できています。疲れを残さないよう、回復の時間も予定に入れましょう。",
      }
    None =>
      {
        title: "まずは自分の基準を作る",
        detail: "比較できる記録が増えるほど、あなた自身に合った活動の傾向が見えてきます。",
      }
  }
}

///|
fn action_for_sleep(latest : @core.Any, baseline : Int?) -> HealthAction {
  let sleep_minutes = get_int(latest, "sleep_duration_minutes")
  if sleep_minutes == 0 {
    return {
      title: "睡眠の記録をためる",
      detail: "睡眠の傾向を把握するため、数日分の記録をそろえていきましょう。",
    }
  }
  match baseline {
    Some(average) if sleep_minutes < average =>
      {
        title: "今夜の休息を先に確保する",
        detail: "睡眠時間は最近の記録より短めです。就寝前の予定を一つ減らし、休む準備を早めましょう。",
      }
    Some(_) =>
      {
        title: "睡眠リズムを保つ",
        detail: "睡眠時間は最近の記録を維持できています。今夜も同じリズムを続けることが、明日の活動を支えます。",
      }
    None =>
      {
        title: "睡眠の記録をためる",
        detail: "睡眠の傾向を把握するため、数日分の記録をそろえていきましょう。",
      }
  }
}

///|
fn action_for_recovery(latest : @core.Any, baseline : Int?) -> HealthAction {
  let resting_heart_rate = get_int(latest, "resting_heart_rate")
  if resting_heart_rate == 0 {
    return {
      title: "回復の記録をためる",
      detail: "安静時心拍の傾向を把握するため、数日分の記録をそろえていきましょう。",
    }
  }
  match baseline {
    Some(average) if resting_heart_rate > average =>
      {
        title: "今日は体調を優先する",
        detail: "安静時心拍は最近の記録より高めです。無理に強度を上げず、違和感や症状があるときは医療者に相談してください。",
      }
    Some(_) =>
      {
        title: "回復の状態を観察する",
        detail: "安静時心拍は最近の記録を維持できています。睡眠と活動のバランスを続けて観察しましょう。",
      }
    None =>
      {
        title: "回復の変化を見守る",
        detail: "安静時心拍は日々の活動や休息の影響を受けます。記録を重ねて、自分の変化を見ていきましょう。",
      }
  }
}

///|
pub fn analyze_health_trends(summaries : @core.Any) -> HealthAnalysis {
  let rows = to_array(summaries)
  if rows.length() == 0 {
    return {
      date: "",
      context: "まだ比較できる記録がありません",
      headline: "Fitbitを同期すると、あなた自身の変化から次の行動を提案します。",
      actions: [],
    }
  }
  let latest = rows[0]
  let date = get_str(latest, "date")
  let compared_records = if rows.length() > 1 { rows.length() - 1 } else { 0 }
  let context = if compared_records > 0 {
    "直近" + compared_records.to_string() + "件の記録と比較"
  } else {
    "最初の記録を基準に準備中"
  }
  {
    date,
    context,
    headline: "数値を眺めるだけで終わらせず、今日の行動につなげましょう。",
    actions: [
      action_for_activity(latest, history_average(rows, "steps")),
      action_for_sleep(latest, history_average(rows, "sleep_duration_minutes")),
      action_for_recovery(latest, history_average(rows, "resting_heart_rate")),
    ],
  }
}

///|
pub fn format_health_analysis_for_slack(analysis : HealthAnalysis) -> String {
  let mut message = "<@U06778BS5LK> :seedling: *今日の健康アクション*\n_" +
    analysis.date +
    " / " +
    analysis.context +
    "_\n\n" +
    analysis.headline
  for action in analysis.actions {
    message = message + "\n\n*" + action.title + "*\n" + action.detail
  }
  message +
  "\n\n_これは記録にもとづく振り返りであり、医療上の診断ではありません。_"
}
