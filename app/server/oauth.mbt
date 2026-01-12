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
/// Calculate expiry time from expires_in seconds
pub extern "js" fn calculate_expiry(expires_in : Int) -> String =
  #| (expires_in) => {
  #|   return new Date(Date.now() + expires_in * 1000).toISOString();
  #| }

///|
/// Get stored OAuth token from D1
pub async fn get_stored_token(user_id : String) -> @core.Any {
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

///|
/// Get sync state from D1
pub async fn get_sync_state(key : String) -> String? {
  let db = get_db()
  let row = db
    .prepare("SELECT value FROM sync_state WHERE key = ?")
    .bind1(@core.any(key))
    .first()
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
  db.prepare(query)
    .bind2(@core.any(key), @core.any(value))
    .run()
  |> ignore
}

///|
/// Save OAuth tokens to D1
pub async fn save_oauth_token(
  user_id : String,
  access_token : String,
  refresh_token : String,
  expires_at : String,
  scope : String
) -> Unit {
  let db = get_db()
  let query = "INSERT INTO oauth_tokens (user_id, access_token, refresh_token, expires_at, scope) VALUES (?, ?, ?, ?, ?) ON CONFLICT(user_id) DO UPDATE SET access_token = excluded.access_token, refresh_token = excluded.refresh_token, expires_at = excluded.expires_at, scope = excluded.scope"
  db.prepare(query)
    .bind([
      @core.any(user_id),
      @core.any(access_token),
      @core.any(refresh_token),
      @core.any(expires_at),
      @core.any(scope),
    ])
    .run()
  |> ignore
}

///|
/// Update OAuth tokens in D1
pub async fn update_oauth_token(
  user_id : String,
  access_token : String,
  refresh_token : String,
  expires_at : String
) -> Unit {
  let db = get_db()
  let query = "UPDATE oauth_tokens SET access_token = ?, refresh_token = ?, expires_at = ? WHERE user_id = ?"
  db.prepare(query)
    .bind([
      @core.any(access_token),
      @core.any(refresh_token),
      @core.any(expires_at),
      @core.any(user_id),
    ])
    .run()
  |> ignore
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

  // Check if token is expired
  if is_token_expired(expires_at) {
    // Refresh the token
    let new_tokens = refresh_oauth_token(refresh_token)

    if is_null(new_tokens) {
      return (None, Some("Token refresh failed"))
    }

    let new_access = safe_string(new_tokens._get("access_token"))
    let new_refresh = safe_string(new_tokens._get("refresh_token"))
    let expires_in = safe_int(new_tokens._get("expires_in"))
    let new_expires_at = calculate_expiry(expires_in)

    // Update tokens in D1
    update_oauth_token(user_id, new_access, new_refresh, new_expires_at)

    (Some(new_access), None)
  } else {
    (Some(access_token), None)
  }
}
