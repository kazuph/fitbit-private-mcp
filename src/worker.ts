/**
 * Fitbit Private MCP - Cloudflare Worker Entry Point
 *
 * Features:
 * - Basic Auth for web dashboard (/)
 * - API Key Auth for MCP endpoint (/mcp)
 * - Fitbit OAuth 2.0 flow
 * - Cron-triggered data sync
 * - Daily Slack health report with Gemini analysis
 */
import { Hono } from 'hono';
import { basicAuth } from 'hono/basic-auth';
import { timingSafeEqual } from 'hono/utils/buffer';
import { cors } from 'hono/cors';
import { configure_app } from '../target/js/release/build/__gen__/server/server.js';
import { postHealthInsightsToSlack, postErrorToSlack } from './services/slack.js';
import { analyzeHealthData, type HealthSummary } from './services/gemini.js';

type Env = {
  DB: D1Database;
  BASIC_AUTH_USER: string;
  BASIC_AUTH_PASS: string;
  FITBIT_CLIENT_ID: string;
  FITBIT_CLIENT_SECRET: string;
  FITBIT_REDIRECT_URI: string;
  MCP_API_KEY: string;
  // Slack & Gemini
  SLACK_BOT_TOKEN?: string;
  SLACK_CHANNEL?: string;
  GEMINI_API_KEY?: string;
};

// Fitbit API Response Types
interface FitbitDistance {
  activity: string;
  distance: number;
}

interface FitbitActivitySummary {
  steps: number;
  caloriesOut: number;
  distances: FitbitDistance[];
  floors: number;
  sedentaryMinutes: number;
  lightlyActiveMinutes: number;
  fairlyActiveMinutes: number;
  veryActiveMinutes: number;
}

interface FitbitActivityResponse {
  summary: FitbitActivitySummary;
}

interface FitbitSleepStages {
  deep: number;
  light: number;
  rem: number;
  wake: number;
}

interface FitbitSleepEntry {
  startTime: string;
  endTime: string;
  duration: number;
  efficiency: number;
}

interface FitbitSleepResponse {
  sleep: FitbitSleepEntry[];
  summary: {
    stages: FitbitSleepStages;
  };
}

interface FitbitHeartRateZone {
  name: string;
  minutes: number;
}

interface FitbitHeartRateValue {
  restingHeartRate: number | null;
  heartRateZones: FitbitHeartRateZone[];
}

interface FitbitHeartRateResponse {
  'activities-heart': Array<{
    value: FitbitHeartRateValue;
  }>;
}

interface FitbitWeightEntry {
  date: string;
  weight: number;
  bmi: number;
  fat: number;
}

interface FitbitWeightResponse {
  weight: FitbitWeightEntry[];
}

// VO2max Response
interface FitbitVO2maxResponse {
  cardioScore: Array<{
    dateTime: string;
    value: {
      vo2Max: string;
    };
  }>;
}

// SpO2 Response
interface FitbitSpO2Response {
  dateTime: string;
  value: {
    avg: number;
    min: number;
    max: number;
  };
}

// Timing-safe comparison helper
const secureCompare = async (a: string | undefined, b: string | undefined): Promise<boolean> => {
  if (typeof a !== 'string' || typeof b !== 'string') return false;
  return await timingSafeEqual(a, b);
};

// HTML escape helper to prevent XSS
const escapeHtml = (unsafe: string): string => {
  return unsafe
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#039;');
};

// Create Hono app
const app = new Hono<{ Bindings: Env }>();

// CORS for MCP endpoint
app.use('/mcp/*', cors({
  origin: '*',
  allowMethods: ['GET', 'POST', 'OPTIONS'],
  allowHeaders: ['Authorization', 'Content-Type'],
}));

