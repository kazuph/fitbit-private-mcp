///| MCP API Routes - JSON API endpoints for AI consumption

///| These endpoints provide Fitbit health data for MCP clients

// =============================================================================
// MCP Data Fetchers (Using mizchi/cloudflare D1 API)
// =============================================================================

///|
/// Get daily summaries for health endpoint
pub async fn mcp_get_health_summaries(days : Int) -> @core.Any {
  let db = get_db()
  d1_all(db, "SELECT * FROM daily_summary ORDER BY date DESC LIMIT ?", [
    @core.any(days),
  ])
}

///|
/// Get activity data for MCP
pub async fn mcp_get_activity(days : Int) -> @core.Any {
  let db = get_db()
  d1_all(db, "SELECT * FROM daily_activity ORDER BY date DESC LIMIT ?", [
    @core.any(days),
  ])
}

///|
/// Get sleep data for MCP
pub async fn mcp_get_sleep(days : Int) -> @core.Any {
  let db = get_db()
  d1_all(db, "SELECT * FROM sleep_data ORDER BY date DESC LIMIT ?", [
    @core.any(days),
  ])
}

///|
/// Get heart rate data for MCP
pub async fn mcp_get_heartrate(days : Int) -> @core.Any {
  let db = get_db()
  d1_all(db, "SELECT * FROM heart_rate ORDER BY date DESC LIMIT ?", [
    @core.any(days),
  ])
}

///|
/// Get weight data for MCP
pub async fn mcp_get_weight(days : Int) -> @core.Any {
  let db = get_db()
  d1_all(db, "SELECT * FROM weight_data ORDER BY date DESC LIMIT ?", [
    @core.any(days),
  ])
}

///|
/// Get VO2max data for MCP
pub async fn mcp_get_vo2max(days : Int) -> @core.Any {
  let db = get_db()
  d1_all(db, "SELECT * FROM vo2max_data ORDER BY date DESC LIMIT ?", [
    @core.any(days),
  ])
}

///|
/// Get SpO2 data for MCP
pub async fn mcp_get_spo2(days : Int) -> @core.Any {
  let db = get_db()
  d1_all(db, "SELECT * FROM spo2_data ORDER BY date DESC LIMIT ?", [
    @core.any(days),
  ])
}

// =============================================================================
// Helper Functions
// =============================================================================

///|
/// Parse days parameter from query string (default value if not present)
pub fn parse_days_param(props : @router.PageProps, default_days : Int) -> Int {
  match props.get_query("days") {
    Some(d) =>
      match @global.parseInt(d) {
        Some(n) => n
        None => default_days
      }
    None => default_days
  }
}

///|
/// Build JSON response for MCP endpoints - MoonBit native
pub fn build_mcp_response(
  success : Bool,
  data_key : String,
  data : @core.Any,
  days : Int,
  end_date : String,
) -> Json raise {
  let period = @core.new_object()
  period._set("days", @core.any(days))
  period._set("end_date", @core.any(end_date))
  let response_data = @core.new_object()
  response_data._set(data_key, data)
  response_data._set("period", period)
  let result = @core.new_object()
  result._set("success", @core.any(success))
  result._set("data", response_data)
  @json.parse(json_stringify(result).view())
}

///|
/// Get the current UTC hour for the scheduled daily report.
extern "js" fn get_utc_hour() -> Int =
  #| () => new Date().getUTCHours()

///|
/// Run Fitbit synchronization from inside Sol's MoonBit async runtime.
async fn sync_today() -> (Bool, String?) {
  let (token, error) = get_valid_access_token("default")
  match token {
    None => (false, error)
    Some(access_token) => {
      let date = get_today_jst()
      let (vo2max, spo2) = sync_health_data(access_token, date)
      update_daily_summary(date, vo2max, spo2)
      (true, None)
    }
  }
}

///|
/// Internal endpoint for the dashboard's manual synchronization action.
async fn internal_sync_handler(_props : @router.PageProps) -> Json {
  let (synced, error) = sync_today()
  let result = @core.new_object()
  result._set("success", @core.any(synced))
  result._set("date", @core.any(get_today_jst()))
  match error {
    Some(message) => result._set("error", @core.any(message))
    None => ()
  }
  @json.parse(json_stringify(result).view())
}

