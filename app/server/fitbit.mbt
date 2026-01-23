///|
/// Fitbit API Service for Health Data
/// Handles OAuth token management and API data fetching

///|
/// Fitbit API base URL
let fitbit_api_url : String = "https://api.fitbit.com"

///|
/// Fitbit OAuth token URL
let fitbit_oauth_url : String = "https://api.fitbit.com/oauth2/token"

///|
/// Fetch activity data from Fitbit
pub async fn fetch_activity_data(
  access_token : String,
  date : String,
) -> @core.Any {
  let url = fitbit_api_url + "/1/user/-/activities/date/" + date + ".json"
  let response = @http.fetch(url, method_="GET", headers={
    "Authorization": "Bearer " + access_token,
  })
  if not(response.ok) {
    @console.error(
      @core.any("Fitbit activity API error: " + response.status.to_string()),
    )
    @core.null()
  } else {
    response.json()
  }
}

///|
/// Fetch sleep data from Fitbit
pub async fn fetch_sleep_data(
  access_token : String,
  date : String,
) -> @core.Any {
  let url = fitbit_api_url + "/1.2/user/-/sleep/date/" + date + ".json"
  let response = @http.fetch(url, method_="GET", headers={
    "Authorization": "Bearer " + access_token,
  })
  if not(response.ok) {
    @console.error(
      @core.any("Fitbit sleep API error: " + response.status.to_string()),
    )
    @core.null()
  } else {
    response.json()
  }
}

///|
/// Fetch heart rate data from Fitbit
pub async fn fetch_heart_data(
  access_token : String,
  date : String,
) -> @core.Any {
  let url = fitbit_api_url +
    "/1/user/-/activities/heart/date/" +
    date +
    "/1d.json"
  let response = @http.fetch(url, method_="GET", headers={
    "Authorization": "Bearer " + access_token,
  })
  if not(response.ok) {
    @console.error(
      @core.any("Fitbit heart rate API error: " + response.status.to_string()),
    )
    @core.null()
  } else {
    response.json()
  }
}

///|
/// Fetch weight data from Fitbit (last 30 days)
pub async fn fetch_weight_data(
  access_token : String,
  date : String,
) -> @core.Any {
  let url = fitbit_api_url +
    "/1/user/-/body/log/weight/date/" +
    date +
    "/30d.json"
  let response = @http.fetch(url, method_="GET", headers={
    "Authorization": "Bearer " + access_token,
  })
  if not(response.ok) {
    @console.error(
      @core.any("Fitbit weight API error: " + response.status.to_string()),
    )
    @core.null()
  } else {
    response.json()
  }
}

///|
/// Fetch VO2max (cardio score) data from Fitbit
pub async fn fetch_vo2max_data(
  access_token : String,
  date : String,
) -> @core.Any {
  let url = fitbit_api_url + "/1/user/-/cardioscore/date/" + date + ".json"
  let response = @http.fetch(url, method_="GET", headers={
    "Authorization": "Bearer " + access_token,
  })
  if not(response.ok) {
    @console.error(
      @core.any("Fitbit VO2max API error: " + response.status.to_string()),
    )
    @core.null()
  } else {
    response.json()
  }
}

///|
/// Fetch SpO2 (oxygen saturation) data from Fitbit
pub async fn fetch_spo2_data(access_token : String, date : String) -> @core.Any {
  let url = fitbit_api_url + "/1/user/-/spo2/date/" + date + ".json"
  let response = @http.fetch(url, method_="GET", headers={
    "Authorization": "Bearer " + access_token,
  })
  if not(response.ok) {
    @console.error(
      @core.any("Fitbit SpO2 API error: " + response.status.to_string()),
    )
    @core.null()
  } else {
    response.json()
  }
}

///|
/// Refresh OAuth token
pub async fn refresh_oauth_token(refresh_token : String) -> @core.Any {
  let client_id = get_env("FITBIT_CLIENT_ID")
  let client_secret = get_env("FITBIT_CLIENT_SECRET")
  if client_id == "" || client_secret == "" {
    @console.error(@core.any("Fitbit OAuth credentials not configured"))
    @core.null()
  } else {
    let auth_header = btoa(client_id + ":" + client_secret)
    let params = new_url_search_params()
    params.set("grant_type", "refresh_token")
    params.set("refresh_token", refresh_token)
    let response = @http.fetch(
      fitbit_oauth_url,
      method_="POST",
      headers={
        "Authorization": "Basic " + auth_header,
        "Content-Type": "application/x-www-form-urlencoded",
      },
      body=@core.any(params.to_string()),
    )
    if not(response.ok) {
      let error_text = response.text()
      @console.error(@core.any("Token refresh failed: " + error_text))
      @core.null()
    } else {
      response.json()
    }
  }
}