// API Key auth for MCP endpoint
app.use('/mcp/*', async (c, next) => {
  const authHeader = c.req.header('Authorization');
  if (!authHeader) {
    return c.json({ error: 'Authorization header required' }, 401);
  }

  // Support both "Bearer <token>" and "ApiKey <token>" formats
  const token = authHeader.replace(/^(Bearer|ApiKey)\s+/i, '');
  const isValid = await secureCompare(token, c.env.MCP_API_KEY);

  if (!isValid) {
    return c.json({ error: 'Invalid API key' }, 401);
  }

  await next();
});

// Basic Auth for dashboard and admin routes
app.use('/*', async (c, next) => {
  // Skip auth for MCP (handled above), OAuth callbacks, and static files
  const path = c.req.path;
  if (path.startsWith('/mcp') ||
      path.startsWith('/auth/callback') ||
      path.endsWith('.js') ||
      path.endsWith('.css') ||
      path.endsWith('.map')) {
    return next();
  }

  const auth = basicAuth({
    verifyUser: async (username, password) => {
      const userMatch = await secureCompare(username, c.env.BASIC_AUTH_USER);
      const passMatch = await secureCompare(password, c.env.BASIC_AUTH_PASS);
      return userMatch && passMatch;
    },
    realm: 'Fitbit Health Dashboard',
  });

  return auth(c, next);
});

// Fitbit OAuth: Start authorization
app.get('/auth/fitbit', (c) => {
  const clientId = c.env.FITBIT_CLIENT_ID;
  const redirectUri = c.env.FITBIT_REDIRECT_URI;
  // Extended scopes to include cardio_fitness (VO2max) and oxygen_saturation (SpO2)
  const scope = 'activity heartrate sleep weight profile cardio_fitness oxygen_saturation';

  const authUrl = new URL('https://www.fitbit.com/oauth2/authorize');
  authUrl.searchParams.set('response_type', 'code');
  authUrl.searchParams.set('client_id', clientId);
  authUrl.searchParams.set('redirect_uri', redirectUri);
  authUrl.searchParams.set('scope', scope);

  return c.redirect(authUrl.toString());
});