///|
/// Internal endpoint that exchanges an OAuth code and persists the token in D1.
async fn internal_oauth_handler(props : @router.PageProps) -> Json {
  let result = @core.new_object()
  match props.get_query("code") {
    None => {
      result._set("success", @core.any(false))
      result._set("error", @core.any("Missing authorization code"))
    }
    Some(code) => {
      let tokens = exchange_auth_code(code, get_env("FITBIT_REDIRECT_URI"))
      if is_null(tokens) {
        result._set("success", @core.any(false))
        result._set("error", @core.any("Token exchange failed"))
      } else {
        save_oauth_token(
          "default",
          safe_string(tokens._get("access_token")),
          safe_string(tokens._get("refresh_token")),
          calculate_expiry(safe_int(tokens._get("expires_in"))),
          safe_string(tokens._get("scope")),
        )
        result._set("success", @core.any(true))
      }
    }
  }
  @json.parse(json_stringify(result).view())
}

///|
/// Internal endpoint for the dashboard's Slack connectivity check.
async fn internal_test_slack_handler(_props : @router.PageProps) -> Json {
  let result = @core.new_object()
  result._set("success", @core.any(post_to_slack("🧪 Slack test")))
  @json.parse(json_stringify(result).view())
}

///|
/// Internal endpoint for manually sending the daily health report.
async fn internal_test_report_handler(_props : @router.PageProps) -> Json {
  post_daily_health_report()
  let result = @core.new_object()
  result._set("success", @core.any(true))
  @json.parse(json_stringify(result).view())
}

///|
/// Internal endpoint for reporting Worker orchestration failures to Slack.
async fn internal_error_handler(props : @router.PageProps) -> Json {
  let message = match props.get_query("message") {
    Some(value) => value
    None => "Unknown Worker error"
  }
  let context = props.get_query("context")
  let result = @core.new_object()
  result._set("success", @core.any(post_error_to_slack(message, context)))
  @json.parse(json_stringify(result).view())
}

///|
/// Internal cron endpoint used by both manual and scheduled Worker handlers.
async fn internal_cron_handler(_props : @router.PageProps) -> Json {
  let (synced, _) = sync_today()
  let report_queued = get_utc_hour() == 22
  if report_queued {
    post_daily_health_report()
  }
  let result = @core.new_object()
  result._set("success", @core.any(true))
  result._set("synced", @core.any(synced))
  result._set("reportQueued", @core.any(report_queued))
  @json.parse(json_stringify(result).view())
}

