///|
/// Data Sync Helpers for Fitbit Health Data
/// Provides utility functions for data synchronization

///|
/// Update daily summary with aggregated data
/// This is a helper that builds the summary from individual data tables
pub async fn build_daily_summary(
  date : String,
  vo2max : String?,
  spo2_avg : Double?
) -> @core.Any {
  let db = get_db()

  // Get activity data
  let activity = db
    .prepare("SELECT * FROM daily_activity WHERE date = ?")
    .bind1(@core.any(date))
    .first()

  // Get sleep data
  let sleep = db
    .prepare("SELECT * FROM sleep_data WHERE date = ?")
    .bind1(@core.any(date))
    .first()

  // Get heart rate data
  let heart = db
    .prepare("SELECT * FROM heart_rate WHERE date = ?")
    .bind1(@core.any(date))
    .first()

  // Get weight data (most recent)
  let weight = db
    .prepare("SELECT * FROM weight_data WHERE date = ? ORDER BY created_at DESC LIMIT 1")
    .bind1(@core.any(date))
    .first()

  // Calculate active minutes
  let fairly_active = match activity {
    Some(a) => get_int(a, "fairly_active_minutes")
    None => 0
  }
  let very_active = match activity {
    Some(a) => get_int(a, "very_active_minutes")
    None => 0
  }
  let active_minutes = fairly_active + very_active

  // Build summary object
  let summary = @core.new_object()
  summary._set("date", @core.any(date))

  match activity {
    Some(a) => {
      summary._set("steps", a._get("steps"))
      summary._set("calories", a._get("calories_out"))
      summary._set("distance", a._get("distance"))
    }
    None => {
      summary._set("steps", @core.any(0))
      summary._set("calories", @core.any(0))
      summary._set("distance", @core.any(0))
    }
  }

  summary._set("active_minutes", @core.any(active_minutes))

  match heart {
    Some(h) => summary._set("resting_heart_rate", h._get("resting_heart_rate"))
    None => summary._set("resting_heart_rate", @core.null())
  }

  match sleep {
    Some(s) => {
      summary._set("sleep_duration_minutes", s._get("duration_minutes"))
      summary._set("sleep_efficiency", s._get("efficiency"))
    }
    None => {
      summary._set("sleep_duration_minutes", @core.any(0))
      summary._set("sleep_efficiency", @core.null())
    }
  }

  match weight {
    Some(w) => summary._set("weight", w._get("weight"))
    None => summary._set("weight", @core.null())
  }

  match vo2max {
    Some(v) => summary._set("vo2max", @core.any(v))
    None => summary._set("vo2max", @core.null())
  }

  match spo2_avg {
    Some(s) => summary._set("spo2_avg", @core.any(s))
    None => summary._set("spo2_avg", @core.null())
  }

  summary
}

///|
/// Update daily summary in D1 database
/// This writes the aggregated summary to the daily_summary table
pub async fn update_daily_summary(date : String, vo2max : String?, spo2_avg : Double?) -> Unit {
  let db = get_db()

  // Get activity data
  let activity = db
    .prepare("SELECT * FROM daily_activity WHERE date = ?")
    .bind1(@core.any(date))
    .first()

  // Get sleep data
  let sleep = db
    .prepare("SELECT * FROM sleep_data WHERE date = ?")
    .bind1(@core.any(date))
    .first()

  // Get heart rate data
  let heart = db
    .prepare("SELECT * FROM heart_rate WHERE date = ?")
    .bind1(@core.any(date))
    .first()

  // Get weight data (most recent)
  let weight = db
    .prepare("SELECT * FROM weight_data WHERE date = ? ORDER BY created_at DESC LIMIT 1")
    .bind1(@core.any(date))
    .first()

  // Calculate active minutes
  let fairly_active = match activity {
    Some(a) => get_int(a, "fairly_active_minutes")
    None => 0
  }
  let very_active = match activity {
    Some(a) => get_int(a, "very_active_minutes")
    None => 0
  }
  let active_minutes = fairly_active + very_active

  // Get values with defaults
  let steps = match activity {
    Some(a) => get_int(a, "steps")
    None => 0
  }
  let calories = match activity {
    Some(a) => get_int(a, "calories_out")
    None => 0
  }
  let distance = match activity {
    Some(a) => get_float(a, "distance")
    None => 0.0
  }
  let resting_hr = match heart {
    Some(h) => {
      let v = h._get("resting_heart_rate")
      if is_null(v) { @core.null() } else { v }
    }
    None => @core.null()
  }
  let sleep_duration = match sleep {
    Some(s) => get_int(s, "duration_minutes")
    None => 0
  }
  let sleep_efficiency = match sleep {
    Some(s) => {
      let v = s._get("efficiency")
      if is_null(v) { @core.null() } else { v }
    }
    None => @core.null()
  }
  let weight_val = match weight {
    Some(w) => {
      let v = w._get("weight")
      if is_null(v) { @core.null() } else { v }
    }
    None => @core.null()
  }

  let vo2max_val : @core.Any = match vo2max {
    Some(v) => @core.any(v)
    None => @core.null()
  }
  let spo2_val : @core.Any = match spo2_avg {
    Some(s) => @core.any(s)
    None => @core.null()
  }

  // Insert or update daily summary
  let query = "INSERT INTO daily_summary (date, steps, calories, distance, active_minutes, resting_heart_rate, sleep_duration_minutes, sleep_efficiency, weight, vo2max, spo2_avg) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) ON CONFLICT(date) DO UPDATE SET steps = excluded.steps, calories = excluded.calories, distance = excluded.distance, active_minutes = excluded.active_minutes, resting_heart_rate = excluded.resting_heart_rate, sleep_duration_minutes = excluded.sleep_duration_minutes, sleep_efficiency = excluded.sleep_efficiency, weight = excluded.weight, vo2max = excluded.vo2max, spo2_avg = excluded.spo2_avg"
  db.prepare(query)
    .bind([
      @core.any(date),
      @core.any(steps),
      @core.any(calories),
      @core.any(distance),
      @core.any(active_minutes),
      resting_hr,
      @core.any(sleep_duration),
      sleep_efficiency,
      weight_val,
      vo2max_val,
      spo2_val,
    ])
    .run()
  |> ignore
}