// Fitbit OAuth: Handle callback
app.get('/auth/callback', async (c) => {
  const code = c.req.query('code');
  const error = c.req.query('error');

  if (error) {
    return c.html(`<h1>Authorization Failed</h1><p>${escapeHtml(error)}</p><a href="/">Back to Dashboard</a>`);
  }

  if (!code) {
    return c.html(`<h1>Missing Code</h1><p>No authorization code received.</p><a href="/">Back to Dashboard</a>`);
  }

  try {
    const clientId = c.env.FITBIT_CLIENT_ID;
    const clientSecret = c.env.FITBIT_CLIENT_SECRET;
    const redirectUri = c.env.FITBIT_REDIRECT_URI;

    // Exchange code for tokens
    const basicAuthHeader = btoa(`${clientId}:${clientSecret}`);
    const tokenResponse = await fetch('https://api.fitbit.com/oauth2/token', {
      method: 'POST',
      headers: {
        'Authorization': `Basic ${basicAuthHeader}`,
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: new URLSearchParams({
        grant_type: 'authorization_code',
        code: code,
        redirect_uri: redirectUri,
      }),
    });

    if (!tokenResponse.ok) {
      const errorText = await tokenResponse.text();
      throw new Error(`Token exchange failed: ${errorText}`);
    }

    const tokens = await tokenResponse.json() as {
      access_token: string;
      refresh_token: string;
      expires_in: number;
      scope: string;
      user_id: string;
    };

    // Calculate expiry time
    const expiresAt = new Date(Date.now() + tokens.expires_in * 1000).toISOString();

    // Store tokens in D1
    const db = c.env.DB;
    await db.prepare(`
      INSERT INTO oauth_tokens (user_id, access_token, refresh_token, expires_at, scope)
      VALUES (?, ?, ?, ?, ?)
      ON CONFLICT(user_id) DO UPDATE SET
        access_token = excluded.access_token,
        refresh_token = excluded.refresh_token,
        expires_at = excluded.expires_at,
        scope = excluded.scope
    `).bind('default', tokens.access_token, tokens.refresh_token, expiresAt, tokens.scope).run();

    return c.redirect('/?auth=success');
  } catch (err) {
    console.error('OAuth callback error:', err);
    const message = err instanceof Error ? err.message : 'Unknown error';
    return c.html(`<h1>Error</h1><p>${escapeHtml(message)}</p><a href="/">Back to Dashboard</a>`);
  }
});

// Note: MCP API endpoints (/mcp/tools, /mcp/health, /mcp/activity, /mcp/sleep, /mcp/heartrate, /mcp/weight)
// are now implemented in MoonBit (app/server/api.mbt) and registered via configure_app()

// Helper to check if request is from browser form submission
const isFormSubmission = (c: { req: { header: (name: string) => string | undefined } }) => {
  const accept = c.req.header('Accept') || '';
  return accept.includes('text/html') || !accept.includes('application/json');
};

// API endpoint for manual data sync
app.post('/api/sync', async (c) => {
  const db = c.env.DB;
  const fromForm = isFormSubmission(c);

  try {
    // Get stored tokens
    const tokenResult = await db.prepare(
      'SELECT * FROM oauth_tokens WHERE user_id = ?'
    ).bind('default').first();

    if (!tokenResult) {
      if (fromForm) {
        return c.redirect('/?error=not_authenticated');
      }
      return c.json({ success: false, error: 'Not authenticated. Please connect Fitbit first.' }, 401);
    }

    let accessToken = tokenResult.access_token as string;
    const refreshToken = tokenResult.refresh_token as string;
    const expiresAt = new Date(tokenResult.expires_at as string);

    // Refresh token if expired
    if (expiresAt < new Date()) {
      const clientId = c.env.FITBIT_CLIENT_ID;
      const clientSecret = c.env.FITBIT_CLIENT_SECRET;
      const basicAuthHeader = btoa(`${clientId}:${clientSecret}`);

      const refreshResponse = await fetch('https://api.fitbit.com/oauth2/token', {
        method: 'POST',
        headers: {
          'Authorization': `Basic ${basicAuthHeader}`,
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: new URLSearchParams({
          grant_type: 'refresh_token',
          refresh_token: refreshToken,
        }),
      });

      if (!refreshResponse.ok) {
        if (fromForm) {
          return c.redirect('/?error=token_refresh_failed');
        }
        return c.json({ success: false, error: 'Token refresh failed. Please re-authenticate.' }, 401);
      }

      const newTokens = await refreshResponse.json() as {
        access_token: string;
        refresh_token: string;
        expires_in: number;
      };

      accessToken = newTokens.access_token;
      const newExpiresAt = new Date(Date.now() + newTokens.expires_in * 1000).toISOString();

      await db.prepare(`
        UPDATE oauth_tokens
        SET access_token = ?, refresh_token = ?, expires_at = ?
        WHERE user_id = ?
      `).bind(accessToken, newTokens.refresh_token, newExpiresAt, 'default').run();
    }

    // Fetch data from Fitbit API
    const today = new Date().toISOString().split('T')[0];
    const headers = { 'Authorization': `Bearer ${accessToken}` };

    // Fetch activity
    const activityResponse = await fetch(
      `https://api.fitbit.com/1/user/-/activities/date/${today}.json`,
      { headers }
    );

    // Fetch sleep
    const sleepResponse = await fetch(
      `https://api.fitbit.com/1.2/user/-/sleep/date/${today}.json`,
      { headers }
    );

    // Fetch heart rate
    const heartResponse = await fetch(
      `https://api.fitbit.com/1/user/-/activities/heart/date/${today}/1d.json`,
      { headers }
    );

    // Fetch weight (last 30 days)
    const weightResponse = await fetch(
      `https://api.fitbit.com/1/user/-/body/log/weight/date/${today}/30d.json`,
      { headers }
    );

    // Fetch VO2max
    const vo2maxResponse = await fetch(
      `https://api.fitbit.com/1/user/-/cardioscore/date/${today}.json`,
      { headers }
    );

    // Fetch SpO2
    const spo2Response = await fetch(
      `https://api.fitbit.com/1/user/-/spo2/date/${today}.json`,
      { headers }
    );

    // Process and store activity data
    if (activityResponse.ok) {
      const activityData = await activityResponse.json() as FitbitActivityResponse;
      const summary = activityData.summary;

      await db.prepare(`
        INSERT INTO daily_activity (date, steps, calories_out, distance, floors,
          sedentary_minutes, lightly_active_minutes, fairly_active_minutes, very_active_minutes, raw_data)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(date) DO UPDATE SET
          steps = excluded.steps, calories_out = excluded.calories_out,
          distance = excluded.distance, floors = excluded.floors,
          sedentary_minutes = excluded.sedentary_minutes,
          lightly_active_minutes = excluded.lightly_active_minutes,
          fairly_active_minutes = excluded.fairly_active_minutes,
          very_active_minutes = excluded.very_active_minutes,
          raw_data = excluded.raw_data
      `).bind(
        today,
        summary?.steps || 0,
        summary?.caloriesOut || 0,
        summary?.distances?.find((d: FitbitDistance) => d.activity === 'total')?.distance || 0,
        summary?.floors || 0,
        summary?.sedentaryMinutes || 0,
        summary?.lightlyActiveMinutes || 0,
        summary?.fairlyActiveMinutes || 0,
        summary?.veryActiveMinutes || 0,
        JSON.stringify(activityData)
      ).run();
    }

    // Process and store sleep data
    let sleepStages: FitbitSleepStages | null = null;
    if (sleepResponse.ok) {
      const sleepData = await sleepResponse.json() as FitbitSleepResponse;
      const sleep = sleepData.sleep?.[0];
      const stages = sleepData.summary?.stages;
      sleepStages = stages || null;

      if (sleep) {
        await db.prepare(`
          INSERT INTO sleep_data (date, start_time, end_time, duration_minutes, efficiency,
            deep_minutes, light_minutes, rem_minutes, wake_minutes, raw_data)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
          ON CONFLICT(date) DO UPDATE SET
            start_time = excluded.start_time, end_time = excluded.end_time,
            duration_minutes = excluded.duration_minutes, efficiency = excluded.efficiency,
            deep_minutes = excluded.deep_minutes, light_minutes = excluded.light_minutes,
            rem_minutes = excluded.rem_minutes, wake_minutes = excluded.wake_minutes,
            raw_data = excluded.raw_data
        `).bind(
          today,
          sleep.startTime,
          sleep.endTime,
          Math.round((sleep.duration || 0) / 60000),
          sleep.efficiency,
          stages?.deep || 0,
          stages?.light || 0,
          stages?.rem || 0,
          stages?.wake || 0,
          JSON.stringify(sleepData)
        ).run();
      }
    }

    // Process and store heart rate data
    let hrZones: { fat_burn: number; cardio: number; peak: number } | null = null;
    if (heartResponse.ok) {
      const heartData = await heartResponse.json() as FitbitHeartRateResponse;
      const hrValue = heartData['activities-heart']?.[0]?.value;

      if (hrValue) {
        const zones = hrValue.heartRateZones || [];
        hrZones = {
          fat_burn: zones.find((z: FitbitHeartRateZone) => z.name === 'Fat Burn')?.minutes || 0,
          cardio: zones.find((z: FitbitHeartRateZone) => z.name === 'Cardio')?.minutes || 0,
          peak: zones.find((z: FitbitHeartRateZone) => z.name === 'Peak')?.minutes || 0,
        };
        await db.prepare(`
          INSERT INTO heart_rate (date, resting_heart_rate, out_of_range_minutes,
            fat_burn_minutes, cardio_minutes, peak_minutes, raw_data)
          VALUES (?, ?, ?, ?, ?, ?, ?)
          ON CONFLICT(date) DO UPDATE SET
            resting_heart_rate = excluded.resting_heart_rate,
            out_of_range_minutes = excluded.out_of_range_minutes,
            fat_burn_minutes = excluded.fat_burn_minutes,
            cardio_minutes = excluded.cardio_minutes,
            peak_minutes = excluded.peak_minutes,
            raw_data = excluded.raw_data
        `).bind(
          today,
          hrValue.restingHeartRate || null,
          zones.find((z: FitbitHeartRateZone) => z.name === 'Out of Range')?.minutes || 0,
          hrZones.fat_burn,
          hrZones.cardio,
          hrZones.peak,
          JSON.stringify(heartData)
        ).run();
      }
    }

    // Process and store weight data
    if (weightResponse.ok) {
      const weightData = await weightResponse.json() as FitbitWeightResponse;
      const weights = weightData.weight || [];

      for (const w of weights) {
        await db.prepare(`
          INSERT INTO weight_data (date, weight, bmi, fat_percent, raw_data)
          VALUES (?, ?, ?, ?, ?)
          ON CONFLICT(date) DO UPDATE SET
            weight = excluded.weight, bmi = excluded.bmi,
            fat_percent = excluded.fat_percent, raw_data = excluded.raw_data
        `).bind(w.date, w.weight, w.bmi, w.fat, JSON.stringify(w)).run();
      }
    }

    // Process and store VO2max data
    let vo2maxValue: string | null = null;
    if (vo2maxResponse.ok) {
      const vo2maxData = await vo2maxResponse.json() as FitbitVO2maxResponse;
      const cardioScore = vo2maxData.cardioScore?.[0];

      if (cardioScore) {
        vo2maxValue = cardioScore.value.vo2Max;
        await db.prepare(`
          INSERT INTO vo2max_data (date, vo2max, raw_data)
          VALUES (?, ?, ?)
          ON CONFLICT(date) DO UPDATE SET
            vo2max = excluded.vo2max,
            raw_data = excluded.raw_data
        `).bind(cardioScore.dateTime, vo2maxValue, JSON.stringify(vo2maxData)).run();
      }
    }

    // Process and store SpO2 data
    let spo2Avg: number | null = null;
    if (spo2Response.ok) {
      const spo2Data = await spo2Response.json() as FitbitSpO2Response;

      if (spo2Data.value) {
        spo2Avg = spo2Data.value.avg;
        await db.prepare(`
          INSERT INTO spo2_data (date, avg, min, max, raw_data)
          VALUES (?, ?, ?, ?, ?)
          ON CONFLICT(date) DO UPDATE SET
            avg = excluded.avg,
            min = excluded.min,
            max = excluded.max,
            raw_data = excluded.raw_data
        `).bind(
          spo2Data.dateTime,
          spo2Data.value.avg,
          spo2Data.value.min,
          spo2Data.value.max,
          JSON.stringify(spo2Data)
        ).run();
      }
    }

    // Update daily summary with VO2max and SpO2
    await updateDailySummary(db, today, vo2maxValue, spo2Avg);

    if (fromForm) {
      return c.redirect('/?sync=success');
    }
    return c.json({ success: true, message: 'Data synced successfully', date: today });
  } catch (err) {
    console.error('Sync error:', err);
    if (fromForm) {
      return c.redirect('/?error=sync_failed');
    }
    return c.json({ success: false, error: String(err) }, 500);
  }
});

// Test Slack posting (for debugging) - protected by global basic auth middleware
app.post('/api/test-slack', async (c) => {
  try {
    const { postToSlack } = await import('./services/slack');
    const result = await postToSlack(c.env, '🧪 Fitbit Health Dashboard - Slack連携テスト\n\nこのメッセージが表示されていればSlack連携は正常に動作しています。');
    return c.json({ success: result, message: result ? 'Test message posted' : 'Failed to post' });
  } catch (err) {
    console.error('Slack test error:', err);
    return c.json({ success: false, error: String(err) }, 500);
  }
});

// Test daily report (for debugging - posts actual health data) - protected by global basic auth middleware
app.post('/api/test-report', async (c) => {
  try {
    await postDailyHealthReport(c.env);
    return c.json({ success: true, message: 'Daily report triggered' });
  } catch (err) {
    console.error('Report test error:', err);
    return c.json({ success: false, error: String(err) }, 500);
  }
});

// Helper function to update daily summary
async function updateDailySummary(
  db: D1Database,
  date: string,
  vo2max: string | null = null,
  spo2Avg: number | null = null
) {
  const activity = await db.prepare(
    'SELECT * FROM daily_activity WHERE date = ?'
  ).bind(date).first();

  const sleep = await db.prepare(
    'SELECT * FROM sleep_data WHERE date = ?'
  ).bind(date).first();

  const heart = await db.prepare(
    'SELECT * FROM heart_rate WHERE date = ?'
  ).bind(date).first();

  const weight = await db.prepare(
    'SELECT * FROM weight_data WHERE date = ? ORDER BY created_at DESC LIMIT 1'
  ).bind(date).first();

  const activeMinutes = (
    ((activity?.fairly_active_minutes as number) || 0) +
    ((activity?.very_active_minutes as number) || 0)
  );

  await db.prepare(`
    INSERT INTO daily_summary (date, steps, calories, distance, active_minutes,
      resting_heart_rate, sleep_duration_minutes, sleep_efficiency, weight, vo2max, spo2_avg)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT(date) DO UPDATE SET
      steps = excluded.steps, calories = excluded.calories,
      distance = excluded.distance, active_minutes = excluded.active_minutes,
      resting_heart_rate = excluded.resting_heart_rate,
      sleep_duration_minutes = excluded.sleep_duration_minutes,
      sleep_efficiency = excluded.sleep_efficiency,
      weight = excluded.weight,
      vo2max = excluded.vo2max,
      spo2_avg = excluded.spo2_avg
  `).bind(
    date,
    (activity?.steps as number) || 0,
    (activity?.calories_out as number) || 0,
    (activity?.distance as number) || 0,
    activeMinutes,
    (heart?.resting_heart_rate as number) || null,
    (sleep?.duration_minutes as number) || 0,
    (sleep?.efficiency as number) || null,
    (weight?.weight as number) || null,
    vo2max,
    spo2Avg
  ).run();
}

// Helper function to get yesterday's date in JST
function getYesterdayJST(): string {
  const now = new Date();
  // Convert to JST (UTC+9)
  const jstOffset = 9 * 60 * 60 * 1000;
  const jstNow = new Date(now.getTime() + jstOffset);
  jstNow.setDate(jstNow.getDate() - 1);
  return jstNow.toISOString().split('T')[0];
}

// Helper function to post daily health report to Slack
async function postDailyHealthReport(env: Env) {
  const db = env.DB;
  const yesterday = getYesterdayJST();

  try {
    // Check if already posted today
    const stateKey = 'slack:dailyReportDate';
    const lastPosted = await db.prepare(
      'SELECT value FROM sync_state WHERE key = ?'
    ).bind(stateKey).first();

    if (lastPosted?.value === yesterday) {
      console.log('Daily report already posted for:', yesterday);
      return;
    }

    // Get yesterday's summary
    const summary = await db.prepare(
      'SELECT * FROM daily_summary WHERE date = ?'
    ).bind(yesterday).first();

    if (!summary) {
      console.log('No summary data for:', yesterday);
      return;
    }

    // Get detailed data for Gemini analysis
    const sleep = await db.prepare(
      'SELECT * FROM sleep_data WHERE date = ?'
    ).bind(yesterday).first();

    const heart = await db.prepare(
      'SELECT * FROM heart_rate WHERE date = ?'
    ).bind(yesterday).first();

    // Build health summary for Gemini
    const healthData: HealthSummary = {
      date: yesterday,
      steps: (summary.steps as number) || 0,
      calories: (summary.calories as number) || 0,
      distance: (summary.distance as number) || 0,
      active_minutes: (summary.active_minutes as number) || 0,
      resting_heart_rate: (summary.resting_heart_rate as number) || null,
      sleep_duration_minutes: (summary.sleep_duration_minutes as number) || 0,
      sleep_efficiency: (summary.sleep_efficiency as number) || null,
      weight: (summary.weight as number) || null,
      vo2max: (summary.vo2max as string) || null,
      spo2_avg: (summary.spo2_avg as number) || null,
      sleep_stages: sleep ? {
        deep: (sleep.deep_minutes as number) || 0,
        light: (sleep.light_minutes as number) || 0,
        rem: (sleep.rem_minutes as number) || 0,
        wake: (sleep.wake_minutes as number) || 0,
      } : undefined,
      heart_rate_zones: heart ? {
        fat_burn: (heart.fat_burn_minutes as number) || 0,
        cardio: (heart.cardio_minutes as number) || 0,
        peak: (heart.peak_minutes as number) || 0,
      } : undefined,
    };

    // Analyze with Gemini
    const insights = await analyzeHealthData(env, healthData);

    if (insights) {
      // Post to Slack
      const posted = await postHealthInsightsToSlack(env, insights, yesterday);

      if (posted) {
        // Update state to prevent duplicate posts
        await db.prepare(`
          INSERT INTO sync_state (key, value, updated_at)
          VALUES (?, ?, datetime('now'))
          ON CONFLICT(key) DO UPDATE SET
            value = excluded.value,
            updated_at = excluded.updated_at
        `).bind(stateKey, yesterday).run();

        console.log('Daily health report posted for:', yesterday);
      }
    } else {
      console.log('Failed to generate insights for:', yesterday);
    }
  } catch (error) {
    console.error('Error posting daily health report:', error);
    await postErrorToSlack(env, error as Error, 'Daily Health Report');
  }
}

// Configure MoonBit/Luna routes for dashboard UI
configure_app(app);

// Export for Cloudflare Workers
export default {
  fetch: async (request: Request, env: Env, ctx: ExecutionContext): Promise<Response> => {
    (globalThis as any).__D1_DB = env.DB;

    const response = await app.fetch(request, env, ctx);

    // Fix MIME type for JS files
    const url = new URL(request.url);
    if (url.pathname.endsWith('.js') && response.headers.get('content-type')?.includes('text/plain')) {
      const headers = new Headers(response.headers);
      headers.set('content-type', 'application/javascript');
      return new Response(response.body, { status: response.status, statusText: response.statusText, headers });
    }

    return response;
  },

  // Cron trigger for automatic data sync and daily report
  scheduled: async (event: ScheduledEvent, env: Env, ctx: ExecutionContext) => {
    console.log('Cron triggered:', event.cron);

    (globalThis as any).__D1_DB = env.DB;

    // Create a mock request to trigger sync
    const syncRequest = new Request('https://internal/api/sync', {
      method: 'POST',
      headers: {
        'Authorization': `Basic ${btoa(`${env.BASIC_AUTH_USER}:${env.BASIC_AUTH_PASS}`)}`,
      },
    });

    try {
      await app.fetch(syncRequest, env, ctx);
      console.log('Cron sync completed successfully');

      // Check if it's morning report time (UTC 22:00 = JST 07:00)
      const now = new Date();
      const utcHour = now.getUTCHours();

      if (utcHour === 22) {
        console.log('Posting daily health report...');
        ctx.waitUntil(postDailyHealthReport(env));
      }
    } catch (err) {
      console.error('Cron sync failed:', err);
      ctx.waitUntil(postErrorToSlack(env, err as Error, 'Cron Sync'));
    }
  },
};
