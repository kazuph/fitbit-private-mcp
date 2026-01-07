/**
 * Fitbit Private MCP - Cloudflare Worker Entry Point
 *
 * Minimal wrapper that configures authentication middleware.
 * Business logic (OAuth, Sync, MCP endpoints) is implemented in MoonBit.
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

// Timing-safe comparison helper
const secureCompare = async (a: string | undefined, b: string | undefined): Promise<boolean> => {
  if (typeof a !== 'string' || typeof b !== 'string') return false;
  return await timingSafeEqual(a, b);
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
      path.endsWith('.map') ||
      path === '/robots.txt') {
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

// Configure MoonBit/Luna routes (dashboard, OAuth, sync, MCP endpoints)
// All business logic is now implemented in MoonBit
configure_app(app);

// Export for Cloudflare Workers
export default {
  fetch: async (request: Request, env: Env, ctx: ExecutionContext): Promise<Response> => {
    // Set D1 binding for database access
    (globalThis as any).__D1_DB = env.DB;
    // Set environment for MoonBit OAuth/Sync access
    (globalThis as any).__WORKER_ENV = env;

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

  // Cron trigger for automatic data sync
  scheduled: async (event: ScheduledEvent, env: Env, ctx: ExecutionContext) => {
    console.log('Cron triggered:', event.cron);

    (globalThis as any).__D1_DB = env.DB;
    (globalThis as any).__WORKER_ENV = env;

    // Call the MoonBit-implemented sync endpoint
    const syncRequest = new Request('https://internal/api/sync', {
      method: 'POST',
      headers: {
        'Authorization': `Basic ${btoa(`${env.BASIC_AUTH_USER}:${env.BASIC_AUTH_PASS}`)}`,
      },
    });

    try {
      await app.fetch(syncRequest, env, ctx);
      console.log('Cron sync completed successfully');
    } catch (err) {
      console.error('Cron sync failed:', err);
    }
  },
};
