///| Routes for Fitbit Health Dashboard

///| Implements SSR health dashboard with Cloudflare D1 database

// =============================================================================
// Route Definitions
// =============================================================================

///|
pub fn routes() -> Array[@router.SolRoutes] {
  // Dashboard routes (with logger middleware)
  let dashboard_routes : Array[@router.SolRoutes] = [
    @router.SolRoutes::WithMiddleware(middleware=[@mw.logger()], children=[
      @router.SolRoutes::Layout(segment="", layout=root_layout, children=[
        @router.SolRoutes::Page(
          path="/",
          handler=@router.PageHandler(dashboard_page),
          title="Health Dashboard",
          meta=[],
          revalidate=None,
          cache=None,
        ),
      ]),
    ]),
  ]
  // MCP API routes (auth handled at Hono level in worker.ts)
  let api_routes = mcp_routes()
  // Combine all routes
  let all_routes : Array[@router.SolRoutes] = []
  for r in dashboard_routes {
    all_routes.push(r)
  }
  for r in api_routes {
    all_routes.push(r)
  }
  all_routes
}

// =============================================================================
// Layouts
// =============================================================================

///|
/// Root layout with navigation
fn root_layout(
  _props : @router.PageProps,
  content : @server_dom.ServerNode,
) -> @server_dom.ServerNode raise Error {
  @server_dom.ServerNode::async_(async fn() {
    let inner = content.resolve()
    @luna.fragment([
      div(class="dashboard-bg", []),
      nav(
        attrs=[("aria-label", @luna.attr_static("Main navigation"))],
        class="main-nav",
        [
          a(href="/", class="nav-brand", [text("Fitbit Health")]),
          a(href="/", class="nav-link active", [text("Dashboard")]),
          a(href="/auth/fitbit", class="nav-link", [text("Connect Fitbit")]),
        ],
      ),
      main_el(class="dashboard-main", [inner]),
    ])
  })
}

// =============================================================================
// Dashboard Page
// =============================================================================

///|
/// Main dashboard page with health metrics
async fn dashboard_page(_props : @router.PageProps) -> @server_dom.ServerNode {
  @server_dom.ServerNode::async_(async fn() {
    let token_status = db_get_token_status()
    let is_connected = get_bool(token_status, "connected")
    if not(is_connected) {
      render_empty_state()
    } else {
      let activity = db_get_latest_activity()
      let sleep = db_get_latest_sleep()
      let heartrate = db_get_latest_heartrate()
      let weight = db_get_latest_weight()
      let vo2max = db_get_latest_vo2max()
      let spo2 = db_get_latest_spo2()
      let summaries = db_get_daily_summaries(7)
      let last_sync = get_str(token_status, "lastSync")
      let sync_text = if last_sync != "" {
        format_date(last_sync)
      } else {
        "Never"
      }
      @luna.fragment([
        header(class="dashboard-header", [
          div([
            h1(class="dashboard-title", [text("Health Dashboard")]),
            p(class="dashboard-subtitle", [text("Last synced: " + sync_text)]),
          ]),
          div(class="header-actions", [
            span(class="auth-status connected", [text("Connected")]),
            form(
              http_method="POST",
              action="/api/sync",
              style="display: inline;",
              [
                button(
                  attrs=[("type", @luna.attr_static("submit"))],
                  class="btn-sync",
                  [text("Sync Now")],
                ),
              ],
            ),
          ]),
        ]),
        section(class="metrics-grid", [
          render_steps_card(activity),
          render_calories_card(activity),
          render_sleep_card(sleep),
          render_heartrate_card(heartrate),
          render_weight_card(weight),
          render_vo2max_card(vo2max),
          render_spo2_card(spo2),
        ]),
        section(class="summary-section", [
          header(class="section-header", [
            h2(class="section-title", [text("Daily Summary")]),
            span(class="section-subtitle", [text("Past 7 days")]),
          ]),
          render_summary_list(summaries),
        ]),
      ])
    }
  })
}

// =============================================================================
// Metric Card Renderers
// =============================================================================

