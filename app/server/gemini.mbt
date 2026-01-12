///|
/// Gemini AI Service for Health Data Analysis
/// Analyzes Fitbit health data and provides insights

///|
/// Gemini API configuration
let gemini_model : String = "gemini-2.0-flash"

///|
let gemini_api_url : String = "https://generativelanguage.googleapis.com/v1beta/models"

///|
/// System prompt for health analysis
let health_system_prompt : String =
  #|あなたは健康アドバイザーです。以下のFitbit健康データを分析し、具体的な行動改善アドバイスを日本語で提供してください。
  #|
  #|分析対象:
  #|1. 活動量（歩数、アクティブ時間、消費カロリー）
  #|2. 睡眠（時間、効率、ステージ）
  #|3. 心拍数（安静時HR、ゾーン別時間）
  #|4. 体重/BMI
  #|5. VO2max（心肺機能スコア）- 範囲または数値で提供
  #|6. SpO2（血中酸素濃度）- 睡眠中の平均値
  #|
  #|重要な注意事項:
  #|- データがない項目（null）は「データなし」として扱い、無理に評価しないこと
  #|- 具体的で実行可能なアドバイスを提供すること
  #|- ポジティブな点を必ず含めること
  #|- 各配列は最大3個までにすること
  #|
  #|出力はJSON形式で以下のスキーマに従ってください:
  #|{
  #|  "summary": "全体評価（1-2文）",
  #|  "highlights": ["良かった点1", "良かった点2", ...],
  #|  "improvements": ["改善すべき点1", "改善すべき点2", ...],
  #|  "actionable_tips": ["今日から実践できるアドバイス1", ...]
  #|}

///|
/// Format health data for the prompt
fn format_health_data_for_prompt(data : HealthSummary) -> String {
  let mut lines = "日付: " + data.date + "\n\n"

  // Activity section
  lines = lines + "## 活動量\n"
  lines = lines + "- 歩数: " + format_number(data.steps) + " 歩\n"
  lines = lines + "- 消費カロリー: " + format_number(data.calories) + " kcal\n"
  lines = lines + "- 移動距離: " + format_float(data.distance, 2) + " km\n"
  lines = lines + "- アクティブ時間: " + data.active_minutes.to_string() + " 分\n"

  // Heart rate zones
  match data.heart_rate_zones {
    Some(zones) => {
      lines = lines + "- 心拍ゾーン:\n"
      lines = lines + "  - 脂肪燃焼: " + zones.fat_burn.to_string() + " 分\n"
      lines = lines + "  - 有酸素: " + zones.cardio.to_string() + " 分\n"
      lines = lines + "  - ピーク: " + zones.peak.to_string() + " 分\n"
    }
    None => ()
  }

  // Sleep section
  lines = lines + "\n## 睡眠\n"
  lines = lines + "- 睡眠時間: " + format_minutes_to_hours(data.sleep_duration_minutes) + "\n"
  lines = lines + "- 睡眠効率: " + (match data.sleep_efficiency {
    Some(e) => e.to_string() + "%"
    None => "データなし"
  }) + "\n"

  match data.sleep_stages {
    Some(stages) => {
      lines = lines + "- 睡眠ステージ:\n"
      lines = lines + "  - 深い睡眠: " + stages.deep.to_string() + " 分\n"
      lines = lines + "  - 浅い睡眠: " + stages.light.to_string() + " 分\n"
      lines = lines + "  - レム睡眠: " + stages.rem.to_string() + " 分\n"
      lines = lines + "  - 覚醒: " + stages.wake.to_string() + " 分\n"
    }
    None => ()
  }

  // Heart rate section
  lines = lines + "\n## 心拍数\n"
  lines = lines + "- 安静時心拍数: " + (match data.resting_heart_rate {
    Some(hr) => hr.to_string() + " bpm"
    None => "データなし"
  }) + "\n"

  // Weight section
  lines = lines + "\n## 体重\n"
  lines = lines + "- 体重: " + (match data.weight {
    Some(w) => format_float(w, 1) + " kg"
    None => "データなし"
  }) + "\n"

  // VO2max section
  lines = lines + "\n## 心肺機能 (VO2max)\n"
  lines = lines + "- スコア: " + (match data.vo2max {
    Some(v) => v
    None => "データなし"
  }) + "\n"

  // SpO2 section
  lines = lines + "\n## 血中酸素 (SpO2)\n"
  lines = lines + "- 平均: " + (match data.spo2_avg {
    Some(s) => format_float(s, 1) + "%"
    None => "データなし"
  }) + "\n"

  lines
}

