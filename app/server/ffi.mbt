///|
/// Additional FFI utilities for Fitbit Health Services
/// Provides JavaScript interop functions not covered by db.mbt

///|
/// Get environment variable from globalThis.__ENV
pub extern "js" fn get_env(key : String) -> String =
  #| (key) => {
  #|   const env = globalThis.__ENV;
  #|   if (!env) return '';
  #|   return env[key] || '';
  #| }

///|
/// Create a new URLSearchParams instance
extern "js" fn ffi_new_url_search_params() -> @url.URLSearchParams =
  #| () => new URLSearchParams()

///|
/// Create URLSearchParams and return as wrapper
pub fn new_url_search_params() -> @url.URLSearchParams {
  ffi_new_url_search_params()
}

///|
/// Parse JSON string to Any
pub extern "js" fn json_parse(text : String) -> @core.Any =
  #| (text) => JSON.parse(text)

///|
/// Stringify Any to JSON string
pub extern "js" fn json_stringify(value : @core.Any) -> String =
  #| (value) => JSON.stringify(value)

///|
/// Get current timestamp in JST format
pub extern "js" fn get_current_time_jst() -> String =
  #| () => new Date().toLocaleString('ja-JP', { timeZone: 'Asia/Tokyo' })

///|
/// Get yesterday's date in JST (YYYY-MM-DD format)
pub extern "js" fn get_yesterday_jst() -> String =
  #| () => {
  #|   const now = new Date();
  #|   const jstOffset = 9 * 60 * 60 * 1000;
  #|   const jstNow = new Date(now.getTime() + jstOffset);
  #|   jstNow.setDate(jstNow.getDate() - 1);
  #|   return jstNow.toISOString().split('T')[0];
  #| }

///|
/// Math.floor for Int conversion
pub extern "js" fn math_floor(n : Double) -> Int =
  #| (n) => Math.floor(n)

///|
/// Safe string extraction from Any (for direct value, not object field)
pub fn safe_string(value : @core.Any) -> String {
  if @core.is_nullish(value) {
    ""
  } else {
    value.cast()
  }
}

///|
/// Safe int extraction from Any (for direct value, not object field)
pub fn safe_int(value : @core.Any) -> Int {
  if @core.is_nullish(value) {
    0
  } else {
    value.cast()
  }
}

///|
/// Safe double extraction from Any (for direct value, not object field)
pub fn safe_double(value : @core.Any) -> Double {
  if @core.is_nullish(value) {
    0.0
  } else {
    value.cast()
  }
}

///|
/// Safe bool extraction from Any (for direct value, not object field)
pub fn safe_bool(value : @core.Any) -> Bool {
  if @core.is_nullish(value) {
    false
  } else {
    value.cast()
  }
}

///|
/// Get optional string field (returns None if null)
pub fn get_str_opt(obj : @core.Any, field : String) -> String? {
  if @core.is_nullish(obj) {
    return None
  }
  let val = obj._get(field)
  if @core.is_nullish(val) {
    None
  } else {
    Some(val.to_string())
  }
}

///|
/// Get optional int field (returns None if null)
pub fn get_int_opt(obj : @core.Any, field : String) -> Int? {
  if @core.is_nullish(obj) {
    return None
  }
  let val = obj._get(field)
  if @core.is_nullish(val) {
    None
  } else {
    Some(val.cast())
  }
}

///|
/// Get optional double field (returns None if null)
pub fn get_float_opt(obj : @core.Any, field : String) -> Double? {
  if @core.is_nullish(obj) {
    return None
  }
  let val = obj._get(field)
  if @core.is_nullish(val) {
    None
  } else {
    Some(val.cast())
  }
}

///|
/// Convert Any to array for iteration
pub fn to_array(arr : @core.Any) -> Array[@core.Any] {
  if @core.is_nullish(arr) {
    return []
  }
  @core.array_from(arr)
}

///|
/// Console log for strings
pub extern "js" fn console_log(msg : String) -> Unit =
  #| (msg) => console.log(msg)
