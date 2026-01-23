import { defineConfig, devices } from '@playwright/test';
import * as dotenv from 'dotenv';

// Load environment variables from .env
dotenv.config();

export default defineConfig({
  testDir: './e2e',
  fullyParallel: false, // Sequential for OAuth tests
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  workers: 1, // Single worker for sequential OAuth flow
  reporter: 'html',
  use: {
    baseURL: 'http://localhost:18787',
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
    video: 'on-first-retry',
    // Basic Auth credentials from .env - send always to avoid timing issues
    httpCredentials: {
      username: process.env.BASIC_AUTH_USER || 'kazuph',
      password: process.env.BASIC_AUTH_PASS || '',
      send: 'always',
    },
  },
  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
    },
  ],
  // Start wrangler dev server before tests
  webServer: {
    command: 'npm run dev',
    url: 'http://localhost:18787',
    reuseExistingServer: !process.env.CI,
    timeout: 60000,
    env: {
      ...process.env,
    },
  },
});
