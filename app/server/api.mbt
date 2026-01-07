///| MCP API Routes - JSON API endpoints for AI consumption
///| These endpoints provide Fitbit health data for MCP clients

// =============================================================================
// MCP Data Fetchers (D1 Database)
// =============================================================================

///| Get daily summaries for health endpoint
pub extern "js" fn mcp_get_health_summaries(days : Int) -> @core.Promise[@core.Any] =
  #| async (days) => {
  #|   const db = globalThis.__D1_DB;
  #|   if (!db) throw new Error('D1 database not initialized');
  #|   const r = await db.prepare("SELECT * FROM daily_summary ORDER BY date DESC LIMIT ?").bind(days).all();
  #|   return r.results;
  #| }

///| Get activity data for MCP
pub extern "js" fn mcp_get_activity(days : Int) -> @core.Promise[@core.Any] =
  #| async (days) => {
  #|   const db = globalThis.__D1_DB;
  #|   if (!db) throw new Error('D1 database not initialized');
  #|   const r = await db.prepare("SELECT * FROM daily_activity ORDER BY date DESC LIMIT ?").bind(days).all();
  #|   return r.results;
  #| }

///| Get sleep data for MCP
pub extern "js" fn mcp_get_sleep(days : Int) -> @core.Promise[@core.Any] =
  #| async (days) => {
  #|   const db = globalThis.__D1_DB;
  #|   if (!db) throw new Error('D1 database not initialized');
  #|   const r = await db.prepare("SELECT * FROM sleep_data ORDER BY date DESC LIMIT ?").bind(days).all();
  #|   return r.results;
  #| }

///| Get heart rate data for MCP
pub extern "js" fn mcp_get_heartrate(days : Int) -> @core.Promise[@core.Any] =
  #| async (days) => {
  #|   const db = globalThis.__D1_DB;
  #|   if (!db) throw new Error('D1 database not initialized');
  #|   const r = await db.prepare("SELECT * FROM heart_rate ORDER BY date DESC LIMIT ?").bind(days).all();
  #|   return r.results;
  #| }

///| Get weight data for MCP
pub extern "js" fn mcp_get_weight(days : Int) -> @core.Promise[@core.Any] =
  #| async (days) => {
  #|   const db = globalThis.__D1_DB;
  #|   if (!db) throw new Error('D1 database not initialized');
  #|   const r = await db.prepare("SELECT * FROM weight_data ORDER BY date DESC LIMIT ?").bind(days).all();
  #|   return r.results;
  #| }

// =============================================================================
// Helper Functions
// =============================================================================

///| Get today's date as YYYY-MM-DD
pub extern "js" fn get_today_date() -> String =
  #| () => new Date().toISOString().split('T')[0]

///| Parse days parameter from query string (default value if not present)
pub fn parse_days_param(props : @router.PageProps, default_days : Int) -> Int {
  match props.get_query("days") {
    Some(d) => {
      match @global.parseInt(d) {
        Some(n) => n
        None => default_days
      }
    }
    None => default_days
  }
}

///| Build JSON response for MCP endpoints
pub extern "js" fn build_mcp_response(
  success : Bool,
  data : @core.Any,
  days : Int,
  end_date : String,
) -> @core.Any =
  #| (success, data, days, endDate) => ({
  #|   success,
  #|   data,
  #|   period: { days, end_date: endDate }
  #| })

///| Build MCP tools list response
pub extern "js" fn build_tools_response() -> @core.Any =
  #| () => ({
  #|   tools: [
  #|     {
  #|       name: 'get_health_summary',
  #|       description: 'Get daily health summary including steps, calories, sleep, and heart rate',
  #|       parameters: {
  #|         type: 'object',
  #|         properties: {
  #|           days: { type: 'number', description: 'Number of days to retrieve (default: 7)' }
  #|         }
  #|       }
  #|     },
  #|     {
  #|       name: 'get_activity_data',
  #|       description: 'Get detailed activity data including steps, distance, and active minutes',
  #|       parameters: {
  #|         type: 'object',
  #|         properties: {
  #|           days: { type: 'number', description: 'Number of days to retrieve (default: 7)' }
  #|         }
  #|       }
  #|     },
  #|     {
  #|       name: 'get_sleep_data',
  #|       description: 'Get sleep data including duration, efficiency, and sleep stages',
  #|       parameters: {
  #|         type: 'object',
  #|         properties: {
  #|           days: { type: 'number', description: 'Number of days to retrieve (default: 7)' }
  #|         }
  #|       }
  #|     },
  #|     {
  #|       name: 'get_heartrate_data',
  #|       description: 'Get heart rate data including resting HR and zone minutes',
  #|       parameters: {
  #|         type: 'object',
  #|         properties: {
  #|           days: { type: 'number', description: 'Number of days to retrieve (default: 7)' }
  #|         }
  #|       }
  #|     },
  #|     {
  #|       name: 'get_weight_data',
  #|       description: 'Get weight and body composition data',
  #|       parameters: {
  #|         type: 'object',
  #|         properties: {
  #|           days: { type: 'number', description: 'Number of days to retrieve (default: 30)' }
  #|         }
  #|       }
  #|     }
  #|   ]
  #| })

// =============================================================================
// MCP API Route Handlers
// =============================================================================

///| GET /mcp/tools - List available MCP tools
pub async fn mcp_tools_handler(_props : @router.PageProps) -> @core.Any {
  build_tools_response()
}

///| GET /mcp/health - Get health summary data
pub async fn mcp_health_handler(props : @router.PageProps) -> @core.Any {
  let days = parse_days_param(props, 7)
  let summaries = mcp_get_health_summaries(days).wait()
  let end_date = get_today_date()
  build_mcp_response(true, summaries, days, end_date)
}

///| GET /mcp/activity - Get activity data
pub async fn mcp_activity_handler(props : @router.PageProps) -> @core.Any {
  let days = parse_days_param(props, 7)
  let activities = mcp_get_activity(days).wait()
  let end_date = get_today_date()
  build_mcp_response(true, activities, days, end_date)
}

///| GET /mcp/sleep - Get sleep data
pub async fn mcp_sleep_handler(props : @router.PageProps) -> @core.Any {
  let days = parse_days_param(props, 7)
  let sleep_data = mcp_get_sleep(days).wait()
  let end_date = get_today_date()
  build_mcp_response(true, sleep_data, days, end_date)
}

///| GET /mcp/heartrate - Get heart rate data
pub async fn mcp_heartrate_handler(props : @router.PageProps) -> @core.Any {
  let days = parse_days_param(props, 7)
  let heart_rate_data = mcp_get_heartrate(days).wait()
  let end_date = get_today_date()
  build_mcp_response(true, heart_rate_data, days, end_date)
}

///| GET /mcp/weight - Get weight data
pub async fn mcp_weight_handler(props : @router.PageProps) -> @core.Any {
  let days = parse_days_param(props, 30) // Default 30 days for weight
  let weight_data = mcp_get_weight(days).wait()
  let end_date = get_today_date()
  build_mcp_response(true, weight_data, days, end_date)
}

// =============================================================================
// MCP Routes Definition
// =============================================================================

///| MCP API routes (to be included in routes())
pub fn mcp_routes() -> Array[@router.SolRoutes] {
  [
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
  ]
}