///|
/// Sync all health data from Fitbit API to D1
/// Returns (vo2max, spo2_avg) for use in daily summary
pub async fn sync_health_data(access_token : String, date : String) -> (String?, Double?) {
  let db = get_db()

  // Fetch all data from Fitbit API
  let activity_raw = fetch_activity_data(access_token, date)
  let sleep_raw = fetch_sleep_data(access_token, date)
  let heart_raw = fetch_heart_data(access_token, date)
  let weight_raw = fetch_weight_data(access_token, date)
  let vo2max_raw = fetch_vo2max_data(access_token, date)
  let spo2_raw = fetch_spo2_data(access_token, date)

  // Process and store activity data
  if not(is_null(activity_raw)) {
    let activity = parse_activity_data(activity_raw)
    if not(is_null(activity)) {
      save_activity_data(db, date, activity, activity_raw)
    }
  }

  // Process and store sleep data
  if not(is_null(sleep_raw)) {
    let sleep = parse_sleep_data(sleep_raw)
    if not(is_null(sleep)) {
      save_sleep_data(db, date, sleep, sleep_raw)
    }
  }

  // Process and store heart rate data
  if not(is_null(heart_raw)) {
    let heart = parse_heart_data(heart_raw)
    if not(is_null(heart)) {
      save_heart_data(db, date, heart, heart_raw)
    }
  }

  // Process and store weight data
  if not(is_null(weight_raw)) {
    save_weight_data(db, weight_raw)
  }

  // Process VO2max data
  let vo2max_value : String? = if not(is_null(vo2max_raw)) {
    save_vo2max_data(db, vo2max_raw)
  } else {
    None
  }

  // Process SpO2 data
  let spo2_avg : Double? = if not(is_null(spo2_raw)) {
    save_spo2_data(db, spo2_raw)
  } else {
    None
  }

  (vo2max_value, spo2_avg)
}

///|
/// Save activity data to D1
async fn save_activity_data(
  db : @cloudflare.D1Database,
  date : String,
  activity : @core.Any,
  raw : @core.Any
) -> Unit {
  let query = "INSERT INTO daily_activity (date, steps, calories_out, distance, floors, sedentary_minutes, lightly_active_minutes, fairly_active_minutes, very_active_minutes, raw_data) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?) ON CONFLICT(date) DO UPDATE SET steps = excluded.steps, calories_out = excluded.calories_out, distance = excluded.distance, floors = excluded.floors, sedentary_minutes = excluded.sedentary_minutes, lightly_active_minutes = excluded.lightly_active_minutes, fairly_active_minutes = excluded.fairly_active_minutes, very_active_minutes = excluded.very_active_minutes, raw_data = excluded.raw_data"
  db.prepare(query)
    .bind([
      @core.any(date),
      activity._get("steps"),
      activity._get("caloriesOut"),
      activity._get("distance"),
      activity._get("floors"),
      activity._get("sedentaryMinutes"),
      activity._get("lightlyActiveMinutes"),
      activity._get("fairlyActiveMinutes"),
      activity._get("veryActiveMinutes"),
      @core.any(json_stringify(raw)),
    ])
    .run()
  |> ignore
}