///|
fn render_steps_card(activity : @core.Any) -> @luna.Node[Unit] {
  let steps = get_int(activity, "steps")
  let distance = get_float(activity, "distance")
  let goal = 10000
  let progress = steps * 100 / goal
  let capped_progress = if progress > 100 { 100 } else { progress }
  article(
    attrs=[
      (
        "aria-label",
        @luna.attr_static(
          "Steps: " +
          format_number(steps) +
          " of " +
          format_number(goal) +
          " goal",
        ),
      ),
    ],
    class="metric-card steps",
    [
      div(class="metric-header", [
        span(class="metric-label", [text("Steps")]),
        span(
          attrs=[("aria-hidden", @luna.attr_static("true"))],
          class="metric-icon",
          [text("👟")],
        ),
      ]),
      div(class="metric-value", [
        span(class="metric-number", [text(format_number(steps))]),
        span(class="metric-unit", [text("steps")]),
      ]),
      div(
        attrs=[
          ("role", @luna.attr_static("progressbar")),
          ("aria-valuenow", @luna.attr_static(capped_progress.to_string())),
          ("aria-valuemin", @luna.attr_static("0")),
          ("aria-valuemax", @luna.attr_static("100")),
          ("aria-label", @luna.attr_static("Steps progress")),
        ],
        class="progress-ring",
        [
          div(
            class="progress-ring-fill",
            style="width: " + capped_progress.to_string() + "%",
            [],
          ),
        ],
      ),
      div(class="progress-label", [
        span([text("Goal: " + format_number(goal))]),
        span([text(capped_progress.to_string() + "%")]),
      ]),
      div(class="metric-secondary", [
        div(class="secondary-stat", [
          span(class="secondary-stat-label", [text("Distance")]),
          span(class="secondary-stat-value", [
            text(format_float(distance, 2) + " km"),
          ]),
        ]),
      ]),
    ],
  )
}

///|
fn render_calories_card(activity : @core.Any) -> @luna.Node[Unit] {
  let calories = get_int(activity, "calories_out")
  let fairly_active = get_int(activity, "fairly_active_minutes")
  let very_active = get_int(activity, "very_active_minutes")
  let active_mins = fairly_active + very_active
  let goal = 2500
  let progress = calories * 100 / goal
  let capped_progress = if progress > 100 { 100 } else { progress }
  article(
    attrs=[
      (
        "aria-label",
        @luna.attr_static(
          "Calories: " + format_number(calories) + " kcal burned",
        ),
      ),
    ],
    class="metric-card calories",
    [
      div(class="metric-header", [
        span(class="metric-label", [text("Calories")]),
        span(
          attrs=[("aria-hidden", @luna.attr_static("true"))],
          class="metric-icon",
          [text("🔥")],
        ),
      ]),
      div(class="metric-value", [
        span(class="metric-number", [text(format_number(calories))]),
        span(class="metric-unit", [text("kcal")]),
      ]),
      div(
        attrs=[
          ("role", @luna.attr_static("progressbar")),
          ("aria-valuenow", @luna.attr_static(capped_progress.to_string())),
          ("aria-valuemin", @luna.attr_static("0")),
          ("aria-valuemax", @luna.attr_static("100")),
          ("aria-label", @luna.attr_static("Calories progress")),
        ],
        class="progress-ring",
        [
          div(
            class="progress-ring-fill",
            style="width: " + capped_progress.to_string() + "%",
            [],
          ),
        ],
      ),
      div(class="metric-secondary", [
        div(class="secondary-stat", [
          span(class="secondary-stat-label", [text("Active")]),
          span(class="secondary-stat-value", [
            text(active_mins.to_string() + " min"),
          ]),
        ]),
      ]),
    ],
  )
}

