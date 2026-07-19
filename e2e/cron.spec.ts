import { test, expect } from '@playwright/test';

test('cron endpoint returns success', async ({ request }) => {
  const res = await request.post('/api/cron');
  expect(res.ok()).toBeTruthy();
  const json = await res.json();
  expect(json.success).toBe(true);
});