///|
/// Save sleep data to D1
async fn save_sleep_data(
  db : @cloudflare.D1Database,
  date : String,
  sleep : @core.Any,
  raw : @core.Any
) -> Unit {
  let duration_ms = safe_int(sleep._get("duration"))
  let duration_minutes = duration_ms / 60000
  let query = "INSERT INTO sleep_data (date, start_time, end_time, duration_minutes, efficiency, deep_minutes, light_minutes, rem_minutes, wake_minutes, raw_data) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?) ON CONFLICT(date) DO UPDATE SET start_time = excluded.start_time, end_time = excluded.end_time, duration_minutes = excluded.duration_minutes, efficiency = excluded.efficiency, deep_minutes = excluded.deep_minutes, light_minutes = excluded.light_minutes, rem_minutes = excluded.rem_minutes, wake_minutes = excluded.wake_minutes, raw_data = excluded.raw_data"
  db.prepare(query)
    .bind([
      @core.any(date),
      sleep._get("startTime"),
      sleep._get("endTime"),
      @core.any(duration_minutes),
      sleep._get("efficiency"),
      sleep._get("deep"),
      sleep._get("light"),
      sleep._get("rem"),
      sleep._get("wake"),
      @core.any(json_stringify(raw)),
    ])
    .run()
  |> ignore
}

///|
/// Save heart rate data to D1
async fn save_heart_data(
  db : @cloudflare.D1Database,
  date : String,
  heart : @core.Any,
  raw : @core.Any
) -> Unit {
  let query = "INSERT INTO heart_rate (date, resting_heart_rate, out_of_range_minutes, fat_burn_minutes, cardio_minutes, peak_minutes, raw_data) VALUES (?, ?, ?, ?, ?, ?, ?) ON CONFLICT(date) DO UPDATE SET resting_heart_rate = excluded.resting_heart_rate, out_of_range_minutes = excluded.out_of_range_minutes, fat_burn_minutes = excluded.fat_burn_minutes, cardio_minutes = excluded.cardio_minutes, peak_minutes = excluded.peak_minutes, raw_data = excluded.raw_data"
  db.prepare(query)
    .bind([
      @core.any(date),
      heart._get("restingHeartRate"),
      heart._get("outOfRange"),
      heart._get("fatBurn"),
      heart._get("cardio"),
      heart._get("peak"),
      @core.any(json_stringify(raw)),
    ])
    .run()
  |> ignore
}

///|
/// Save weight data to D1
async fn save_weight_data(db : @cloudflare.D1Database, raw : @core.Any) -> Unit {
  let weights = to_array(raw._get("weight"))
  for w in weights {
    let query = "INSERT INTO weight_data (date, weight, bmi, fat_percent, raw_data) VALUES (?, ?, ?, ?, ?) ON CONFLICT(date) DO UPDATE SET weight = excluded.weight, bmi = excluded.bmi, fat_percent = excluded.fat_percent, raw_data = excluded.raw_data"
    db.prepare(query)
      .bind([
        w._get("date"),
        w._get("weight"),
        w._get("bmi"),
        w._get("fat"),
        @core.any(json_stringify(w)),
      ])
      .run()
    |> ignore
  }
}

///|
/// Save VO2max data to D1 and return the value
async fn save_vo2max_data(db : @cloudflare.D1Database, raw : @core.Any) -> String? {
  let cardio_scores = to_array(raw._get("cardioScore"))
  if cardio_scores.length() > 0 {
    let score = cardio_scores[0]
    let date_time = safe_string(score._get("dateTime"))
    let value_obj = score._get("value")
    let vo2max = safe_string(value_obj._get("vo2Max"))
    let query = "INSERT INTO vo2max_data (date, vo2max, raw_data) VALUES (?, ?, ?) ON CONFLICT(date) DO UPDATE SET vo2max = excluded.vo2max, raw_data = excluded.raw_data"
    db.prepare(query)
      .bind([
        @core.any(date_time),
        @core.any(vo2max),
        @core.any(json_stringify(raw)),
      ])
      .run()
    |> ignore
    Some(vo2max)
  } else {
    None
  }
}

///|
/// Save SpO2 data to D1 and return the avg value
async fn save_spo2_data(db : @cloudflare.D1Database, raw : @core.Any) -> Double? {
  let value_obj = raw._get("value")
  if is_null(value_obj) {
    return None
  }
  let date_time = safe_string(raw._get("dateTime"))
  let avg = safe_double(value_obj._get("avg"))
  let min = safe_double(value_obj._get("min"))
  let max = safe_double(value_obj._get("max"))
  let query = "INSERT INTO spo2_data (date, avg, min, max, raw_data) VALUES (?, ?, ?, ?, ?) ON CONFLICT(date) DO UPDATE SET avg = excluded.avg, min = excluded.min, max = excluded.max, raw_data = excluded.raw_data"
  db.prepare(query)
    .bind([
      @core.any(date_time),
      @core.any(avg),
      @core.any(min),
      @core.any(max),
      @core.any(json_stringify(raw)),
    ])
    .run()
  |> ignore
  Some(avg)
}