///|
fn render_sleep_card(sleep : @core.Any) -> @luna.Node[Unit] {
  let duration = get_int(sleep, "duration_minutes")
  let efficiency = get_int(sleep, "efficiency")
  let hours = duration / 60
  let mins = duration % 60
  let eff_text = if efficiency > 0 {
    efficiency.to_string() + "%"
  } else {
    "--"
  }
  article(
    attrs=[
      (
        "aria-label",
        @luna.attr_static(
          "Sleep: " +
          hours.to_string() +
          " hours " +
          mins.to_string() +
          " minutes",
        ),
      ),
    ],
    class="metric-card sleep",
    [
      div(class="metric-header", [
        span(class="metric-label", [text("Sleep")]),
        span(
          attrs=[("aria-hidden", @luna.attr_static("true"))],
          class="metric-icon",
          [text("😴")],
        ),
      ]),
      div(class="metric-value", [
        span(class="metric-number", [
          text(hours.to_string() + "h " + mins.to_string() + "m"),
        ]),
        span(class="metric-unit", [text("")]),
      ]),
      div(class="metric-secondary", [
        div(class="secondary-stat", [
          span(class="secondary-stat-label", [text("Efficiency")]),
          span(class="secondary-stat-value", [text(eff_text)]),
        ]),
      ]),
    ],
  )
}

///|
fn render_heartrate_card(heartrate : @core.Any) -> @luna.Node[Unit] {
  let resting = get_int(heartrate, "resting_heart_rate")
  let cardio = get_int(heartrate, "cardio_minutes")
  let hr_text = if resting > 0 { resting.to_string() } else { "--" }
  article(
    attrs=[
      (
        "aria-label",
        @luna.attr_static("Heart Rate: " + hr_text + " bpm resting"),
      ),
    ],
    class="metric-card heartrate",
    [
      div(class="metric-header", [
        span(class="metric-label", [text("Heart Rate")]),
        span(
          attrs=[("aria-hidden", @luna.attr_static("true"))],
          class="metric-icon",
          [text("❤️")],
        ),
      ]),
      div(class="metric-value", [
        span(class="metric-number", [text(hr_text)]),
        span(class="metric-unit", [text("bpm resting")]),
      ]),
      div(class="metric-secondary", [
        div(class="secondary-stat", [
          span(class="secondary-stat-label", [text("Cardio")]),
          span(class="secondary-stat-value", [text(cardio.to_string() + " min")]),
        ]),
      ]),
    ],
  )
}

///|
fn render_weight_card(weight : @core.Any) -> @luna.Node[Unit] {
  let weight_kg = get_float(weight, "weight")
  let bmi = get_float(weight, "bmi")
  let weight_text = if weight_kg > 0.0 {
    format_float(weight_kg, 1)
  } else {
    "--"
  }
  let bmi_text = if bmi > 0.0 { format_float(bmi, 1) } else { "--" }
  article(
    attrs=[("aria-label", @luna.attr_static("Weight: " + weight_text + " kg"))],
    class="metric-card weight",
    [
      div(class="metric-header", [
        span(class="metric-label", [text("Weight")]),
        span(
          attrs=[("aria-hidden", @luna.attr_static("true"))],
          class="metric-icon",
          [text("⚖️")],
        ),
      ]),
      div(class="metric-value", [
        span(class="metric-number", [text(weight_text)]),
        span(class="metric-unit", [text("kg")]),
      ]),
      div(class="metric-secondary", [
        div(class="secondary-stat", [
          span(class="secondary-stat-label", [text("BMI")]),
          span(class="secondary-stat-value", [text(bmi_text)]),
        ]),
      ]),
    ],
  )
}

///|
fn render_vo2max_card(vo2max : @core.Any) -> @luna.Node[Unit] {
  let vo2max_val = get_str(vo2max, "vo2max")
  let vo2max_text = if vo2max_val != "" { vo2max_val } else { "--" }
  let date = get_str(vo2max, "date")
  let date_text = if date != "" { format_date(date) } else { "--" }

  // Fitness level based on VO2max range (simplified)
  let fitness_level = if vo2max_val == "" { "No data" } else { "Active" }
  article(
    attrs=[
      ("aria-label", @luna.attr_static("VO2max: " + vo2max_text + " mL/kg/min")),
    ],
    class="metric-card vo2max",
    [
      div(class="metric-header", [
        span(class="metric-label", [text("VO2max")]),
        span(
          attrs=[("aria-hidden", @luna.attr_static("true"))],
          class="metric-icon",
          [text("🫀")],
        ),
      ]),
      div(class="metric-value", [
        span(class="metric-number", [text(vo2max_text)]),
        span(class="metric-unit", [text("mL/kg/min")]),
      ]),
      div(class="metric-secondary", [
        div(class="secondary-stat", [
          span(class="secondary-stat-label", [text("Fitness")]),
          span(class="secondary-stat-value", [text(fitness_level)]),
        ]),
        div(class="secondary-stat", [
          span(class="secondary-stat-label", [text("Updated")]),
          span(class="secondary-stat-value", [text(date_text)]),
        ]),
      ]),
    ],
  )
}

