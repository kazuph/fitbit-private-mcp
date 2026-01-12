///| D1 Database Access Layer using mizchi/cloudflare package
///| Fitbit Health Data Access with minimal FFI

// =============================================================================
// Single FFI - D1 Database Binding Retrieval
// =============================================================================

///| Get D1 database from globalThis (only FFI needed)
extern "js" fn get_global_db() -> @core.Any =
  #| () => {
  #|   const db = globalThis.__D1_DB;
  #|   if (!db) throw new Error('D1 database not initialized');
  #|   return db;
  #| }

///| Convert JS D1 binding to typed D1Database
fn get_db() -> @cloudflare.D1Database {
  let db_js : @core.Any = get_global_db()
  @core.identity(db_js)
}

// =============================================================================
// D1 Database Access Functions (MoonBit Native)
// =============================================================================

///| Get OAuth token for user
pub async fn db_get_oauth_token(user_id : String) -> @core.Any {
  let db = get_db()
  let row = db
    .prepare("SELECT * FROM oauth_tokens WHERE user_id = ?")
    .bind1(@core.any(user_id))
    .first()
  match row {
    Some(r) => r
    None => @core.null()
  }
}

///| Check if user is authenticated
pub async fn db_is_authenticated() -> Bool {
  let db = get_db()
  let row = db
    .prepare("SELECT * FROM oauth_tokens WHERE user_id = 'default'")
    .first()
  match row {
    Some(_) => true
    None => false
  }
}

///| Get daily summaries for dashboard
pub async fn db_get_daily_summaries(limit : Int) -> @core.Any {
  let db = get_db()
  let result = db
    .prepare("SELECT * FROM daily_summary ORDER BY date DESC LIMIT ?")
    .bind1(@core.any(limit))
    .all()
  result.results_raw()
}

///| Get today's summary
pub async fn db_get_today_summary() -> @core.Any {
  let db = get_db()
  let today = get_today_str()
  let row = db
    .prepare("SELECT * FROM daily_summary WHERE date = ?")
    .bind1(@core.any(today))
    .first()
  match row {
    Some(r) => r
    None => @core.null()
  }
}

///| Get latest activity data
pub async fn db_get_latest_activity() -> @core.Any {
  let db = get_db()
  let row = db
    .prepare("SELECT * FROM daily_activity ORDER BY date DESC LIMIT 1")
    .first()
  match row {
    Some(r) => r
    None => @core.null()
  }
}

///| Get latest sleep data
pub async fn db_get_latest_sleep() -> @core.Any {
  let db = get_db()
  let row = db
    .prepare("SELECT * FROM sleep_data ORDER BY date DESC LIMIT 1")
    .first()
  match row {
    Some(r) => r
    None => @core.null()
  }
}

///| Get latest heart rate data
pub async fn db_get_latest_heartrate() -> @core.Any {
  let db = get_db()
  let row = db
    .prepare("SELECT * FROM heart_rate ORDER BY date DESC LIMIT 1")
    .first()
  match row {
    Some(r) => r
    None => @core.null()
  }
}

///| Get latest weight data
pub async fn db_get_latest_weight() -> @core.Any {
  let db = get_db()
  let row = db
    .prepare("SELECT * FROM weight_data ORDER BY date DESC LIMIT 1")
    .first()
  match row {
    Some(r) => r
    None => @core.null()
  }
}

///| Get latest VO2max data
pub async fn db_get_latest_vo2max() -> @core.Any {
  let db = get_db()
  let row = db
    .prepare("SELECT * FROM vo2max_data ORDER BY date DESC LIMIT 1")
    .first()
  match row {
    Some(r) => r
    None => @core.null()
  }
}

///| Get latest SpO2 data
pub async fn db_get_latest_spo2() -> @core.Any {
  let db = get_db()
  let row = db
    .prepare("SELECT * FROM spo2_data ORDER BY date DESC LIMIT 1")
    .first()
  match row {
    Some(r) => r
    None => @core.null()
  }
}

