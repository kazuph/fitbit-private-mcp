import { test, expect } from '@playwright/test';

test.describe('Dashboard UI Tests', () => {
  test.beforeEach(async ({ page }) => {
    // Navigate to dashboard (Basic Auth is handled by Playwright config)
    await page.goto('/');
  });

  test('should display dashboard header', async ({ page }) => {
    // Check that the page title is correct
    await expect(page).toHaveTitle('Health Dashboard');

    // Check that the dashboard title is visible
    await expect(page.locator('.dashboard-title')).toContainText('Health Dashboard');
  });

  test('should display navigation bar', async ({ page }) => {
    const nav = page.locator('.main-nav');
    await expect(nav).toBeVisible();

    // Check nav brand
    await expect(nav.locator('.nav-brand')).toContainText('Fitbit Health');

    // Check navigation links
    await expect(nav.locator('.nav-link.active')).toContainText('Dashboard');
    await expect(nav.locator('a[href="/auth/fitbit"]')).toContainText('Connect Fitbit');
  });

  test('should display empty state when not connected', async ({ page }) => {
    // When Fitbit is not connected, should show empty state
    const emptyState = page.locator('.empty-state');

    // Check if empty state or connected state exists
    const hasEmptyState = await emptyState.count() > 0;

    if (hasEmptyState) {
      await expect(emptyState).toBeVisible();
      await expect(emptyState.locator('.empty-state-title')).toContainText('Connect Your Fitbit');
      await expect(page.locator('.btn-connect')).toHaveAttribute('href', '/auth/fitbit');
    } else {
      // If connected, check for metrics grid
      await expect(page.locator('.metrics-grid')).toBeVisible();
    }
  });

  test('should protect dashboard with Basic Auth', async ({ browser }) => {
    // Create a new context without credentials
    const context = await browser.newContext({
      httpCredentials: undefined,
    });
    const page = await context.newPage();

    // Try to access without auth - should get 401
    const response = await page.goto('/');
    expect(response?.status()).toBe(401);

    await context.close();
  });

  test('should have responsive design elements', async ({ page }) => {
    // Check viewport meta
    const viewport = await page.locator('meta[name="viewport"]').getAttribute('content');
    expect(viewport).toContain('width=device-width');

    // Check CSS custom properties are applied
    const rootStyles = await page.evaluate(() => {
      return getComputedStyle(document.documentElement).getPropertyValue('--bg-deep');
    });
    expect(rootStyles.trim()).toBe('#0a0e1a');
  });

  test('should load Google Fonts', async ({ page }) => {
    // Check for preconnect and stylesheet links
    const fontLinks = page.locator('link[href*="fonts.googleapis"]');
    await expect(fontLinks).toHaveCount(2); // preconnect + stylesheet
  });
});

test.describe('Dashboard with Fitbit Connected', () => {
  // These tests will be run after OAuth is completed
  // They verify the dashboard shows health data correctly

  test.skip('should display metrics cards when connected', async ({ page }) => {
    // This test assumes Fitbit is connected and token exists
    await page.goto('/');

    // Check metrics grid exists
    const metricsGrid = page.locator('.metrics-grid');
    await expect(metricsGrid).toBeVisible();

    // Check all metric cards exist
    await expect(page.locator('.metric-card.steps')).toBeVisible();
    await expect(page.locator('.metric-card.calories')).toBeVisible();
    await expect(page.locator('.metric-card.sleep')).toBeVisible();
    await expect(page.locator('.metric-card.heartrate')).toBeVisible();
    await expect(page.locator('.metric-card.weight')).toBeVisible();
  });

  test.skip('should display daily summary section', async ({ page }) => {
    await page.goto('/');

    // Check summary section
    const summarySection = page.locator('.summary-section');
    await expect(summarySection).toBeVisible();
    await expect(summarySection.locator('.section-title')).toContainText('Daily Summary');
  });

  test.skip('should show sync button and status when connected', async ({ page }) => {
    await page.goto('/');

    // Check connected status
    await expect(page.locator('.auth-status.connected')).toBeVisible();

    // Check sync button
    await expect(page.locator('.btn-sync')).toBeVisible();
  });
});