///|
fn render_spo2_card(spo2 : @core.Any) -> @luna.Node[Unit] {
  let avg = get_float(spo2, "avg")
  let min_val = get_float(spo2, "min")
  let max_val = get_float(spo2, "max")
  let avg_text = if avg > 0.0 { format_float(avg, 1) } else { "--" }
  let min_text = if min_val > 0.0 { format_float(min_val, 1) } else { "--" }
  let max_text = if max_val > 0.0 { format_float(max_val, 1) } else { "--" }
  article(
    attrs=[("aria-label", @luna.attr_static("SpO2: " + avg_text + "% average"))],
    class="metric-card spo2",
    [
      div(class="metric-header", [
        span(class="metric-label", [text("Blood Oxygen")]),
        span(
          attrs=[("aria-hidden", @luna.attr_static("true"))],
          class="metric-icon",
          [text("💨")],
        ),
      ]),
      div(class="metric-value", [
        span(class="metric-number", [text(avg_text)]),
        span(class="metric-unit", [text("% avg")]),
      ]),
      div(class="metric-secondary", [
        div(class="secondary-stat", [
          span(class="secondary-stat-label", [text("Min")]),
          span(class="secondary-stat-value", [text(min_text + "%")]),
        ]),
        div(class="secondary-stat", [
          span(class="secondary-stat-label", [text("Max")]),
          span(class="secondary-stat-value", [text(max_text + "%")]),
        ]),
      ]),
    ],
  )
}

// =============================================================================
// Summary List Renderer
// =============================================================================

///|
fn render_summary_list(summaries : @core.Any) -> @luna.Node[Unit] {
  let len = array_len(summaries)
  if len == 0 {
    div(class="empty-state", [
      p([text("No data yet. Sync your Fitbit to see daily summaries.")]),
    ])
  } else {
    let items : Array[@luna.Node[Unit]] = []
    for i = 0; i < len; i = i + 1 {
      let summary = array_get(summaries, i)
      let date = get_str(summary, "date")
      let is_today_row = is_today(date)
      let row_class = if is_today_row {
        "summary-item today"
      } else {
        "summary-item"
      }
      let steps = get_int(summary, "steps")
      let calories = get_int(summary, "calories")
      let sleep_mins = get_int(summary, "sleep_duration_minutes")
      let hr = get_int(summary, "resting_heart_rate")
      let w = get_float(summary, "weight")
      let hr_str = if hr > 0 { hr.to_string() } else { "--" }
      let w_str = if w > 0.0 { format_float(w, 1) } else { "--" }
      items.push(
        div(class=row_class, [
          div(class="summary-date", [span([text(format_date(date))])]),
          div(class="summary-metric", [
            span(class="summary-metric-value", [text(format_number(steps))]),
            span(class="summary-metric-label", [text("Steps")]),
          ]),
          div(class="summary-metric", [
            span(class="summary-metric-value", [text(format_number(calories))]),
            span(class="summary-metric-label", [text("Cal")]),
          ]),
          div(class="summary-metric", [
            span(class="summary-metric-value", [
              text((sleep_mins / 60).to_string() + "h"),
            ]),
            span(class="summary-metric-label", [text("Sleep")]),
          ]),
          div(class="summary-metric", [
            span(class="summary-metric-value", [text(hr_str)]),
            span(class="summary-metric-label", [text("HR")]),
          ]),
          div(class="summary-metric", [
            span(class="summary-metric-value", [text(w_str)]),
            span(class="summary-metric-label", [text("kg")]),
          ]),
        ]),
      )
    }
    div(class="summary-list", items)
  }
}

