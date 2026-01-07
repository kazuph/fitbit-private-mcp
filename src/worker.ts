/**
 * Fitbit Private MCP - Cloudflare Worker Entry Point
 *
 * Authentication middleware and OAuth/Sync routes.
 * Dashboard UI and MCP API endpoints are implemented in MoonBit.
 */
import { Hono } from 'hono';
import { basicAuth } from 'hono/basic-auth';
import { timingSafeEqual } from 'hono/utils/buffer';
import { cors } from 'hono/cors';
import { configure_app } from '../target/js/release/build/__gen__/server/server.js';

type Env = {
  DB: D1Database;
  BASIC_AUTH_USER: string;
  BASIC_AUTH_PASS: string;
  FITBIT_CLIENT_ID: string;
  FITBIT_CLIENT_SECRET: string;
  FITBIT_REDIRECT_URI: string;
  MCP_API_KEY: string;
};

// Timing-safe comparison
const secureCompare = async (a: string | undefined, b: string | undefined): Promise<boolean> => {
  if (typeof a !== 'string' || typeof b !== 'string') return false;
  return await timingSafeEqual(a, b);
};

// HTML escape helper
const escapeHtml = (s: string): string =>
  s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
   .replace(/"/g, '&quot;').replace(/'/g, '&#039;');

const app = new Hono<{ Bindings: Env }>();

// CORS for MCP
app.use('/mcp/*', cors({ origin: '*', allowMethods: ['GET', 'POST', 'OPTIONS'], allowHeaders: ['Authorization', 'Content-Type'] }));

// API Key auth for MCP
app.use('/mcp/*', async (c, next) => {
  const authHeader = c.req.header('Authorization');
  if (!authHeader) return c.json({ error: 'Authorization header required' }, 401);
  const token = authHeader.replace(/^(Bearer|ApiKey)\s+/i, '');
  if (!await secureCompare(token, c.env.MCP_API_KEY)) return c.json({ error: 'Invalid API key' }, 401);
  await next();
});

// Basic Auth
app.use('/*', async (c, next) => {
  const path = c.req.path;
  if (path.startsWith('/mcp') || path.startsWith('/auth/callback') ||
      path.endsWith('.js') || path.endsWith('.css') || path.endsWith('.map') || path === '/robots.txt') return next();
  return basicAuth({
    verifyUser: async (u, p) => await secureCompare(u, c.env.BASIC_AUTH_USER) && await secureCompare(p, c.env.BASIC_AUTH_PASS),
    realm: 'Fitbit Health Dashboard',
  })(c, next);
});

// OAuth: Start
app.get('/auth/fitbit', (c) => {
  const url = new URL('https://www.fitbit.com/oauth2/authorize');
  url.searchParams.set('response_type', 'code');
  url.searchParams.set('client_id', c.env.FITBIT_CLIENT_ID);
  url.searchParams.set('redirect_uri', c.env.FITBIT_REDIRECT_URI);
  url.searchParams.set('scope', 'activity heartrate sleep weight profile');
  return c.redirect(url.toString());
});

// OAuth: Callback
app.get('/auth/callback', async (c) => {
  const code = c.req.query('code'), error = c.req.query('error');
  if (error) return c.html(`<h1>Error</h1><p>${escapeHtml(error)}</p><a href="/">Back</a>`);
  if (!code) return c.html(`<h1>Missing Code</h1><a href="/">Back</a>`);
  try {
    const auth = btoa(`${c.env.FITBIT_CLIENT_ID}:${c.env.FITBIT_CLIENT_SECRET}`);
    const res = await fetch('https://api.fitbit.com/oauth2/token', {
      method: 'POST', headers: { 'Authorization': `Basic ${auth}`, 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({ grant_type: 'authorization_code', code, redirect_uri: c.env.FITBIT_REDIRECT_URI }),
    });
    if (!res.ok) throw new Error(await res.text());
    const t = await res.json() as { access_token: string; refresh_token: string; expires_in: number; scope: string };
    const expiresAt = new Date(Date.now() + t.expires_in * 1000).toISOString();
    await c.env.DB.prepare(`INSERT INTO oauth_tokens (user_id, access_token, refresh_token, expires_at, scope) VALUES (?, ?, ?, ?, ?)
      ON CONFLICT(user_id) DO UPDATE SET access_token=excluded.access_token, refresh_token=excluded.refresh_token, expires_at=excluded.expires_at, scope=excluded.scope`)
      .bind('default', t.access_token, t.refresh_token, expiresAt, t.scope).run();
    return c.redirect('/?auth=success');
  } catch (e) { return c.html(`<h1>Error</h1><p>${escapeHtml(String(e))}</p><a href="/">Back</a>`); }
});

// Sync
app.post('/api/sync', async (c) => {
  const db = c.env.DB;
  const fromForm = (c.req.header('Accept') || '').includes('text/html');
  try {
    const tok = await db.prepare('SELECT * FROM oauth_tokens WHERE user_id = ?').bind('default').first();
    if (!tok) return fromForm ? c.redirect('/?error=not_authenticated') : c.json({ success: false, error: 'Not authenticated' }, 401);
    let accessToken = tok.access_token as string;
    if (new Date(tok.expires_at as string) < new Date()) {
      const auth = btoa(`${c.env.FITBIT_CLIENT_ID}:${c.env.FITBIT_CLIENT_SECRET}`);
      const res = await fetch('https://api.fitbit.com/oauth2/token', {
        method: 'POST', headers: { 'Authorization': `Basic ${auth}`, 'Content-Type': 'application/x-www-form-urlencoded' },
        body: new URLSearchParams({ grant_type: 'refresh_token', refresh_token: tok.refresh_token as string }),
      });
      if (!res.ok) return fromForm ? c.redirect('/?error=token_refresh_failed') : c.json({ success: false, error: 'Token refresh failed' }, 401);
      const nt = await res.json() as { access_token: string; refresh_token: string; expires_in: number };
      accessToken = nt.access_token;
      await db.prepare('UPDATE oauth_tokens SET access_token=?, refresh_token=?, expires_at=? WHERE user_id=?')
        .bind(accessToken, nt.refresh_token, new Date(Date.now() + nt.expires_in * 1000).toISOString(), 'default').run();
    }
    const today = new Date().toISOString().split('T')[0];
    const headers = { 'Authorization': `Bearer ${accessToken}` };
    const [actRes, sleepRes, hrRes, wtRes] = await Promise.all([
      fetch(`https://api.fitbit.com/1/user/-/activities/date/${today}.json`, { headers }),
      fetch(`https://api.fitbit.com/1.2/user/-/sleep/date/${today}.json`, { headers }),
      fetch(`https://api.fitbit.com/1/user/-/activities/heart/date/${today}/1d.json`, { headers }),
      fetch(`https://api.fitbit.com/1/user/-/body/log/weight/date/${today}/30d.json`, { headers }),
    ]);
    if (actRes.ok) {
      const d = await actRes.json() as any, s = d.summary;
      await db.prepare(`INSERT INTO daily_activity (date, steps, calories_out, distance, floors, sedentary_minutes, lightly_active_minutes, fairly_active_minutes, very_active_minutes, raw_data) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?) ON CONFLICT(date) DO UPDATE SET steps=excluded.steps, calories_out=excluded.calories_out, distance=excluded.distance, floors=excluded.floors, sedentary_minutes=excluded.sedentary_minutes, lightly_active_minutes=excluded.lightly_active_minutes, fairly_active_minutes=excluded.fairly_active_minutes, very_active_minutes=excluded.very_active_minutes, raw_data=excluded.raw_data`)
        .bind(today, s?.steps||0, s?.caloriesOut||0, s?.distances?.find((x:any)=>x.activity==='total')?.distance||0, s?.floors||0, s?.sedentaryMinutes||0, s?.lightlyActiveMinutes||0, s?.fairlyActiveMinutes||0, s?.veryActiveMinutes||0, JSON.stringify(d)).run();
    }
    if (sleepRes.ok) {
      const d = await sleepRes.json() as any, sl = d.sleep?.[0], st = d.summary?.stages;
      if (sl) await db.prepare(`INSERT INTO sleep_data (date, start_time, end_time, duration_minutes, efficiency, deep_minutes, light_minutes, rem_minutes, wake_minutes, raw_data) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?) ON CONFLICT(date) DO UPDATE SET start_time=excluded.start_time, end_time=excluded.end_time, duration_minutes=excluded.duration_minutes, efficiency=excluded.efficiency, deep_minutes=excluded.deep_minutes, light_minutes=excluded.light_minutes, rem_minutes=excluded.rem_minutes, wake_minutes=excluded.wake_minutes, raw_data=excluded.raw_data`)
        .bind(today, sl.startTime, sl.endTime, Math.round((sl.duration||0)/60000), sl.efficiency, st?.deep||0, st?.light||0, st?.rem||0, st?.wake||0, JSON.stringify(d)).run();
    }
    if (hrRes.ok) {
      const d = await hrRes.json() as any, v = d['activities-heart']?.[0]?.value, z = v?.heartRateZones||[];
      if (v) await db.prepare(`INSERT INTO heart_rate (date, resting_heart_rate, out_of_range_minutes, fat_burn_minutes, cardio_minutes, peak_minutes, raw_data) VALUES (?, ?, ?, ?, ?, ?, ?) ON CONFLICT(date) DO UPDATE SET resting_heart_rate=excluded.resting_heart_rate, out_of_range_minutes=excluded.out_of_range_minutes, fat_burn_minutes=excluded.fat_burn_minutes, cardio_minutes=excluded.cardio_minutes, peak_minutes=excluded.peak_minutes, raw_data=excluded.raw_data`)
        .bind(today, v.restingHeartRate||null, z.find((x:any)=>x.name==='Out of Range')?.minutes||0, z.find((x:any)=>x.name==='Fat Burn')?.minutes||0, z.find((x:any)=>x.name==='Cardio')?.minutes||0, z.find((x:any)=>x.name==='Peak')?.minutes||0, JSON.stringify(d)).run();
    }
    if (wtRes.ok) {
      const d = await wtRes.json() as any;
      for (const w of d.weight||[]) await db.prepare(`INSERT INTO weight_data (date, weight, bmi, fat_percent, raw_data) VALUES (?, ?, ?, ?, ?) ON CONFLICT(date) DO UPDATE SET weight=excluded.weight, bmi=excluded.bmi, fat_percent=excluded.fat_percent, raw_data=excluded.raw_data`)
        .bind(w.date, w.weight, w.bmi, w.fat, JSON.stringify(w)).run();
    }
    // Update summary
    const [act, slp, hr, wt] = await Promise.all([
      db.prepare('SELECT * FROM daily_activity WHERE date=?').bind(today).first(),
      db.prepare('SELECT * FROM sleep_data WHERE date=?').bind(today).first(),
      db.prepare('SELECT * FROM heart_rate WHERE date=?').bind(today).first(),
      db.prepare('SELECT * FROM weight_data WHERE date=? ORDER BY created_at DESC LIMIT 1').bind(today).first(),
    ]);
    await db.prepare(`INSERT INTO daily_summary (date, steps, calories, distance, active_minutes, resting_heart_rate, sleep_duration_minutes, sleep_efficiency, weight) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?) ON CONFLICT(date) DO UPDATE SET steps=excluded.steps, calories=excluded.calories, distance=excluded.distance, active_minutes=excluded.active_minutes, resting_heart_rate=excluded.resting_heart_rate, sleep_duration_minutes=excluded.sleep_duration_minutes, sleep_efficiency=excluded.sleep_efficiency, weight=excluded.weight`)
      .bind(today, (act?.steps as number)||0, (act?.calories_out as number)||0, (act?.distance as number)||0, ((act?.fairly_active_minutes as number)||0)+((act?.very_active_minutes as number)||0), (hr?.resting_heart_rate as number)||null, (slp?.duration_minutes as number)||0, (slp?.efficiency as number)||null, (wt?.weight as number)||null).run();
    return fromForm ? c.redirect('/?sync=success') : c.json({ success: true, date: today });
  } catch (e) { return fromForm ? c.redirect('/?error=sync_failed') : c.json({ success: false, error: String(e) }, 500); }
});

// MoonBit routes
configure_app(app);

export default {
  fetch: async (request: Request, env: Env, ctx: ExecutionContext): Promise<Response> => {
    (globalThis as any).__D1_DB = env.DB;
    (globalThis as any).__WORKER_ENV = env;
    const response = await app.fetch(request, env, ctx);
    const url = new URL(request.url);
    if (url.pathname.endsWith('.js') && response.headers.get('content-type')?.includes('text/plain')) {
      const headers = new Headers(response.headers);
      headers.set('content-type', 'application/javascript');
      return new Response(response.body, { status: response.status, headers });
    }
    return response;
  },
  scheduled: async (event: ScheduledEvent, env: Env, ctx: ExecutionContext) => {
    (globalThis as any).__D1_DB = env.DB;
    (globalThis as any).__WORKER_ENV = env;
    await app.fetch(new Request('https://internal/api/sync', { method: 'POST', headers: { 'Authorization': `Basic ${btoa(`${env.BASIC_AUTH_USER}:${env.BASIC_AUTH_PASS}`)}` } }), env, ctx);
  },
};