///|
/// Build MCP tools list response - MoonBit native
pub fn build_tools_response() -> Json raise {
  let tools = @core.new_array()

  // Tool 1: get_health_summary
  let tool1 = @core.new_object()
  tool1._set("name", @core.any("get_health_summary"))
  tool1._set(
    "description",
    @core.any(
      "Get daily health summary including steps, calories, sleep, and heart rate",
    ),
  )
  let params1 = @core.new_object()
  params1._set("type", @core.any("object"))
  let props1 = @core.new_object()
  let days_prop = @core.new_object()
  days_prop._set("type", @core.any("number"))
  days_prop._set(
    "description",
    @core.any("Number of days to retrieve (default: 7)"),
  )
  props1._set("days", days_prop)
  params1._set("properties", props1)
  tool1._set("parameters", params1)
  @core.any(tools)._call("push", [tool1]) |> ignore

  // Tool 2: get_activity_data
  let tool2 = @core.new_object()
  tool2._set("name", @core.any("get_activity_data"))
  tool2._set(
    "description",
    @core.any(
      "Get detailed activity data including steps, distance, and active minutes",
    ),
  )
  let params2 = @core.new_object()
  params2._set("type", @core.any("object"))
  let props2 = @core.new_object()
  let days_prop2 = @core.new_object()
  days_prop2._set("type", @core.any("number"))
  days_prop2._set(
    "description",
    @core.any("Number of days to retrieve (default: 7)"),
  )
  props2._set("days", days_prop2)
  params2._set("properties", props2)
  tool2._set("parameters", params2)
  @core.any(tools)._call("push", [tool2]) |> ignore

  // Tool 3: get_sleep_data
  let tool3 = @core.new_object()
  tool3._set("name", @core.any("get_sleep_data"))
  tool3._set(
    "description",
    @core.any("Get sleep data including duration, efficiency, and sleep stages"),
  )
  let params3 = @core.new_object()
  params3._set("type", @core.any("object"))
  let props3 = @core.new_object()
  let days_prop3 = @core.new_object()
  days_prop3._set("type", @core.any("number"))
  days_prop3._set(
    "description",
    @core.any("Number of days to retrieve (default: 7)"),
  )
  props3._set("days", days_prop3)
  params3._set("properties", props3)
  tool3._set("parameters", params3)
  @core.any(tools)._call("push", [tool3]) |> ignore

  // Tool 4: get_heartrate_data
  let tool4 = @core.new_object()
  tool4._set("name", @core.any("get_heartrate_data"))
  tool4._set(
    "description",
    @core.any("Get heart rate data including resting HR and zone minutes"),
  )
  let params4 = @core.new_object()
  params4._set("type", @core.any("object"))
  let props4 = @core.new_object()
  let days_prop4 = @core.new_object()
  days_prop4._set("type", @core.any("number"))
  days_prop4._set(
    "description",
    @core.any("Number of days to retrieve (default: 7)"),
  )
  props4._set("days", days_prop4)
  params4._set("properties", props4)
  tool4._set("parameters", params4)
  @core.any(tools)._call("push", [tool4]) |> ignore

  // Tool 5: get_weight_data
  let tool5 = @core.new_object()
  tool5._set("name", @core.any("get_weight_data"))
  tool5._set("description", @core.any("Get weight and body composition data"))
  let params5 = @core.new_object()
  params5._set("type", @core.any("object"))
  let props5 = @core.new_object()
  let days_prop5 = @core.new_object()
  days_prop5._set("type", @core.any("number"))
  days_prop5._set(
    "description",
    @core.any("Number of days to retrieve (default: 30)"),
  )
  props5._set("days", days_prop5)
  params5._set("properties", props5)
  tool5._set("parameters", params5)
  @core.any(tools)._call("push", [tool5]) |> ignore

  // Tool 6: get_vo2max_data
  let tool6 = @core.new_object()
  tool6._set("name", @core.any("get_vo2max_data"))
  tool6._set(
    "description",
    @core.any(
      "Get VO2max (cardio fitness score) data - measures cardiovascular fitness",
    ),
  )
  let params6 = @core.new_object()
  params6._set("type", @core.any("object"))
  let props6 = @core.new_object()
  let days_prop6 = @core.new_object()
  days_prop6._set("type", @core.any("number"))
  days_prop6._set(
    "description",
    @core.any("Number of days to retrieve (default: 30)"),
  )
  props6._set("days", days_prop6)
  params6._set("properties", props6)
  tool6._set("parameters", params6)
  @core.any(tools)._call("push", [tool6]) |> ignore

  // Tool 7: get_spo2_data
  let tool7 = @core.new_object()
  tool7._set("name", @core.any("get_spo2_data"))
  tool7._set(
    "description",
    @core.any("Get SpO2 (blood oxygen saturation) data - measured during sleep"),
  )
  let params7 = @core.new_object()
  params7._set("type", @core.any("object"))
  let props7 = @core.new_object()
  let days_prop7 = @core.new_object()
  days_prop7._set("type", @core.any("number"))
  days_prop7._set(
    "description",
    @core.any("Number of days to retrieve (default: 7)"),
  )
  props7._set("days", days_prop7)
  params7._set("properties", props7)
  tool7._set("parameters", params7)
  @core.any(tools)._call("push", [tool7]) |> ignore
  let result = @core.new_object()
  result._set("tools", @core.any(tools))
  @json.parse(json_stringify(result).view())
}

// =============================================================================
// MCP API Route Handlers
// =============================================================================

///|
/// GET /mcp/tools - List available MCP tools
pub async fn mcp_tools_handler(_props : @router.PageProps) -> Json {
  build_tools_response()
}

///|
/// GET /mcp/health - Get health summary data
pub async fn mcp_health_handler(props : @router.PageProps) -> Json {
  let days = parse_days_param(props, 7)
  let summaries = mcp_get_health_summaries(days)
  let end_date = get_today_jst()
  build_mcp_response(true, "summaries", summaries, days, end_date)
}

