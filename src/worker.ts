import { Hono } from 'hono';
import { AsyncLocalStorage } from 'node:async_hooks';
import { basicAuth } from 'hono/basic-auth';
import { timingSafeEqual } from 'hono/utils/buffer';
import { cors } from 'hono/cors';
import '../_build/js/release/build/__gen__/server/server.js';

type WorkerEnv = Env & { SLACK_BOT_TOKEN?: string; GEMINI_API_KEY?: string };
type SolApp = {
  fetch(request: Request, env: WorkerEnv, ctx: ExecutionContext): Response | Promise<Response>;
};
type RequestState = { env: WorkerEnv; ctx: ExecutionContext };

const secureCompare = async (a: string | undefined, b: string | undefined) => typeof a === 'string' && typeof b === 'string' && await timingSafeEqual(a, b);
const escapeHtml = (s: string) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#039;');

const requestState = new AsyncLocalStorage<RequestState>();

declare global {
  var __FITBIT_WORKER_ENV__: (() => WorkerEnv | undefined) | undefined;
  var __FITBIT_D1_DB__: (() => D1Database | undefined) | undefined;
  var __SOL_APP__: SolApp | undefined;
}

globalThis.__FITBIT_WORKER_ENV__ = () => requestState.getStore()?.env;
globalThis.__FITBIT_D1_DB__ = () => requestState.getStore()?.env.DB;

const solApp = globalThis.__SOL_APP__;
if (!solApp) throw new Error('Sol app was not exported by the generated server module');

const app = new Hono<{ Bindings: WorkerEnv }>();

app.use('/mcp/*', cors({ origin: '*', allowMethods: ['GET', 'POST', 'OPTIONS'], allowHeaders: ['Authorization', 'Content-Type'] }));

app.use('/mcp/*', async (c, next) => {
  const auth = c.req.header('Authorization');
  if (!auth) return c.json({ error: 'Authorization required' }, 401);
  const token = auth.replace(/^(Bearer|ApiKey)\s+/i, '');
  if (!await secureCompare(token, c.env.MCP_API_KEY)) return c.json({ error: 'Invalid API key' }, 401);
  return next();
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
    const ctx = getExecutionContext();
    const url = new URL('/__internal/oauth', c.req.url);
    url.searchParams.set('code', code);
    const result = await runMoonTask<OAuthResult>(url, c.env, ctx);
    if (!result.success) throw new Error(result.error || 'Token exchange failed');
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
    const result = await runMoonTask<SyncResult>(new URL('/__internal/sync', c.req.url), c.env, getExecutionContext());
    if (!result.success) {
      const errorCode = result.error === 'Not authenticated' ? 'not_authenticated' : 'token_refresh_failed';
      return form ? c.redirect(`/?error=${errorCode}`) : c.json(result, 401);
    }
    return form ? c.redirect('/?sync=success') : c.json(result);
  } catch (err) {
    return form ? c.redirect('/?error=sync_failed') : c.json({ success: false, error: String(err) }, 500);
  }
});

app.post('/api/test-slack', async (c) => c.json(await runMoonTask<{ success: boolean }>(new URL('/__internal/test-slack', c.req.url), c.env, getExecutionContext())));
app.post('/api/test-report', async (c) => c.json(await runMoonTask<{ success: boolean }>(new URL('/__internal/test-report', c.req.url), c.env, getExecutionContext())));
app.post('/api/cron', async (c) => {
  return c.json(await runCron(c.req.url, c.env, getExecutionContext()));
});

app.all('*', (c) => {
  const ctx = requestState.getStore()?.ctx;
  if (!ctx) throw new Error('Workers execution context is unavailable');
  return solApp.fetch(c.req.raw, c.env, ctx);
});

type CronResult = { success: boolean; synced: boolean; reportQueued: boolean };
type SyncResult = { success: boolean; date: string; error?: string };
type OAuthResult = { success: boolean; error?: string };

const getExecutionContext = (): ExecutionContext => {
  const ctx = requestState.getStore()?.ctx;
  if (!ctx) throw new Error('Workers execution context is unavailable');
  return ctx;
};

const runMoonTask = async <T>(url: URL, env: WorkerEnv, ctx: ExecutionContext): Promise<T> => {
  const response = await solApp.fetch(new Request(url, { method: 'POST' }), env, ctx);
  if (!response.ok) throw new Error(`MoonBit task failed with HTTP ${response.status}`);
  return response.json<T>();
};

const runCron = async (requestUrl: string, env: WorkerEnv, ctx: ExecutionContext): Promise<CronResult> => {
  return runMoonTask<CronResult>(new URL('/__internal/cron', requestUrl), env, ctx);
};

export default {
  fetch: (req: Request, env: WorkerEnv, ctx: ExecutionContext) =>
    requestState.run({ env, ctx }, async () => {
      const res = await app.fetch(req, env, ctx);
      const url = new URL(req.url);
      if (url.pathname.endsWith('.js') && res.headers.get('content-type')?.includes('text/plain')) {
        const h = new Headers(res.headers); h.set('content-type', 'application/javascript');
        return new Response(res.body, { status: res.status, headers: h });
      }
      return res;
    }),
  scheduled: (_: ScheduledController, env: WorkerEnv, ctx: ExecutionContext) => {
    ctx.waitUntil(requestState.run({ env, ctx }, async () => {
      try {
        await runCron('https://scheduled.internal', env, ctx);
      } catch (e) {
        const errorUrl = new URL('/__internal/error', 'https://scheduled.internal');
        errorUrl.searchParams.set('message', e instanceof Error ? e.message : String(e));
        errorUrl.searchParams.set('context', 'Cron');
        try {
          await runMoonTask<{ success: boolean }>(errorUrl, env, ctx);
        } catch (notificationError) {
          console.error('Failed to report scheduled Worker error', notificationError);
        }
        throw e;
      }
    }));
  },
};
