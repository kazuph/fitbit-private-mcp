///| OAuth Logic - MoonBit implementation of Fitbit OAuth2 flow
///| Migrated from worker.ts to increase MoonBit ratio

// =============================================================================
// Environment Access (FFI)
// =============================================================================

///| Get environment variable
pub extern "js" fn get_env(key : String) -> String =
  #| (key) => {
  #|   const env = globalThis.__WORKER_ENV || {};
  #|   return env[key] || '';
  #| }

// =============================================================================
// Fitbit OAuth Helpers (FFI)
// =============================================================================

///| Build Fitbit authorization URL
pub fn build_fitbit_auth_url() -> String {
  let client_id = get_env("FITBIT_CLIENT_ID")
  let redirect_uri = get_env("FITBIT_REDIRECT_URI")
  let scope = "activity heartrate sleep weight profile"
  let base_url = "https://www.fitbit.com/oauth2/authorize"
  "\{base_url}?response_type=code&client_id=\{client_id}&redirect_uri=\{redirect_uri}&scope=\{scope}"
}

///| Exchange authorization code for tokens
pub extern "js" fn exchange_code_for_tokens(code : String) -> @core.Promise[@core.Any] =
  #| async (code) => {
  #|   const env = globalThis.__WORKER_ENV || {};
  #|   const clientId = env.FITBIT_CLIENT_ID;
  #|   const clientSecret = env.FITBIT_CLIENT_SECRET;
  #|   const redirectUri = env.FITBIT_REDIRECT_URI;
  #|
  #|   const basicAuth = btoa(`${clientId}:${clientSecret}`);
  #|   const response = await fetch('https://api.fitbit.com/oauth2/token', {
  #|     method: 'POST',
  #|     headers: {
  #|       'Authorization': `Basic ${basicAuth}`,
  #|       'Content-Type': 'application/x-www-form-urlencoded',
  #|     },
  #|     body: new URLSearchParams({
  #|       grant_type: 'authorization_code',
  #|       code: code,
  #|       redirect_uri: redirectUri,
  #|     }),
  #|   });
  #|
  #|   if (!response.ok) {
  #|     const errorText = await response.text();
  #|     throw new Error(`Token exchange failed: ${errorText}`);
  #|   }
  #|
  #|   return response.json();
  #| }

///| Store OAuth tokens in D1 database
pub extern "js" fn store_oauth_tokens(
  access_token : String,
  refresh_token : String,
  expires_in : Int,
  scope : String
) -> @core.Promise[Bool] =
  #| async (accessToken, refreshToken, expiresIn, scope) => {
  #|   const db = globalThis.__D1_DB;
  #|   if (!db) throw new Error('D1 database not initialized');
  #|
  #|   const expiresAt = new Date(Date.now() + expiresIn * 1000).toISOString();
  #|
  #|   await db.prepare(`
  #|     INSERT INTO oauth_tokens (user_id, access_token, refresh_token, expires_at, scope)
  #|     VALUES (?, ?, ?, ?, ?)
  #|     ON CONFLICT(user_id) DO UPDATE SET
  #|       access_token = excluded.access_token,
  #|       refresh_token = excluded.refresh_token,
  #|       expires_at = excluded.expires_at,
  #|       scope = excluded.scope
  #|   `).bind('default', accessToken, refreshToken, expiresAt, scope).run();
  #|
  #|   return true;
  #| }

///| Get stored OAuth tokens
pub extern "js" fn get_stored_tokens() -> @core.Promise[@core.Any] =
  #| async () => {
  #|   const db = globalThis.__D1_DB;
  #|   if (!db) return null;
  #|   return db.prepare('SELECT * FROM oauth_tokens WHERE user_id = ?').bind('default').first();
  #| }

///| Refresh OAuth tokens
pub extern "js" fn refresh_oauth_tokens(refresh_token : String) -> @core.Promise[@core.Any] =
  #| async (refreshToken) => {
  #|   const env = globalThis.__WORKER_ENV || {};
  #|   const clientId = env.FITBIT_CLIENT_ID;
  #|   const clientSecret = env.FITBIT_CLIENT_SECRET;
  #|
  #|   const basicAuth = btoa(`${clientId}:${clientSecret}`);
  #|   const response = await fetch('https://api.fitbit.com/oauth2/token', {
  #|     method: 'POST',
  #|     headers: {
  #|       'Authorization': `Basic ${basicAuth}`,
  #|       'Content-Type': 'application/x-www-form-urlencoded',
  #|     },
  #|     body: new URLSearchParams({
  #|       grant_type: 'refresh_token',
  #|       refresh_token: refreshToken,
  #|     }),
  #|   });
  #|
  #|   if (!response.ok) {
  #|     throw new Error('Token refresh failed');
  #|   }
  #|
  #|   return response.json();
  #| }

///| Update tokens in database after refresh
pub extern "js" fn update_tokens(
  access_token : String,
  refresh_token : String,
  expires_in : Int
) -> @core.Promise[Bool] =
  #| async (accessToken, refreshToken, expiresIn) => {
  #|   const db = globalThis.__D1_DB;
  #|   if (!db) throw new Error('D1 database not initialized');
  #|
  #|   const expiresAt = new Date(Date.now() + expiresIn * 1000).toISOString();
  #|
  #|   await db.prepare(`
  #|     UPDATE oauth_tokens
  #|     SET access_token = ?, refresh_token = ?, expires_at = ?
  #|     WHERE user_id = ?
  #|   `).bind(accessToken, refreshToken, expiresAt, 'default').run();
  #|
  #|   return true;
  #| }

///| Process OAuth callback token response
pub extern "js" fn process_token_response(tokens : @core.Any) -> @core.Any =
  #| (tokens) => ({
  #|   access_token: tokens.access_token,
  #|   refresh_token: tokens.refresh_token,
  #|   expires_in: tokens.expires_in,
  #|   scope: tokens.scope || ''
  #| })

///| Get token field as string
pub extern "js" fn get_token_field_string(tokens : @core.Any, field : String) -> String =
  #| (tokens, field) => tokens[field] || ''

///| Get token field as int
pub extern "js" fn get_token_field_int(tokens : @core.Any, field : String) -> Int =
  #| (tokens, field) => parseInt(tokens[field]) || 0