///|
/// GET /mcp/activity - Get activity data
pub async fn mcp_activity_handler(props : @router.PageProps) -> Json {
  let days = parse_days_param(props, 7)
  let activities = mcp_get_activity(days)
  let end_date = get_today_jst()
  build_mcp_response(true, "activities", activities, days, end_date)
}

///|
/// GET /mcp/sleep - Get sleep data
pub async fn mcp_sleep_handler(props : @router.PageProps) -> Json {
  let days = parse_days_param(props, 7)
  let sleep_data = mcp_get_sleep(days)
  let end_date = get_today_jst()
  build_mcp_response(true, "sleep_data", sleep_data, days, end_date)
}

///|
/// GET /mcp/heartrate - Get heart rate data
pub async fn mcp_heartrate_handler(props : @router.PageProps) -> Json {
  let days = parse_days_param(props, 7)
  let heart_rate_data = mcp_get_heartrate(days)
  let end_date = get_today_jst()
  build_mcp_response(true, "heart_rate_data", heart_rate_data, days, end_date)
}

///|
/// GET /mcp/weight - Get weight data
pub async fn mcp_weight_handler(props : @router.PageProps) -> Json {
  let days = parse_days_param(props, 30) // Default 30 days for weight
  let weight_data = mcp_get_weight(days)
  let end_date = get_today_jst()
  build_mcp_response(true, "weight_data", weight_data, days, end_date)
}

///|
/// GET /mcp/vo2max - Get VO2max (cardio fitness) data
pub async fn mcp_vo2max_handler(props : @router.PageProps) -> Json {
  let days = parse_days_param(props, 30) // Default 30 days for VO2max
  let vo2max_data = mcp_get_vo2max(days)
  let end_date = get_today_jst()
  build_mcp_response(true, "vo2max_data", vo2max_data, days, end_date)
}

///|
/// GET /mcp/spo2 - Get SpO2 (blood oxygen) data
pub async fn mcp_spo2_handler(props : @router.PageProps) -> Json {
  let days = parse_days_param(props, 7) // Default 7 days for SpO2
  let spo2_data = mcp_get_spo2(days)
  let end_date = get_today_jst()
  build_mcp_response(true, "spo2_data", spo2_data, days, end_date)
}

// =============================================================================
// MCP Routes Definition
// =============================================================================

///|
/// MCP API routes (to be included in routes())
pub fn mcp_routes() -> Array[@router.SolRoutes] {
  [
    @router.SolRoutes::Post(
      path="/__internal/sync",
      handler=@router.ApiHandler(internal_sync_handler),
    ),
    @router.SolRoutes::Post(
      path="/__internal/oauth",
      handler=@router.ApiHandler(internal_oauth_handler),
    ),
    @router.SolRoutes::Post(
      path="/__internal/test-slack",
      handler=@router.ApiHandler(internal_test_slack_handler),
    ),
    @router.SolRoutes::Post(
      path="/__internal/test-report",
      handler=@router.ApiHandler(internal_test_report_handler),
    ),
    @router.SolRoutes::Post(
      path="/__internal/error",
      handler=@router.ApiHandler(internal_error_handler),
    ),
    @router.SolRoutes::Post(
      path="/__internal/cron",
      handler=@router.ApiHandler(internal_cron_handler),
    ),
    @router.SolRoutes::Get(
      path="/mcp/tools",
      handler=@router.ApiHandler(mcp_tools_handler),
    ),
    @router.SolRoutes::Get(
      path="/mcp/health",
      handler=@router.ApiHandler(mcp_health_handler),
    ),
    @router.SolRoutes::Get(
      path="/mcp/activity",
      handler=@router.ApiHandler(mcp_activity_handler),
    ),
    @router.SolRoutes::Get(
      path="/mcp/sleep",
      handler=@router.ApiHandler(mcp_sleep_handler),
    ),
    @router.SolRoutes::Get(
      path="/mcp/heartrate",
      handler=@router.ApiHandler(mcp_heartrate_handler),
    ),
    @router.SolRoutes::Get(
      path="/mcp/weight",
      handler=@router.ApiHandler(mcp_weight_handler),
    ),
    @router.SolRoutes::Get(
      path="/mcp/vo2max",
      handler=@router.ApiHandler(mcp_vo2max_handler),
    ),
    @router.SolRoutes::Get(
      path="/mcp/spo2",
      handler=@router.ApiHandler(mcp_spo2_handler),
    ),
  ]
}
