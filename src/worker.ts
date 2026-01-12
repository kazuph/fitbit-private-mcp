import { Hono } from 'hono';
import { basicAuth } from 'hono/basic-auth';
import { timingSafeEqual } from 'hono/utils/buffer';
import { cors } from 'hono/cors';
import { configure_app } from '../target/js/release/build/__gen__/server/server.js';
import {
  postErrorToSlack, postToSlack, exchangeAuthCode, saveOAuthToken,
  getValidAccessToken, calculateExpiry, syncHealthData, updateDailySummary, postDailyHealthReport,
} from './services/moonbit-wrapper.js';

type Env = {
  DB: D1Database; BASIC_AUTH_USER: string; BASIC_AUTH_PASS: string;
  FITBIT_CLIENT_ID: string; FITBIT_CLIENT_SECRET: string; FITBIT_REDIRECT_URI: string;
  MCP_API_KEY: string; SLACK_BOT_TOKEN?: string; SLACK_CHANNEL?: string; GEMINI_API_KEY?: string;
};

const secureCompare = async (a: string | undefined, b: string | undefined) => typeof a === 'string' && typeof b === 'string' && await timingSafeEqual(a, b);
const escapeHtml = (s: string) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#039;');

const setEnv = (env: Env) => { (globalThis as any).__ENV = env; (globalThis as any).__D1_DB = env.DB; };

const app = new Hono<{ Bindings: Env }>();

app.use('/mcp/*', cors({ origin: '*', allowMethods: ['GET', 'POST', 'OPTIONS'], allowHeaders: ['Authorization', 'Content-Type'] }));

app.use('/mcp/*', async (c, next) => {
  const auth = c.req.header('Authorization');
  if (!auth) return c.json({ error: 'Authorization required' }, 401);
  const token = auth.replace(/^(Bearer|ApiKey)\s+/i, '');
  if (!await secureCompare(token, c.env.MCP_API_KEY)) return c.json({ error: 'Invalid API key' }, 401);
  await next();
});

app.use('/*', async (c, next) => {
  const p = c.req.path;
  if (p.startsWith('/mcp') || p.startsWith('/auth/callback') || /\.(js|css|map)$/.test(p)) return next();
  return basicAuth({
    verifyUser: async (u, pw) => await secureCompare(u, c.env.BASIC_AUTH_USER) && await secureCompare(pw, c.env.BASIC_AUTH_PASS),
    realm: 'Fitbit Health Dashboard',
  })(c, next);
});

app.get('/auth/fitbit', (c) => {
  const u = new URL('https://www.fitbit.com/oauth2/authorize');
  u.searchParams.set('response_type', 'code'); u.searchParams.set('client_id', c.env.FITBIT_CLIENT_ID);
  u.searchParams.set('redirect_uri', c.env.FITBIT_REDIRECT_URI); u.searchParams.set('scope', 'activity heartrate sleep weight profile cardio_fitness oxygen_saturation');
  return c.redirect(u.toString());
});

app.get('/auth/callback', async (c) => {
  const code = c.req.query('code'), error = c.req.query('error');
  if (error) return c.html(`<h1>Failed</h1><p>${escapeHtml(error)}</p><a href="/">Back</a>`);
  if (!code) return c.html(`<h1>Missing Code</h1><a href="/">Back</a>`);
  try {
    setEnv(c.env);
    const tokens = await exchangeAuthCode(code, c.env.FITBIT_REDIRECT_URI);
    if (!tokens) throw new Error('Token exchange failed');
    await saveOAuthToken('default', tokens.access_token, tokens.refresh_token, calculateExpiry(tokens.expires_in), tokens.scope || '');
    return c.redirect('/?auth=success');
  } catch (err) {
    return c.html(`<h1>Error</h1><p>${escapeHtml(err instanceof Error ? err.message : 'Unknown')}</p><a href="/">Back</a>`);
  }
});

const isForm = (c: { req: { header: (n: string) => string | undefined } }) => {
  const a = c.req.header('Accept') || ''; return a.includes('text/html') || !a.includes('application/json');
};

app.post('/api/sync', async (c) => {
  const form = isForm(c);
  try {
    setEnv(c.env);
    const [token, err] = await getValidAccessToken('default');
    if (err || !token) {
      const e = err === 'Not authenticated' ? 'not_authenticated' : 'token_refresh_failed';
      return form ? c.redirect(`/?error=${e}`) : c.json({ success: false, error: err || 'Auth failed' }, 401);
    }
    const today = new Date().toISOString().split('T')[0];
    const [vo2, spo2] = await syncHealthData(token, today);
    await updateDailySummary(today, vo2, spo2);
    return form ? c.redirect('/?sync=success') : c.json({ success: true, date: today });
  } catch (err) {
    return form ? c.redirect('/?error=sync_failed') : c.json({ success: false, error: String(err) }, 500);
  }
});

app.post('/api/test-slack', async (c) => { setEnv(c.env); return c.json({ success: await postToSlack('🧪 Slack test') }); });
app.post('/api/test-report', async (c) => { setEnv(c.env); await postDailyHealthReport(); return c.json({ success: true }); });

configure_app(app);

export default {
  fetch: async (req: Request, env: Env, ctx: ExecutionContext) => {
    setEnv(env);
    const res = await app.fetch(req, env, ctx);
    const url = new URL(req.url);
    if (url.pathname.endsWith('.js') && res.headers.get('content-type')?.includes('text/plain')) {
      const h = new Headers(res.headers); h.set('content-type', 'application/javascript');
      return new Response(res.body, { status: res.status, headers: h });
    }
    return res;
  },
  scheduled: async (_: ScheduledEvent, env: Env, ctx: ExecutionContext) => {
    setEnv(env);
    try {
      const [token] = await getValidAccessToken('default');
      if (token) { const d = new Date().toISOString().split('T')[0]; const [vo2, spo2] = await syncHealthData(token, d); await updateDailySummary(d, vo2, spo2); }
      if (new Date().getUTCHours() === 22) ctx.waitUntil(postDailyHealthReport());
    } catch (e) { ctx.waitUntil(postErrorToSlack(e as Error, 'Cron')); }
  },
};
