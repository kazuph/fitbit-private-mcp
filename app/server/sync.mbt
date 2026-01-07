///| Data Sync Logic - MoonBit implementation of Fitbit data synchronization
///| Migrated from worker.ts to increase MoonBit ratio

// =============================================================================
// Token Management
// =============================================================================

///| Check if token is expired
pub extern "js" fn is_token_expired(expires_at : String) -> Bool =
  #| (expiresAt) => new Date(expiresAt) < new Date()

///| Get access token from stored tokens
pub extern "js" fn get_access_token(tokens : @core.Any) -> String =
  #| (tokens) => tokens?.access_token || ''

///| Get refresh token from stored tokens
pub extern "js" fn get_refresh_token(tokens : @core.Any) -> String =
  #| (tokens) => tokens?.refresh_token || ''

///| Get expires_at from stored tokens
pub extern "js" fn get_expires_at(tokens : @core.Any) -> String =
  #| (tokens) => tokens?.expires_at || ''

// =============================================================================
// Fitbit API Fetchers (FFI)
// =============================================================================

///| Fetch activity data from Fitbit API
pub extern "js" fn fetch_fitbit_activity(access_token : String, date : String) -> @core.Promise[@core.Any] =
  #| async (accessToken, date) => {
  #|   const response = await fetch(
  #|     `https://api.fitbit.com/1/user/-/activities/date/${date}.json`,
  #|     { headers: { 'Authorization': `Bearer ${accessToken}` } }
  #|   );
  #|   if (!response.ok) return null;
  #|   return response.json();
  #| }

///| Fetch sleep data from Fitbit API
pub extern "js" fn fetch_fitbit_sleep(access_token : String, date : String) -> @core.Promise[@core.Any] =
  #| async (accessToken, date) => {
  #|   const response = await fetch(
  #|     `https://api.fitbit.com/1.2/user/-/sleep/date/${date}.json`,
  #|     { headers: { 'Authorization': `Bearer ${accessToken}` } }
  #|   );
  #|   if (!response.ok) return null;
  #|   return response.json();
  #| }

///| Fetch heart rate data from Fitbit API
pub extern "js" fn fetch_fitbit_heartrate(access_token : String, date : String) -> @core.Promise[@core.Any] =
  #| async (accessToken, date) => {
  #|   const response = await fetch(
  #|     `https://api.fitbit.com/1/user/-/activities/heart/date/${date}/1d.json`,
  #|     { headers: { 'Authorization': `Bearer ${accessToken}` } }
  #|   );
  #|   if (!response.ok) return null;
  #|   return response.json();
  #| }

///| Fetch weight data from Fitbit API (last 30 days)
pub extern "js" fn fetch_fitbit_weight(access_token : String, date : String) -> @core.Promise[@core.Any] =
  #| async (accessToken, date) => {
  #|   const response = await fetch(
  #|     `https://api.fitbit.com/1/user/-/body/log/weight/date/${date}/30d.json`,
  #|     { headers: { 'Authorization': `Bearer ${accessToken}` } }
  #|   );
  #|   if (!response.ok) return null;
  #|   return response.json();
  #| }

// =============================================================================
// Data Storage (FFI)
// =============================================================================

///| Store activity data in D1
pub extern "js" fn store_activity_data(date : String, data : @core.Any) -> @core.Promise[Bool] =
  #| async (date, data) => {
  #|   const db = globalThis.__D1_DB;
  #|   if (!db || !data?.summary) return false;
  #|
  #|   const summary = data.summary;
  #|   const distance = summary.distances?.find(d => d.activity === 'total')?.distance || 0;
  #|
  #|   await db.prepare(`
  #|     INSERT INTO daily_activity (date, steps, calories_out, distance, floors,
  #|       sedentary_minutes, lightly_active_minutes, fairly_active_minutes, very_active_minutes, raw_data)
  #|     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  #|     ON CONFLICT(date) DO UPDATE SET
  #|       steps = excluded.steps, calories_out = excluded.calories_out,
  #|       distance = excluded.distance, floors = excluded.floors,
  #|       sedentary_minutes = excluded.sedentary_minutes,
  #|       lightly_active_minutes = excluded.lightly_active_minutes,
  #|       fairly_active_minutes = excluded.fairly_active_minutes,
  #|       very_active_minutes = excluded.very_active_minutes,
  #|       raw_data = excluded.raw_data
  #|   `).bind(
  #|     date,
  #|     summary.steps || 0,
  #|     summary.caloriesOut || 0,
  #|     distance,
  #|     summary.floors || 0,
  #|     summary.sedentaryMinutes || 0,
  #|     summary.lightlyActiveMinutes || 0,
  #|     summary.fairlyActiveMinutes || 0,
  #|     summary.veryActiveMinutes || 0,
  #|     JSON.stringify(data)
  #|   ).run();
  #|
  #|   return true;
  #| }

///| Store sleep data in D1
pub extern "js" fn store_sleep_data(date : String, data : @core.Any) -> @core.Promise[Bool] =
  #| async (date, data) => {
  #|   const db = globalThis.__D1_DB;
  #|   if (!db || !data?.sleep?.[0]) return false;
  #|
  #|   const sleep = data.sleep[0];
  #|   const stages = data.summary?.stages;
  #|
  #|   await db.prepare(`
  #|     INSERT INTO sleep_data (date, start_time, end_time, duration_minutes, efficiency,
  #|       deep_minutes, light_minutes, rem_minutes, wake_minutes, raw_data)
  #|     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  #|     ON CONFLICT(date) DO UPDATE SET
  #|       start_time = excluded.start_time, end_time = excluded.end_time,
  #|       duration_minutes = excluded.duration_minutes, efficiency = excluded.efficiency,
  #|       deep_minutes = excluded.deep_minutes, light_minutes = excluded.light_minutes,
  #|       rem_minutes = excluded.rem_minutes, wake_minutes = excluded.wake_minutes,
  #|       raw_data = excluded.raw_data
  #|   `).bind(
  #|     date,
  #|     sleep.startTime,
  #|     sleep.endTime,
  #|     Math.round((sleep.duration || 0) / 60000),
  #|     sleep.efficiency,
  #|     stages?.deep || 0,
  #|     stages?.light || 0,
  #|     stages?.rem || 0,
  #|     stages?.wake || 0,
  #|     JSON.stringify(data)
  #|   ).run();
  #|
  #|   return true;
  #| }