// =============================================================================
// Empty State
// =============================================================================

///|
fn render_empty_state() -> @luna.Node[Unit] {
  @luna.fragment([
    header(class="dashboard-header", [
      div([
        h1(class="dashboard-title", [text("Health Dashboard")]),
        p(class="dashboard-subtitle", [
          text("Connect your Fitbit to get started"),
        ]),
      ]),
    ]),
    div(class="empty-state", [
      span(
        attrs=[("aria-hidden", @luna.attr_static("true"))],
        class="empty-state-icon",
        [text("💪")],
      ),
      h3(class="empty-state-title", [text("Connect Your Fitbit")]),
      p(class="empty-state-text", [
        text("Link your Fitbit account to start tracking your health metrics."),
      ]),
      a(href="/auth/fitbit", class="btn-connect", [text("Connect Fitbit")]),
    ]),
  ])
}

// =============================================================================
// Router Configuration
// =============================================================================

///|
const ROOT : String =
  #|<!DOCTYPE html>
  #|<html lang="en">
  #|<head>
  #|  <meta charset="UTF-8">
  #|  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  #|  <meta name="description" content="Track your Fitbit health metrics including steps, calories, sleep, heart rate, and weight. Personal health dashboard powered by Fitbit API.">
  #|  <link rel="canonical" href="https://fitbit-private-mcp.kazu-san.workers.dev/">
  #|  <title>__LUNA_TITLE__</title>
  #|  <link rel="preconnect" href="https://fonts.googleapis.com">
  #|  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  #|  <link href="https://fonts.googleapis.com/css2?family=DM+Sans:wght@400;500;600;700&family=JetBrains+Mono:wght@400;500&family=Outfit:wght@400;500;600;700&display=swap" rel="stylesheet" media="print" onload="this.media='all'">
  #|  <noscript><link href="https://fonts.googleapis.com/css2?family=DM+Sans:wght@400;500;600;700&family=JetBrains+Mono:wght@400;500&family=Outfit:wght@400;500;600;700&display=swap" rel="stylesheet"></noscript>
  #|  <style>
  #|    :root{--bg-deep:#0a0e1a;--bg-primary:#0f1629;--bg-elevated:#161d35;--bg-card:rgba(22,29,53,0.7);--bg-card-hover:rgba(30,40,70,0.8);--accent-teal:#00d4aa;--accent-teal-dim:#00a888;--accent-teal-glow:rgba(0,212,170,0.3);--accent-orange:#ff8c42;--accent-purple:#a855f7;--accent-red:#ff6b6b;--accent-blue:#4f8cff;--text-primary:#fff;--text-secondary:rgba(255,255,255,0.7);--text-muted:rgba(255,255,255,0.6);--text-dim:rgba(255,255,255,0.35);--font-display:'Outfit',system-ui,sans-serif;--font-body:'DM Sans',system-ui,sans-serif;--font-mono:'JetBrains Mono',monospace;--metric-size-xl:clamp(2.5rem,5vw,4rem);--space-xs:0.5rem;--space-sm:0.75rem;--space-md:1rem;--space-lg:1.5rem;--space-xl:2rem;--space-2xl:3rem;--radius-sm:8px;--radius-md:12px;--radius-lg:16px;--radius-full:9999px;--border-subtle:1px solid rgba(255,255,255,0.06);--shadow-card:0 4px 24px rgba(0,0,0,0.4);--shadow-elevated:0 8px 32px rgba(0,0,0,0.5);--shadow-glow-teal:0 0 30px var(--accent-teal-glow);--transition-fast:0.15s cubic-bezier(0.4,0,0.2,1);--transition-base:0.25s cubic-bezier(0.4,0,0.2,1)}
  #|    *,*::before,*::after{box-sizing:border-box}
  #|    body{font-family:var(--font-body);font-size:16px;line-height:1.6;color:var(--text-primary);background:var(--bg-deep);margin:0;padding:0;-webkit-font-smoothing:antialiased;min-height:100vh}
  #|    .dashboard-bg{position:fixed;inset:0;z-index:-1;background:radial-gradient(ellipse 80% 50% at 20% 0%,rgba(0,212,170,0.08) 0%,transparent 50%),radial-gradient(ellipse 60% 40% at 80% 100%,rgba(255,140,66,0.06) 0%,transparent 50%),radial-gradient(ellipse 100% 100% at 50% 50%,var(--bg-primary) 0%,var(--bg-deep) 100%)}
  #|    #__sol__{max-width:1400px;margin:0 auto;padding:var(--space-xl);min-height:100vh}
  #|    .main-nav{display:flex;align-items:center;gap:var(--space-md);padding:var(--space-md) var(--space-lg);background:var(--bg-elevated);border:var(--border-subtle);border-radius:var(--radius-lg);margin-bottom:var(--space-xl)}
  #|    .nav-brand{font-family:var(--font-display);font-size:1.125rem;font-weight:700;color:var(--text-primary);text-decoration:none;margin-right:auto}
  #|    .nav-link{font-size:0.875rem;font-weight:500;color:var(--text-secondary);text-decoration:none;padding:var(--space-xs) var(--space-md);border-radius:var(--radius-sm);transition:all var(--transition-fast)}
  #|    .nav-link:hover{color:var(--text-primary);background:rgba(255,255,255,0.05)}
  #|    .nav-link.active{color:var(--accent-teal);background:rgba(0,212,170,0.1)}
  #|    .dashboard-header{display:flex;justify-content:space-between;align-items:center;margin-bottom:var(--space-2xl);padding-bottom:var(--space-lg);border-bottom:var(--border-subtle)}
  #|    .dashboard-title{font-family:var(--font-display);font-size:clamp(1.5rem,3vw,2rem);font-weight:700;margin:0;background:linear-gradient(135deg,var(--text-primary) 0%,var(--accent-teal) 100%);-webkit-background-clip:text;-webkit-text-fill-color:transparent;background-clip:text}
  #|    .dashboard-subtitle{font-size:0.875rem;color:var(--text-muted);margin-top:var(--space-xs)}
  #|    .header-actions{display:flex;gap:var(--space-md);align-items:center}
  #|    .auth-status{display:flex;align-items:center;gap:var(--space-sm);padding:var(--space-xs) var(--space-md);font-size:0.75rem;font-weight:500;text-transform:uppercase;letter-spacing:0.05em;border-radius:var(--radius-full);background:var(--bg-elevated);border:var(--border-subtle)}
  #|    .auth-status::before{content:'';width:8px;height:8px;border-radius:50%;background:var(--accent-red)}
  #|    .auth-status.connected::before{background:var(--accent-teal);box-shadow:0 0 8px var(--accent-teal);animation:pulse-dot 2s ease-in-out infinite}
  #|    @keyframes pulse-dot{0%,100%{opacity:1}50%{opacity:0.5}}
  #|    .btn-sync{display:inline-flex;align-items:center;gap:var(--space-sm);padding:var(--space-sm) var(--space-lg);font-family:var(--font-body);font-size:0.875rem;font-weight:600;color:var(--bg-deep);background:linear-gradient(135deg,var(--accent-teal) 0%,var(--accent-teal-dim) 100%);border:none;border-radius:var(--radius-full);cursor:pointer;transition:all var(--transition-base);box-shadow:var(--shadow-glow-teal)}
  #|    .btn-sync:hover{transform:translateY(-2px)}
  #|    .metrics-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(240px,1fr));gap:var(--space-lg);margin-bottom:var(--space-2xl)}
  #|    .metric-card{position:relative;padding:var(--space-xl);background:var(--bg-card);backdrop-filter:blur(20px);border:var(--border-subtle);border-radius:var(--radius-lg);box-shadow:var(--shadow-card);overflow:hidden;transition:all var(--transition-base)}
  #|    .metric-card::before{content:'';position:absolute;inset:0;background:linear-gradient(135deg,rgba(255,255,255,0.03) 0%,transparent 50%);pointer-events:none}
  #|    .metric-card:hover{transform:translateY(-4px);background:var(--bg-card-hover);box-shadow:var(--shadow-elevated)}
  #|    .metric-card::after{content:'';position:absolute;top:0;left:var(--space-lg);right:var(--space-lg);height:2px;background:var(--card-accent,var(--accent-teal));border-radius:0 0 2px 2px;opacity:0.6}
  #|    .metric-card:hover::after{opacity:1}
  #|    .metric-card.steps{--card-accent:var(--accent-teal)}
  #|    .metric-card.calories{--card-accent:var(--accent-orange)}
  #|    .metric-card.sleep{--card-accent:var(--accent-purple)}
  #|    .metric-card.heartrate{--card-accent:var(--accent-red)}
  #|    .metric-card.weight{--card-accent:var(--accent-blue)}
  #|    .metric-card.vo2max{--card-accent:#10b981}
  #|    .metric-card.spo2{--card-accent:#06b6d4}
  #|    .metric-header{display:flex;align-items:center;justify-content:space-between;margin-bottom:var(--space-lg)}
  #|    .metric-label{font-size:0.75rem;font-weight:600;text-transform:uppercase;letter-spacing:0.08em;color:var(--text-muted)}
  #|    .metric-icon{width:36px;height:36px;display:flex;align-items:center;justify-content:center;background:rgba(255,255,255,0.05);border-radius:var(--radius-md);font-size:1.25rem}
  #|    .metric-value{display:flex;align-items:baseline;gap:var(--space-xs);margin-bottom:var(--space-sm)}
  #|    .metric-number{font-family:var(--font-display);font-size:var(--metric-size-xl);font-weight:700;line-height:1;letter-spacing:-0.03em}
  #|    .metric-unit{font-size:0.875rem;font-weight:500;color:var(--text-muted)}
  #|    .progress-ring{width:100%;height:6px;background:rgba(255,255,255,0.1);border-radius:var(--radius-full);overflow:hidden;margin-top:var(--space-md)}
  #|    .progress-ring-fill{height:100%;background:linear-gradient(90deg,var(--card-accent,var(--accent-teal)),var(--accent-teal));border-radius:var(--radius-full);box-shadow:0 0 10px var(--card-accent,var(--accent-teal))}
  #|    .progress-label{display:flex;justify-content:space-between;margin-top:var(--space-sm);font-size:0.75rem;color:var(--text-muted)}
  #|    .metric-secondary{display:flex;gap:var(--space-lg);margin-top:var(--space-md);padding-top:var(--space-md);border-top:var(--border-subtle)}
  #|    .secondary-stat{flex:1}
  #|    .secondary-stat-label{font-size:0.625rem;font-weight:500;text-transform:uppercase;letter-spacing:0.05em;color:var(--text-dim);margin-bottom:2px;display:block}
  #|    .secondary-stat-value{font-family:var(--font-display);font-size:1rem;font-weight:600;color:var(--text-secondary)}
  #|    .summary-section{margin-top:var(--space-2xl)}
  #|    .section-header{display:flex;align-items:center;justify-content:space-between;margin-bottom:var(--space-lg)}
  #|    .section-title{font-family:var(--font-display);font-size:1.25rem;font-weight:600;margin:0}
  #|    .section-subtitle{font-size:0.875rem;color:var(--text-muted)}
  #|    .summary-list{display:flex;flex-direction:column;gap:var(--space-sm)}
  #|    .summary-item{display:grid;grid-template-columns:100px repeat(5,1fr);align-items:center;gap:var(--space-md);padding:var(--space-md) var(--space-lg);background:var(--bg-card);backdrop-filter:blur(10px);border:var(--border-subtle);border-radius:var(--radius-md);transition:all var(--transition-fast)}
  #|    .summary-item:hover{background:var(--bg-card-hover);transform:translateX(4px)}
  #|    .summary-date{font-family:var(--font-mono);font-size:0.8125rem;font-weight:500;color:var(--text-secondary)}
  #|    .summary-metric{text-align:right}
  #|    .summary-metric-value{font-family:var(--font-display);font-size:1rem;font-weight:600;display:block}
  #|    .summary-metric-label{font-size:0.625rem;color:var(--text-muted);text-transform:uppercase}
  #|    .summary-item.today{background:rgba(0,212,170,0.1);border-color:rgba(0,212,170,0.2)}
  #|    .summary-item.today .summary-date{color:var(--accent-teal)}
  #|    .empty-state{display:flex;flex-direction:column;align-items:center;justify-content:center;padding:var(--space-2xl);text-align:center;background:var(--bg-card);border:2px dashed rgba(255,255,255,0.1);border-radius:var(--radius-lg);margin-top:var(--space-xl)}
  #|    .empty-state-icon{font-size:3rem;margin-bottom:var(--space-md);opacity:0.4}
  #|    .empty-state-title{font-family:var(--font-display);font-size:1.25rem;font-weight:600;margin:0 0 var(--space-sm)}
  #|    .empty-state-text{color:var(--text-muted);max-width:320px;margin-bottom:var(--space-lg)}
  #|    .btn-connect{display:inline-flex;align-items:center;gap:var(--space-sm);padding:var(--space-md) var(--space-xl);font-family:var(--font-body);font-size:0.9375rem;font-weight:600;color:var(--text-primary);background:linear-gradient(135deg,var(--accent-teal) 0%,#00c8ff 100%);border:none;border-radius:var(--radius-full);cursor:pointer;text-decoration:none;transition:all var(--transition-base);box-shadow:var(--shadow-glow-teal)}
  #|    .btn-connect:hover{transform:translateY(-2px) scale(1.02)}
  #|    .metric-card{animation:card-enter 0.5s cubic-bezier(0.4,0,0.2,1) backwards}
  #|    .metric-card:nth-child(1){animation-delay:0.1s}.metric-card:nth-child(2){animation-delay:0.15s}.metric-card:nth-child(3){animation-delay:0.2s}.metric-card:nth-child(4){animation-delay:0.25s}.metric-card:nth-child(5){animation-delay:0.3s}
  #|    @keyframes card-enter{from{opacity:0;transform:translateY(20px)}to{opacity:1;transform:translateY(0)}}
  #|    .summary-item{animation:row-enter 0.4s cubic-bezier(0.4,0,0.2,1) backwards}
  #|    .summary-item:nth-child(1){animation-delay:0.4s}.summary-item:nth-child(2){animation-delay:0.45s}.summary-item:nth-child(3){animation-delay:0.5s}.summary-item:nth-child(4){animation-delay:0.55s}.summary-item:nth-child(5){animation-delay:0.6s}.summary-item:nth-child(6){animation-delay:0.65s}.summary-item:nth-child(7){animation-delay:0.7s}
  #|    @keyframes row-enter{from{opacity:0;transform:translateX(-10px)}to{opacity:1;transform:translateX(0)}}
  #|    @media(max-width:1024px){.summary-item{grid-template-columns:80px repeat(3,1fr)}.summary-item>:nth-child(n+5){display:none}}
  #|    @media(max-width:768px){#__sol__{padding:var(--space-md)}.dashboard-header{flex-direction:column;align-items:flex-start;gap:var(--space-md)}.header-actions{width:100%;justify-content:space-between}.metrics-grid{grid-template-columns:1fr}.summary-item{grid-template-columns:1fr 1fr;gap:var(--space-sm)}.summary-item>:nth-child(n+4){display:none}}
  #|    @media(prefers-reduced-motion:reduce){.metric-card,.summary-item,.btn-sync,.btn-connect{animation:none;transition:none}.progress-ring-fill{transition:none}.auth-status.connected::before{animation:none}}
  #|  </style>
  #|  __LUNA_HEAD__
  #|</head>
  #|<body>
  #|  <div id="__sol__">__LUNA_MAIN__</div>
  #|  <script src="/loader.js"></script>
  #|</body>
  #|</html>

///|
pub fn config() -> @router.RouterConfig {
  @router.RouterConfig::default()
  .with_root_template(ROOT)
  .with_loader_url("/loader.js")
}

// =============================================================================
// Action Registry (empty for now - no server actions needed)
// =============================================================================

///|
pub fn action_registry() -> @action.ActionRegistry {
  @action.ActionRegistry::new()
}
