///|
/// Type definitions for Fitbit Health Services

///|
/// Sleep stages breakdown
pub struct SleepStages {
  deep : Int
  light : Int
  rem : Int
  wake : Int
}

///|
/// Heart rate zones breakdown
pub struct HeartRateZones {
  fat_burn : Int
  cardio : Int
  peak : Int
}

///|
/// Health summary data from Fitbit
pub struct HealthSummary {
  date : String
  steps : Int
  calories : Int
  distance : Double
  active_minutes : Int
  resting_heart_rate : Int?
  sleep_duration_minutes : Int
  sleep_efficiency : Int?
  weight : Double?
  vo2max : String?
  spo2_avg : Double?
  sleep_stages : SleepStages?
  heart_rate_zones : HeartRateZones?
}

///|
/// Health insights from Gemini analysis
pub struct HealthInsights {
  summary : String
  highlights : Array[String]
  improvements : Array[String]
  actionable_tips : Array[String]
}

///|
/// Create empty health insights
pub fn HealthInsights::empty() -> HealthInsights {
  {
    summary: "",
    highlights: [],
    improvements: [],
    actionable_tips: [],
  }
}

///|
/// Check if insights have content
pub fn HealthInsights::has_content(self : HealthInsights) -> Bool {
  self.summary != "" ||
  self.highlights.length() > 0 ||
  self.improvements.length() > 0 ||
  self.actionable_tips.length() > 0
}

///|
/// Parse HealthSummary from JS object
pub fn parse_health_summary(obj : @core.Any) -> HealthSummary {
  // Parse sleep stages if present
  let sleep_stages_obj = obj._get("sleep_stages")
  let sleep_stages : SleepStages? = if is_null(sleep_stages_obj) {
    None
  } else {
    Some({
      deep: get_int(sleep_stages_obj, "deep"),
      light: get_int(sleep_stages_obj, "light"),
      rem: get_int(sleep_stages_obj, "rem"),
      wake: get_int(sleep_stages_obj, "wake"),
    })
  }

  // Parse heart rate zones if present
  let hr_zones_obj = obj._get("heart_rate_zones")
  let heart_rate_zones : HeartRateZones? = if is_null(hr_zones_obj) {
    None
  } else {
    Some({
      fat_burn: get_int(hr_zones_obj, "fat_burn"),
      cardio: get_int(hr_zones_obj, "cardio"),
      peak: get_int(hr_zones_obj, "peak"),
    })
  }

  {
    date: get_str(obj, "date"),
    steps: get_int(obj, "steps"),
    calories: get_int(obj, "calories"),
    distance: get_float(obj, "distance"),
    active_minutes: get_int(obj, "active_minutes"),
    resting_heart_rate: get_int_opt(obj, "resting_heart_rate"),
    sleep_duration_minutes: get_int(obj, "sleep_duration_minutes"),
    sleep_efficiency: get_int_opt(obj, "sleep_efficiency"),
    weight: get_float_opt(obj, "weight"),
    vo2max: get_str_opt(obj, "vo2max"),
    spo2_avg: get_float_opt(obj, "spo2_avg"),
    sleep_stages,
    heart_rate_zones,
  }
}

///|
/// Parse HealthInsights from Gemini API response
pub fn parse_health_insights(json : @core.Any) -> HealthInsights {
  // Parse summary
  let summary = safe_string(json._get("summary"))

  // Parse highlights array
  let highlights : Array[String] = []
  let highlights_arr = json._get("highlights")
  if not(is_null(highlights_arr)) {
    let arr = to_array(highlights_arr)
    for item in arr {
      highlights.push(safe_string(item))
    }
  }

  // Parse improvements array
  let improvements : Array[String] = []
  let improvements_arr = json._get("improvements")
  if not(is_null(improvements_arr)) {
    let arr = to_array(improvements_arr)
    for item in arr {
      improvements.push(safe_string(item))
    }
  }

  // Parse actionable_tips array
  let actionable_tips : Array[String] = []
  let tips_arr = json._get("actionable_tips")
  if not(is_null(tips_arr)) {
    let arr = to_array(tips_arr)
    for item in arr {
      actionable_tips.push(safe_string(item))
    }
  }

  { summary, highlights, improvements, actionable_tips }
}

///|
/// Convert HealthInsights to JS object for export
pub fn HealthInsights::to_js(self : HealthInsights) -> @core.Any {
  let result = @core.new_object()
  result._set("summary", @core.any(self.summary))

  // Convert highlights
  let highlights_arr = @core.new_array()
  for h in self.highlights {
    @core.any(highlights_arr)._call("push", [@core.any(h)]) |> ignore
  }
  result._set("highlights", highlights_arr)

  // Convert improvements
  let improvements_arr = @core.new_array()
  for i in self.improvements {
    @core.any(improvements_arr)._call("push", [@core.any(i)]) |> ignore
  }
  result._set("improvements", improvements_arr)

  // Convert actionable_tips
  let tips_arr = @core.new_array()
  for t in self.actionable_tips {
    @core.any(tips_arr)._call("push", [@core.any(t)]) |> ignore
  }
  result._set("actionable_tips", tips_arr)

  result
}

///|
/// Format minutes to hours and minutes string
pub fn format_minutes_to_hours(minutes : Int) -> String {
  if minutes == 0 {
    return "データなし"
  }
  let hours = minutes / 60
  let mins = minutes % 60
  hours.to_string() + "時間" + mins.to_string() + "分"
}