///| Store heart rate data in D1
pub extern "js" fn store_heartrate_data(date : String, data : @core.Any) -> @core.Promise[Bool] =
  #| async (date, data) => {
  #|   const db = globalThis.__D1_DB;
  #|   const hrValue = data?.['activities-heart']?.[0]?.value;
  #|   if (!db || !hrValue) return false;
  #|
  #|   const zones = hrValue.heartRateZones || [];
  #|
  #|   await db.prepare(`
  #|     INSERT INTO heart_rate (date, resting_heart_rate, out_of_range_minutes,
  #|       fat_burn_minutes, cardio_minutes, peak_minutes, raw_data)
  #|     VALUES (?, ?, ?, ?, ?, ?, ?)
  #|     ON CONFLICT(date) DO UPDATE SET
  #|       resting_heart_rate = excluded.resting_heart_rate,
  #|       out_of_range_minutes = excluded.out_of_range_minutes,
  #|       fat_burn_minutes = excluded.fat_burn_minutes,
  #|       cardio_minutes = excluded.cardio_minutes,
  #|       peak_minutes = excluded.peak_minutes,
  #|       raw_data = excluded.raw_data
  #|   `).bind(
  #|     date,
  #|     hrValue.restingHeartRate || null,
  #|     zones.find(z => z.name === 'Out of Range')?.minutes || 0,
  #|     zones.find(z => z.name === 'Fat Burn')?.minutes || 0,
  #|     zones.find(z => z.name === 'Cardio')?.minutes || 0,
  #|     zones.find(z => z.name === 'Peak')?.minutes || 0,
  #|     JSON.stringify(data)
  #|   ).run();
  #|
  #|   return true;
  #| }

///| Store weight data in D1
pub extern "js" fn store_weight_data(data : @core.Any) -> @core.Promise[Bool] =
  #| async (data) => {
  #|   const db = globalThis.__D1_DB;
  #|   const weights = data?.weight;
  #|   if (!db || !weights?.length) return false;
  #|
  #|   for (const w of weights) {
  #|     await db.prepare(`
  #|       INSERT INTO weight_data (date, weight, bmi, fat_percent, raw_data)
  #|       VALUES (?, ?, ?, ?, ?)
  #|       ON CONFLICT(date) DO UPDATE SET
  #|         weight = excluded.weight, bmi = excluded.bmi,
  #|         fat_percent = excluded.fat_percent, raw_data = excluded.raw_data
  #|     `).bind(w.date, w.weight, w.bmi, w.fat, JSON.stringify(w)).run();
  #|   }
  #|
  #|   return true;
  #| }

///| Update daily summary
pub extern "js" fn update_daily_summary(date : String) -> @core.Promise[Bool] =
  #| async (date) => {
  #|   const db = globalThis.__D1_DB;
  #|   if (!db) return false;
  #|
  #|   const activity = await db.prepare('SELECT * FROM daily_activity WHERE date = ?').bind(date).first();
  #|   const sleep = await db.prepare('SELECT * FROM sleep_data WHERE date = ?').bind(date).first();
  #|   const heart = await db.prepare('SELECT * FROM heart_rate WHERE date = ?').bind(date).first();
  #|   const weight = await db.prepare('SELECT * FROM weight_data WHERE date = ? ORDER BY created_at DESC LIMIT 1').bind(date).first();
  #|
  #|   const activeMinutes = (activity?.fairly_active_minutes || 0) + (activity?.very_active_minutes || 0);
  #|
  #|   await db.prepare(`
  #|     INSERT INTO daily_summary (date, steps, calories, distance, active_minutes,
  #|       resting_heart_rate, sleep_duration_minutes, sleep_efficiency, weight)
  #|     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
  #|     ON CONFLICT(date) DO UPDATE SET
  #|       steps = excluded.steps, calories = excluded.calories,
  #|       distance = excluded.distance, active_minutes = excluded.active_minutes,
  #|       resting_heart_rate = excluded.resting_heart_rate,
  #|       sleep_duration_minutes = excluded.sleep_duration_minutes,
  #|       sleep_efficiency = excluded.sleep_efficiency,
  #|       weight = excluded.weight
  #|   `).bind(
  #|     date,
  #|     activity?.steps || 0,
  #|     activity?.calories_out || 0,
  #|     activity?.distance || 0,
  #|     activeMinutes,
  #|     heart?.resting_heart_rate || null,
  #|     sleep?.duration_minutes || 0,
  #|     sleep?.efficiency || null,
  #|     weight?.weight || null
  #|   ).run();
  #|
  #|   return true;
  #| }

// =============================================================================
// Sync Response Builders
// =============================================================================

///| Build sync response
pub extern "js" fn build_sync_response(success : Bool, message : String, date : String) -> @core.Any =
  #| (success, message, date) => ({ success, message, date })

///| Build sync error response
pub extern "js" fn build_sync_error(message : String) -> @core.Any =
  #| (message) => ({ success: false, error: message })