///|
/// Exchange authorization code for tokens
pub async fn exchange_auth_code(
  code : String,
  redirect_uri : String,
) -> @core.Any {
  let client_id = get_env("FITBIT_CLIENT_ID")
  let client_secret = get_env("FITBIT_CLIENT_SECRET")
  if client_id == "" || client_secret == "" {
    @console.error(@core.any("Fitbit OAuth credentials not configured"))
    @core.null()
  } else {
    let auth_header = btoa(client_id + ":" + client_secret)
    let params = new_url_search_params()
    params.set("grant_type", "authorization_code")
    params.set("code", code)
    params.set("redirect_uri", redirect_uri)
    let response = @http.fetch(
      fitbit_oauth_url,
      method_="POST",
      headers={
        "Authorization": "Basic " + auth_header,
        "Content-Type": "application/x-www-form-urlencoded",
      },
      body=@core.any(params.to_string()),
    )
    if not(response.ok) {
      let error_text = response.text()
      @console.error(@core.any("Token exchange failed: " + error_text))
      @core.null()
    } else {
      response.json()
    }
  }
}

///|
/// Base64 encode a string (for Basic Auth)
extern "js" fn btoa(s : String) -> String =
  #| (s) => btoa(s)

///|
/// Get today's date in ISO format (YYYY-MM-DD)
pub extern "js" fn get_today_iso() -> String =
  #| () => new Date().toISOString().split('T')[0]

///|
/// Parse activity data from Fitbit response
pub fn parse_activity_data(data : @core.Any) -> @core.Any {
  if is_null(data) {
    @core.null()
  } else {
    let summary = data._get("summary")
    if is_null(summary) {
      @core.null()
    } else {
      let result = @core.new_object()
      result._set("steps", summary._get("steps"))
      result._set("caloriesOut", summary._get("caloriesOut"))
      result._set("floors", summary._get("floors"))
      result._set("sedentaryMinutes", summary._get("sedentaryMinutes"))
      result._set("lightlyActiveMinutes", summary._get("lightlyActiveMinutes"))
      result._set("fairlyActiveMinutes", summary._get("fairlyActiveMinutes"))
      result._set("veryActiveMinutes", summary._get("veryActiveMinutes"))

      // Extract total distance
      let distances = summary._get("distances")
      if not(is_null(distances)) {
        let arr = to_array(distances)
        for d in arr {
          let activity = safe_string(d._get("activity"))
          if activity == "total" {
            result._set("distance", d._get("distance"))
            break
          }
        }
      }
      result
    }
  }
}

///|
/// Parse sleep data from Fitbit response
pub fn parse_sleep_data(data : @core.Any) -> @core.Any {
  if is_null(data) {
    @core.null()
  } else {
    let sleep_arr = data._get("sleep")
    if is_null(sleep_arr) {
      @core.null()
    } else {
      let arr = to_array(sleep_arr)
      if arr.length() == 0 {
        @core.null()
      } else {
        let sleep = arr[0]
        let result = @core.new_object()
        result._set("startTime", sleep._get("startTime"))
        result._set("endTime", sleep._get("endTime"))
        result._set("duration", sleep._get("duration"))
        result._set("efficiency", sleep._get("efficiency"))

        // Parse stages from summary
        let summary = data._get("summary")
        if not(is_null(summary)) {
          let stages = summary._get("stages")
          if not(is_null(stages)) {
            result._set("deep", stages._get("deep"))
            result._set("light", stages._get("light"))
            result._set("rem", stages._get("rem"))
            result._set("wake", stages._get("wake"))
          }
        }
        result
      }
    }
  }
}

///|
/// Parse heart rate data from Fitbit response
pub fn parse_heart_data(data : @core.Any) -> @core.Any {
  if is_null(data) {
    @core.null()
  } else {
    let activities_heart = data._get("activities-heart")
    if is_null(activities_heart) {
      @core.null()
    } else {
      let arr = to_array(activities_heart)
      if arr.length() == 0 {
        @core.null()
      } else {
        let hr_value = arr[0]._get("value")
        if is_null(hr_value) {
          @core.null()
        } else {
          let result = @core.new_object()
          result._set("restingHeartRate", hr_value._get("restingHeartRate"))

          // Parse heart rate zones
          let zones = hr_value._get("heartRateZones")
          if not(is_null(zones)) {
            let zones_arr = to_array(zones)
            for z in zones_arr {
              let name = safe_string(z._get("name"))
              let minutes = z._get("minutes")
              if name == "Out of Range" {
                result._set("outOfRange", minutes)
              } else if name == "Fat Burn" {
                result._set("fatBurn", minutes)
              } else if name == "Cardio" {
                result._set("cardio", minutes)
              } else if name == "Peak" {
                result._set("peak", minutes)
              }
            }
          }
          result
        }
      }
    }
  }
}
