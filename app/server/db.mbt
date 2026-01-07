///| D1 Database FFI Bindings for Cloudflare Workers
///| Fitbit Health Data Access Layer

// =============================================================================
// D1 Database FFI - JavaScript bindings for Cloudflare D1
// =============================================================================

///| Get OAuth token for user
pub extern "js" fn db_get_oauth_token(user_id : String) -> @core.Promise[@core.Any] =
  #| async (userId) => {
  #|   const db = globalThis.__D1_DB;
  #|   if (!db) throw new Error('D1 database not initialized');
  #|   return await db.prepare("SELECT * FROM oauth_tokens WHERE user_id = ?").bind(userId).first();
  #| }

///| Check if user is authenticated
pub extern "js" fn db_is_authenticated() -> @core.Promise[Bool] =
  #| async () => {
  #|   const db = globalThis.__D1_DB;
  #|   if (!db) return false;
  #|   const token = await db.prepare("SELECT * FROM oauth_tokens WHERE user_id = 'default'").first();
  #|   return token != null;
  #| }

///| Get daily summaries for dashboard
pub extern "js" fn db_get_daily_summaries(limit : Int) -> @core.Promise[@core.Any] =
  #| async (limit) => {
  #|   const db = globalThis.__D1_DB;
  #|   if (!db) throw new Error('D1 database not initialized');
  #|   const r = await db.prepare("SELECT * FROM daily_summary ORDER BY date DESC LIMIT ?").bind(limit).all();
  #|   return r.results;
  #| }

///| Get today's summary
pub extern "js" fn db_get_today_summary() -> @core.Promise[@core.Any] =
  #| async () => {
  #|   const db = globalThis.__D1_DB;
  #|   if (!db) throw new Error('D1 database not initialized');
  #|   const today = new Date().toISOString().split('T')[0];
  #|   return await db.prepare("SELECT * FROM daily_summary WHERE date = ?").bind(today).first();
  #| }

///| Get latest activity data
pub extern "js" fn db_get_latest_activity() -> @core.Promise[@core.Any] =
  #| async () => {
  #|   const db = globalThis.__D1_DB;
  #|   if (!db) throw new Error('D1 database not initialized');
  #|   return await db.prepare("SELECT * FROM daily_activity ORDER BY date DESC LIMIT 1").first();
  #| }

///| Get latest sleep data
pub extern "js" fn db_get_latest_sleep() -> @core.Promise[@core.Any] =
  #| async () => {
  #|   const db = globalThis.__D1_DB;
  #|   if (!db) throw new Error('D1 database not initialized');
  #|   return await db.prepare("SELECT * FROM sleep_data ORDER BY date DESC LIMIT 1").first();
  #| }

///| Get latest heart rate data
pub extern "js" fn db_get_latest_heartrate() -> @core.Promise[@core.Any] =
  #| async () => {
  #|   const db = globalThis.__D1_DB;
  #|   if (!db) throw new Error('D1 database not initialized');
  #|   return await db.prepare("SELECT * FROM heart_rate ORDER BY date DESC LIMIT 1").first();
  #| }

///| Get latest weight data
pub extern "js" fn db_get_latest_weight() -> @core.Promise[@core.Any] =
  #| async () => {
  #|   const db = globalThis.__D1_DB;
  #|   if (!db) throw new Error('D1 database not initialized');
  #|   return await db.prepare("SELECT * FROM weight_data ORDER BY date DESC LIMIT 1").first();
  #| }

///| Get OAuth token expiry status
pub extern "js" fn db_get_token_status() -> @core.Promise[@core.Any] =
  #| async () => {
  #|   const db = globalThis.__D1_DB;
  #|   if (!db) return { connected: false };
  #|   const token = await db.prepare("SELECT expires_at, updated_at FROM oauth_tokens WHERE user_id = 'default'").first();
  #|   if (!token) return { connected: false };
  #|   const expiresAt = new Date(token.expires_at);
  #|   const isExpired = expiresAt < new Date();
  #|   return {
  #|     connected: true,
  #|     expired: isExpired,
  #|     lastSync: token.updated_at
  #|   };
  #| }

// =============================================================================
// Data Access Helpers
// =============================================================================

///| Extract string field from JS object
pub extern "js" fn get_str(obj : @core.Any, field : String) -> String =
  #| (obj, field) => obj && obj[field] != null ? String(obj[field]) : ""

///| Extract int field from JS object
pub extern "js" fn get_int(obj : @core.Any, field : String) -> Int =
  #| (obj, field) => obj && obj[field] != null ? Number(obj[field]) : 0

///| Extract float field from JS object
pub extern "js" fn get_float(obj : @core.Any, field : String) -> Double =
  #| (obj, field) => obj && obj[field] != null ? Number(obj[field]) : 0

///| Check if JS value is null/undefined
pub extern "js" fn is_null(obj : @core.Any) -> Bool =
  #| (obj) => obj == null

///| Get array length
pub extern "js" fn array_len(arr : @core.Any) -> Int =
  #| (arr) => Array.isArray(arr) ? arr.length : 0

///| Get array element
pub extern "js" fn array_get(arr : @core.Any, idx : Int) -> @core.Any =
  #| (arr, idx) => arr[idx]

///| Get boolean field from JS object
pub extern "js" fn get_bool(obj : @core.Any, field : String) -> Bool =
  #| (obj, field) => obj && obj[field] === true

///| Format number with commas
pub extern "js" fn format_number(n : Int) -> String =
  #| (n) => n.toLocaleString()

///| Format date to readable string
pub extern "js" fn format_date(date_str : String) -> String =
  #| (dateStr) => {
  #|   if (!dateStr) return '';
  #|   const date = new Date(dateStr);
  #|   return date.toLocaleDateString('ja-JP', { month: 'short', day: 'numeric' });
  #| }

///| Check if date is today
pub extern "js" fn is_today(date_str : String) -> Bool =
  #| (dateStr) => {
  #|   if (!dateStr) return false;
  #|   const today = new Date().toISOString().split('T')[0];
  #|   return dateStr === today;
  #| }

///| Get current timestamp
pub extern "js" fn get_timestamp() -> String =
  #| () => new Date().toISOString()

///| Truncate string to specified length (handles UTF-8 properly)
pub extern "js" fn truncate_str(s : String, max_len : Int) -> String =
  #| (s, maxLen) => s.length <= maxLen ? s : s.slice(0, maxLen)

///| Get float as string with limited decimal places
pub extern "js" fn format_float(n : Double, decimals : Int) -> String =
  #| (n, decimals) => n.toFixed(decimals)
