///|
/// OAuth Token Management for Fitbit API
/// Handles token validation and expiration checks

///|
/// Check if a datetime string is expired
pub extern "js" fn is_token_expired(expires_at : String) -> Bool =
  #| (expires_at) => {
  #|   if (!expires_at) return true;
  #|   return new Date(expires_at) < new Date();
  #| }

///|
/// Get remaining hours until token expires (returns -1 if expired or invalid)
pub extern "js" fn get_token_expires_in_hours(expires_at : String) -> Int =
  #| (expires_at) => {
  #|   if (!expires_at) return -1;
  #|   const expiresDate = new Date(expires_at);
  #|   const now = new Date();
  #|   const diffMs = expiresDate - now;
  #|   if (diffMs <= 0) return -1;
  #|   return Math.floor(diffMs / (1000 * 60 * 60));
  #| }

///|
/// Calculate expiry time from expires_in seconds
pub extern "js" fn calculate_expiry(expires_in : Int) -> String =
  #| (expires_in) => {
  #|   return new Date(Date.now() + expires_in * 1000).toISOString();
  #| }

///|
/// Get stored OAuth token from D1
pub async fn get_stored_token(user_id : String) -> @core.Any {
  let db = get_db()
  let row = d1_first(db, "SELECT * FROM oauth_tokens WHERE user_id = ?", [
    @core.any(user_id),
  ])
  match row {
    Some(r) => r
    None => @core.null()
  }
}

///|
/// Get sync state from D1
pub async fn get_sync_state(key : String) -> String? {
  let db = get_db()
  let row = d1_first(db, "SELECT value FROM sync_state WHERE key = ?", [
    @core.any(key),
  ])
  match row {
    Some(r) => {
      let val = r._get("value")
      if is_null(val) {
        None
      } else {
        Some(val.to_string())
      }
    }
    None => None
  }
}

///|
/// Set sync state in D1
pub async fn set_sync_state(key : String, value : String) -> Unit {
  let db = get_db()
  let query = "INSERT INTO sync_state (key, value, updated_at) VALUES (?, ?, datetime('now')) ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at"
  d1_run(db, query, [@core.any(key), @core.any(value)])
}

///|
/// Save OAuth tokens to D1
pub async fn save_oauth_token(
  user_id : String,
  access_token : String,
  refresh_token : String,
  expires_at : String,
  scope : String,
) -> Unit {
  let db = get_db()
  let query = "INSERT INTO oauth_tokens (user_id, access_token, refresh_token, expires_at, scope) VALUES (?, ?, ?, ?, ?) ON CONFLICT(user_id) DO UPDATE SET access_token = excluded.access_token, refresh_token = excluded.refresh_token, expires_at = excluded.expires_at, scope = excluded.scope"
  d1_run(db, query, [
    @core.any(user_id),
    @core.any(access_token),
    @core.any(refresh_token),
    @core.any(expires_at),
    @core.any(scope),
  ])
}

///|
/// Update OAuth tokens in D1
pub async fn update_oauth_token(
  user_id : String,
  access_token : String,
  refresh_token : String,
  expires_at : String,
) -> Unit {
  let db = get_db()
  let query = "UPDATE oauth_tokens SET access_token = ?, refresh_token = ?, expires_at = ? WHERE user_id = ?"
  d1_run(db, query, [
    @core.any(access_token),
    @core.any(refresh_token),
    @core.any(expires_at),
    @core.any(user_id),
  ])
}

///|
/// Maximum retry attempts for token refresh
let max_refresh_retries : Int = 3

///|
/// Hours threshold for early warning notification
let early_warning_hours : Int = 1

///|
/// Refresh token with retry mechanism
/// Returns new tokens or null if all retries failed
async fn refresh_oauth_token_with_retry(refresh_token : String) -> @core.Any {
  let mut attempt = 0
  let mut last_error = ""
  while attempt < max_refresh_retries {
    attempt = attempt + 1
    @console.info(
      @core.any(
        "Token refresh attempt " +
        attempt.to_string() +
        "/" +
        max_refresh_retries.to_string(),
      ),
    )
    let result = refresh_oauth_token(refresh_token)
    if !is_null(result) {
      // Check if result contains access_token (success)
      let access_token = result._get("access_token")
      if !is_null(access_token) {
        @console.info(
          @core.any("Token refresh succeeded on attempt " + attempt.to_string()),
        )
        return result
      }
      // Check for error in response
      let error = result._get("error")
      if !is_null(error) {
        last_error = safe_string(error)
      }
    }
  }
  // All retries failed - notify via Slack
  let error_msg = if last_error == "" {
    "Unknown error after " + max_refresh_retries.to_string() + " attempts"
  } else {
    last_error + " (after " + max_refresh_retries.to_string() + " attempts)"
  }
  @console.error(@core.any("Token refresh failed: " + error_msg))
  post_error_to_slack(
    "Fitbit OAuth トークンの更新に失敗しました: " + error_msg,
    Some(
      "再認証が必要です: https://fitbit-private-mcp.kazu-san.workers.dev/",
    ),
  )
  |> ignore
  @core.null()
}

///|
/// Get valid access token, refreshing if expired
/// Returns (access_token, error_message)
pub async fn get_valid_access_token(user_id : String) -> (String?, String?) {
  let token_data = get_stored_token(user_id)
  if is_null(token_data) {
    return (None, Some("Not authenticated"))
  }
  let access_token = safe_string(token_data._get("access_token"))
  let refresh_token = safe_string(token_data._get("refresh_token"))
  let expires_at = safe_string(token_data._get("expires_at"))

  // Check remaining time and warn if close to expiry
  let hours_remaining = get_token_expires_in_hours(expires_at)
  if hours_remaining >= 0 && hours_remaining <= early_warning_hours {
    @console.warn(
      @core.any(
        "Token expires in " +
        hours_remaining.to_string() +
        " hours, refreshing proactively",
      ),
    )
  }

  // Check if token is expired or close to expiry (proactive refresh)
  if is_token_expired(expires_at) ||
    (hours_remaining >= 0 && hours_remaining <= early_warning_hours) {
    // Refresh the token with retry mechanism
    let new_tokens = refresh_oauth_token_with_retry(refresh_token)
    if is_null(new_tokens) {
      return (None, Some("Token refresh failed after retries"))
    }
    let new_access = safe_string(new_tokens._get("access_token"))
    let new_refresh = safe_string(new_tokens._get("refresh_token"))
    let expires_in = safe_int(new_tokens._get("expires_in"))
    let new_expires_at = calculate_expiry(expires_in)

    // Update tokens in D1
    update_oauth_token(user_id, new_access, new_refresh, new_expires_at)
    @console.info(
      @core.any("Token refreshed successfully, new expiry: " + new_expires_at),
    )
    (Some(new_access), None)
  } else {
    (Some(access_token), None)
  }
}
