import { test, expect } from '@playwright/test';

test.describe('Dashboard UI Tests', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/');
  });

  test('should display dashboard header', async ({ page }) => {
    // Check that the page title is correct
    await expect(page).toHaveTitle('健康アクション ダッシュボード');

    // Check that the dashboard title is visible
    await expect(page.locator('.dashboard-title')).toContainText(/健康アクション/);
  });

  test('should display navigation bar', async ({ page }) => {
    const nav = page.locator('.main-nav');
    await expect(nav).toBeVisible();

    // Check nav brand
    await expect(nav.locator('.nav-brand')).toContainText('Fitbit 健康アクション');

    // Check navigation links
    await expect(nav.locator('.nav-link.active')).toContainText('記録と提案');
    await expect(nav.locator('a[href="/auth/fitbit"]')).toContainText('Fitbitを連携');
  });

  test('should display empty state when not connected', async ({ page }) => {
    // When Fitbit is not connected, should show empty state
    const emptyState = page.locator('.empty-state');

    // Check if empty state or connected state exists
    const hasEmptyState = await emptyState.count() > 0;

    if (hasEmptyState) {
      await expect(emptyState).toBeVisible();
      await expect(emptyState.locator('.empty-state-title')).toContainText('Fitbitを連携する');
      await expect(page.locator('.btn-connect')).toHaveAttribute('href', '/auth/fitbit');
    } else {
      // If connected, check for metrics grid
      await expect(page.locator('.metrics-grid')).toBeVisible();
    }
  });

  test('should render without Basic Auth', async ({ page }) => {
    const response = await page.goto('/');
    expect(response?.status()).toBe(200);
  });

  test('should have responsive design elements', async ({ page }) => {
    // Check viewport meta
    const viewport = await page.locator('meta[name="viewport"]').getAttribute('content');
    expect(viewport).toContain('width=device-width');

    // Check CSS custom properties are applied
    const rootStyles = await page.evaluate(() => {
      return getComputedStyle(document.documentElement).getPropertyValue('--paper');
    });
    expect(rootStyles.trim()).toBe('#f7f6f0');
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
    await expect(summarySection.locator('.section-title')).toContainText('最近の記録');
  });

  test.skip('should show sync button and status when connected', async ({ page }) => {
    await page.goto('/');

    // Check connected status
    await expect(page.locator('.auth-status.connected')).toBeVisible();

    // Check sync button
    await expect(page.locator('.btn-sync')).toBeVisible();
  });
});
