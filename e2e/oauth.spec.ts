import { test, expect, Page } from '@playwright/test';

/**
 * Fitbit OAuth E2E Tests
 *
 * These tests use the REAL Fitbit API - no mocks.
 * Prerequisites:
 * 1. Valid Fitbit credentials in .env (FITBIT_CLIENT_ID, FITBIT_CLIENT_SECRET)
 * 2. Fitbit developer app configured with redirect URI: http://localhost:8787/auth/callback
 * 3. Manual test: User needs to login to Fitbit during interactive test run
 */

test.describe('Fitbit OAuth Flow', () => {
  test.describe.configure({ mode: 'serial' });

  test('should redirect to Fitbit authorization page', async ({ page }) => {
    // Navigate to OAuth start endpoint
    const response = await page.goto('/auth/fitbit');

    // Should redirect to Fitbit (may go through login/transfer page)
    const url = page.url();
    expect(url).toContain('fitbit.com');
    // URL params may be encoded, check for client_id in decoded URL
    const decodedUrl = decodeURIComponent(url);
    expect(decodedUrl).toContain('client_id=23TVTM');
    expect(decodedUrl).toContain('response_type=code');
  });

  test('should include required OAuth scopes', async ({ page }) => {
    await page.goto('/auth/fitbit');

    const url = page.url();
    const scopes = ['activity', 'heartrate', 'sleep', 'weight', 'profile'];

    // Check that all required scopes are present
    for (const scope of scopes) {
      expect(url.toLowerCase()).toContain(scope);
    }
  });

  /**
   * Interactive OAuth Test
   *
   * This test requires manual interaction to login to Fitbit.
   * Run with: npx playwright test oauth.spec.ts --headed
   *
   * The test will:
   * 1. Start OAuth flow
   * 2. Wait for user to login to Fitbit (manual)
   * 3. Verify callback is received and token is stored
   */
  test.skip('should complete OAuth flow with manual login', async ({ page }) => {
    // Start OAuth flow
    await page.goto('/auth/fitbit');

    // Wait for user to complete Fitbit login
    // This is a manual step - user needs to login interactively
    console.log('Please login to Fitbit in the browser window...');

    // Wait for redirect back to our callback
    await page.waitForURL('**/auth/callback**', { timeout: 120000 });

    // After callback, should redirect to dashboard
    await page.waitForURL('/');

    // Dashboard should now show connected state
    await expect(page.locator('.auth-status.connected')).toBeVisible({ timeout: 10000 });
  });
});

test.describe('OAuth Callback Handling', () => {
  test('should reject callback without authorization code', async ({ page }) => {
    // Try callback without code parameter
    const response = await page.goto('/auth/callback');

    // Should return error or redirect with error (case insensitive check)
    const content = await page.content();
    expect(content.toLowerCase()).toContain('missing');
  });

  test('should reject callback with invalid state', async ({ page }) => {
    // Try callback with invalid state parameter
    const response = await page.goto('/auth/callback?code=fake_code&state=invalid_state');

    // Should return error
    const content = await page.content();
    expect(content.toLowerCase()).toContain('error');
  });
});

test.describe('OAuth Security', () => {
  test('should use PKCE (state parameter)', async ({ page }) => {
    await page.goto('/auth/fitbit');

    const url = page.url();
    const decodedUrl = decodeURIComponent(url);
    // State param should be present (may be double-encoded through login redirect)
    expect(decodedUrl.toLowerCase()).toContain('state');
  });

  test('should have correct redirect URI', async ({ page }) => {
    await page.goto('/auth/fitbit');

    const url = page.url();
    const decodedUrl = decodeURIComponent(url);
    // Redirect URI should be present (may be encoded through login redirect)
    expect(decodedUrl).toContain('redirect_uri');
    expect(decodedUrl).toContain('callback');
  });
});

/**
 * Token Management Tests
 *
 * These tests verify token storage and refresh behavior.
 * They require a valid token to be stored first.
 */
test.describe.skip('Token Management', () => {
  test('should store token in D1 database after successful auth', async ({ page, request }) => {
    // After OAuth completion, verify token exists via MCP endpoint
    const mcpApiKey = process.env.MCP_API_KEY || '';

    const response = await request.get('/mcp/health', {
      headers: {
        'Authorization': `Bearer ${mcpApiKey}`,
      },
    });

    expect(response.ok()).toBe(true);
    const data = await response.json();
    expect(data.success).toBe(true);
  });

  test('should refresh token when expired', async ({ page }) => {
    // This would require waiting for token to expire
    // or mocking the token expiry time
    // Skipped in automated tests
  });
});