///| Get OAuth token expiry status
pub async fn db_get_token_status() -> @core.Any {
  let db = get_db()
  let row = db
    .prepare("SELECT expires_at, updated_at FROM oauth_tokens WHERE user_id = 'default'")
    .first()
  match row {
    None => {
      let result = @core.new_object()
      result._set("connected", @core.any(false))
      result
    }
    Some(token) => {
      let expires_at = get_str(token, "expires_at")
      let updated_at = get_str(token, "updated_at")
      let is_expired = is_expired_timestamp(expires_at)
      let result = @core.new_object()
      result._set("connected", @core.any(true))
      result._set("expired", @core.any(is_expired))
      result._set("lastSync", @core.any(updated_at))
      result
    }
  }
}

// =============================================================================
// Data Access Helpers (MoonBit Native - No FFI)
// =============================================================================

///| Extract string field from JS object
pub fn get_str(obj : @core.Any, field : String) -> String {
  if @core.is_nullish(obj) {
    return ""
  }
  let val = obj._get(field)
  if @core.is_nullish(val) {
    ""
  } else {
    val.to_string()
  }
}

///| Extract int field from JS object
pub fn get_int(obj : @core.Any, field : String) -> Int {
  if @core.is_nullish(obj) {
    return 0
  }
  let val = obj._get(field)
  if @core.is_nullish(val) {
    0
  } else {
    val.cast()
  }
}

///| Extract float field from JS object
pub fn get_float(obj : @core.Any, field : String) -> Double {
  if @core.is_nullish(obj) {
    return 0.0
  }
  let val = obj._get(field)
  if @core.is_nullish(val) {
    0.0
  } else {
    val.cast()
  }
}

///| Check if JS value is null/undefined
pub fn is_null(obj : @core.Any) -> Bool {
  @core.is_nullish(obj)
}

///| Get array length
pub fn array_len(arr : @core.Any) -> Int {
  if @core.is_nullish(arr) {
    0
  } else {
    arr._get("length").cast()
  }
}

///| Get array element
pub fn array_get(arr : @core.Any, idx : Int) -> @core.Any {
  arr._get_by_index(idx)
}

///| Get boolean field from JS object
pub fn get_bool(obj : @core.Any, field : String) -> Bool {
  if @core.is_nullish(obj) {
    return false
  }
  let val = obj._get(field)
  if @core.is_nullish(val) {
    false
  } else {
    val.cast()
  }
}

// =============================================================================
// Date/Format Helpers (Minimal FFI for JS Date API)
// =============================================================================

///| Get today's date string (YYYY-MM-DD) - requires FFI for Date API
extern "js" fn get_today_str() -> String =
  #| () => new Date().toISOString().split('T')[0]

///| Get current timestamp (ISO format) - requires FFI for Date API
pub extern "js" fn get_timestamp() -> String =
  #| () => new Date().toISOString()

///| Check if timestamp is expired - requires FFI for Date comparison
extern "js" fn is_expired_timestamp(expires_at : String) -> Bool =
  #| (expiresAt) => {
  #|   if (!expiresAt) return true;
  #|   const expiresDate = new Date(expiresAt);
  #|   return expiresDate < new Date();
  #| }

///| Format number with commas - requires FFI for toLocaleString
pub extern "js" fn format_number(n : Int) -> String =
  #| (n) => n.toLocaleString()

///| Format date to readable string - requires FFI for Date formatting
pub extern "js" fn format_date(date_str : String) -> String =
  #| (dateStr) => {
  #|   if (!dateStr) return '';
  #|   const date = new Date(dateStr);
  #|   return date.toLocaleDateString('ja-JP', { month: 'short', day: 'numeric' });
  #| }

///| Check if date is today - requires FFI for Date comparison
pub extern "js" fn is_today(date_str : String) -> Bool =
  #| (dateStr) => {
  #|   if (!dateStr) return false;
  #|   const today = new Date().toISOString().split('T')[0];
  #|   return dateStr === today;
  #| }

///| Truncate string to specified length
pub fn truncate_str(s : String, max_len : Int) -> String {
  let chars = s.to_array()
  if chars.length() <= max_len {
    s
  } else {
    let result = StringBuilder::new()
    for i = 0; i < max_len; i = i + 1 {
      result.write_char(chars[i])
    }
    result.to_string()
  }
}

///| Format float with decimals - requires FFI for toFixed
pub extern "js" fn format_float(n : Double, decimals : Int) -> String =
  #| (n, decimals) => n.toFixed(decimals)