///|
/// Escape special characters for JSON string
fn escape_json_string(s : String) -> String {
  let mut result = ""
  for c in s {
    if c == '"' {
      result = result + "\\\""
    } else if c == '\\' {
      result = result + "\\\\"
    } else if c == '\n' {
      result = result + "\\n"
    } else if c == '\r' {
      result = result + "\\r"
    } else if c == '\t' {
      result = result + "\\t"
    } else {
      result = result + c.to_string()
    }
  }
  result
}

///|
/// Analyze health data using Gemini API
/// Returns HealthInsights or None if analysis fails
pub async fn analyze_health_data(health_data : @core.Any) -> @core.Any {
  let api_key = get_env("GEMINI_API_KEY")

  if api_key == "" {
    @console.error(@core.any("GEMINI_API_KEY not configured"))
    return @core.null()
  }

  // Parse health data
  let data = parse_health_summary(health_data)

  // Build prompt
  let data_payload = format_health_data_for_prompt(data)
  let prompt = health_system_prompt + "\n\n---\n\n健康データ:\n" + data_payload

  // Build request body
  let request_body = @core.new_object()

  // contents array
  let contents = @core.new_array()
  let content_obj = @core.new_object()
  let parts = @core.new_array()
  let part_obj = @core.new_object()
  part_obj._set("text", @core.any(prompt))
  @core.any(parts)._call("push", [@core.identity(part_obj)]) |> ignore
  content_obj._set("parts", parts)
  @core.any(contents)._call("push", [@core.identity(content_obj)]) |> ignore
  request_body._set("contents", contents)

  // generationConfig
  let gen_config = @core.new_object()
  gen_config._set("responseMimeType", @core.any("application/json"))
  gen_config._set("temperature", @core.any(0.7))
  gen_config._set("maxOutputTokens", @core.any(2048))
  request_body._set("generationConfig", gen_config)

  // Make API request
  let url = gemini_api_url + "/" + gemini_model + ":generateContent?key=" + api_key

  let response = @http.fetch(
    url,
    method_="POST",
    headers={ "Content-Type": "application/json" },
    body=request_body,
  )

  if not(response.ok) {
    let error_text = response.text()
    @console.error(@core.any("Gemini API error: " + response.status.to_string() + " " + error_text))
    return @core.null()
  }

  let result = response.json()

  // Extract text from response
  let candidates = result._get("candidates")
  if is_null(candidates) {
    @console.error(@core.any("No candidates in Gemini response"))
    return @core.null()
  }

  let candidates_arr = to_array(candidates)
  if candidates_arr.length() == 0 {
    @console.error(@core.any("Empty candidates array in Gemini response"))
    return @core.null()
  }

  let first_candidate = candidates_arr[0]
  let content = first_candidate._get("content")
  if is_null(content) {
    @console.error(@core.any("No content in first candidate"))
    return @core.null()
  }

  let response_parts = content._get("parts")
  if is_null(response_parts) {
    @console.error(@core.any("No parts in content"))
    return @core.null()
  }

  let parts_arr = to_array(response_parts)
  if parts_arr.length() == 0 {
    @console.error(@core.any("Empty parts array"))
    return @core.null()
  }

  let text = parts_arr[0]._get("text")
  if is_null(text) {
    @console.error(@core.any("No text in first part"))
    return @core.null()
  }

  // Parse JSON response
  let text_str : String = text.cast()
  let insights_json = json_parse(text_str)
  let insights = parse_health_insights(insights_json)

  // Return as JS object
  insights.to_js()
}
