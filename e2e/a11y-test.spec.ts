import { test, expect } from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';
import fs from 'fs';
import * as dotenv from 'dotenv';

// Load environment variables
dotenv.config();

test.describe('A11y & UX Review', () => {
  // Use httpCredentials from playwright.config.ts (configured via environment variables)

  test('Full accessibility scan with axe-core', async ({ page }) => {
    // Navigate to dashboard
    await page.goto('/');
    await page.waitForLoadState('networkidle');

    // Run axe accessibility scan
    const accessibilityScanResults = await new AxeBuilder({ page })
      .withTags(['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa', 'wcag22aa'])
      .analyze();

    // Log violations to console for review
    console.log('\n========== AXE-CORE VIOLATIONS ==========');
    console.log(`Total violations: ${accessibilityScanResults.violations.length}`);

    accessibilityScanResults.violations.forEach((violation, index) => {
      console.log(`\n--- Violation ${index + 1} ---`);
      console.log(`ID: ${violation.id}`);
      console.log(`Impact: ${violation.impact}`);
      console.log(`Description: ${violation.description}`);
      console.log(`Help: ${violation.help}`);
      console.log(`Help URL: ${violation.helpUrl}`);
      console.log(`WCAG Tags: ${violation.tags.join(', ')}`);
      console.log(`Nodes affected: ${violation.nodes.length}`);

      violation.nodes.forEach((node, nodeIndex) => {
        console.log(`  Node ${nodeIndex + 1}:`);
        console.log(`    Target: ${node.target.join(', ')}`);
        console.log(`    HTML: ${node.html.substring(0, 100)}${node.html.length > 100 ? '...' : ''}`);
        console.log(`    Failure: ${node.failureSummary}`);
      });
    });

    // Log passes for reference
    console.log(`\n========== PASSES ==========`);
    console.log(`Total passes: ${accessibilityScanResults.passes.length}`);
    accessibilityScanResults.passes.forEach(pass => {
      console.log(`  - ${pass.id}: ${pass.help}`);
    });

    // Log incomplete checks
    console.log(`\n========== INCOMPLETE CHECKS ==========`);
    console.log(`Total incomplete: ${accessibilityScanResults.incomplete.length}`);
    accessibilityScanResults.incomplete.forEach(incomplete => {
      console.log(`  - ${incomplete.id}: ${incomplete.help}`);
    });

    // Save detailed report to file
    const reportPath = '/tmp/axe-report.json';
    fs.writeFileSync(reportPath, JSON.stringify(accessibilityScanResults, null, 2));
    console.log(`\nDetailed report saved to: ${reportPath}`);
  });

  test('Keyboard navigation and focus management', async ({ page }) => {
    await page.goto('/');
    await page.waitForLoadState('networkidle');

    console.log('\n========== KEYBOARD NAVIGATION TEST ==========');

    // Get all focusable elements
    const focusableElements = await page.evaluate(() => {
      const focusable = Array.from(
        document.querySelectorAll('a, button, input, select, textarea, [tabindex]:not([tabindex="-1"])')
      );
      return focusable.map((el, index) => ({
        index,
        tag: el.tagName,
        id: el.id,
        class: el.className,
        text: el.textContent?.trim().substring(0, 50),
        tabindex: el.getAttribute('tabindex'),
        ariaLabel: el.getAttribute('aria-label'),
        role: el.getAttribute('role'),
      }));
    });

    console.log(`Total focusable elements: ${focusableElements.length}`);
    focusableElements.forEach(el => {
      console.log(`  [${el.index}] ${el.tag}: ${el.text || el.ariaLabel || el.id || '(no label)'}`);
    });

    // Test tab navigation
    console.log('\n--- Tab Navigation Order ---');
    for (let i = 0; i < Math.min(focusableElements.length, 10); i++) {
      await page.keyboard.press('Tab');

      const focused = await page.evaluate(() => {
        const el = document.activeElement;
        if (!el) return null;
        return {
          tag: el.tagName,
          text: el.textContent?.trim().substring(0, 50),
          id: el.id,
          class: el.className,
        };
      });

      console.log(`  Tab ${i + 1}: ${focused?.tag} - ${focused?.text || focused?.id || focused?.class}`);

      // Check if focus indicator is visible
      const hasVisibleFocus = await page.evaluate(() => {
        const el = document.activeElement;
        if (!el) return false;
        const styles = window.getComputedStyle(el);
        const outline = styles.outline;
        const boxShadow = styles.boxShadow;
        return outline !== 'none' || boxShadow !== 'none';
      });

      if (!hasVisibleFocus) {
        console.log(`    ⚠️  NO VISIBLE FOCUS INDICATOR`);
      }
    }

    // Test Shift+Tab reverse navigation
    console.log('\n--- Shift+Tab Reverse Navigation ---');
    for (let i = 0; i < 3; i++) {
      await page.keyboard.press('Shift+Tab');
      const focused = await page.evaluate(() => {
        const el = document.activeElement;
        return el ? `${el.tagName} - ${el.textContent?.trim().substring(0, 30)}` : 'none';
      });
      console.log(`  Shift+Tab ${i + 1}: ${focused}`);
    }

    // Screenshot with focus indicator
    await page.keyboard.press('Tab');
    await page.screenshot({ path: '/tmp/focus-indicator.png', fullPage: false });
    console.log('\nFocus indicator screenshot saved to: /tmp/focus-indicator.png');
  });

  test('ARIA attributes and semantic HTML', async ({ page }) => {
    await page.goto('/');
    await page.waitForLoadState('networkidle');

    console.log('\n========== ARIA & SEMANTIC HTML TEST ==========');

    // Check for landmark regions
    const landmarks = await page.evaluate(() => {
      return {
        nav: document.querySelectorAll('nav, [role="navigation"]').length,
        main: document.querySelectorAll('main, [role="main"]').length,
        header: document.querySelectorAll('header, [role="banner"]').length,
        footer: document.querySelectorAll('footer, [role="contentinfo"]').length,
        section: document.querySelectorAll('section').length,
        article: document.querySelectorAll('article').length,
      };
    });

    console.log('\n--- Landmark Regions ---');
    console.log(`  Navigation: ${landmarks.nav}`);
    console.log(`  Main: ${landmarks.main}`);
    console.log(`  Header: ${landmarks.header}`);
    console.log(`  Footer: ${landmarks.footer}`);
    console.log(`  Sections: ${landmarks.section}`);
    console.log(`  Articles: ${landmarks.article}`);

    // Check for heading hierarchy
    const headings = await page.evaluate(() => {
      return Array.from(document.querySelectorAll('h1, h2, h3, h4, h5, h6')).map(h => ({
        level: h.tagName,
        text: h.textContent?.trim(),
        ariaLevel: h.getAttribute('aria-level'),
      }));
    });

    console.log('\n--- Heading Hierarchy ---');
    headings.forEach((h, i) => {
      console.log(`  ${h.level}: ${h.text?.substring(0, 60)}`);
    });

    // Check form labels
    const formElements = await page.evaluate(() => {
      const inputs = Array.from(document.querySelectorAll('input, select, textarea, button'));
      return inputs.map(el => ({
        tag: el.tagName,
        type: el.getAttribute('type'),
        id: el.id,
        name: el.getAttribute('name'),
        label: document.querySelector(`label[for="${el.id}"]`)?.textContent?.trim(),
        ariaLabel: el.getAttribute('aria-label'),
        ariaLabelledBy: el.getAttribute('aria-labelledby'),
        role: el.getAttribute('role'),
      }));
    });

    console.log('\n--- Form Elements & Labels ---');
    formElements.forEach((el, i) => {
      const labelInfo = el.label || el.ariaLabel || el.ariaLabelledBy || 'NO LABEL ⚠️';
      console.log(`  ${el.tag}[type=${el.type}]: ${labelInfo}`);
    });

    // Check for time elements with datetime
    const timeElements = await page.evaluate(() => {
      return Array.from(document.querySelectorAll('time')).map(t => ({
        text: t.textContent?.trim(),
        datetime: t.getAttribute('datetime'),
      }));
    });

    console.log('\n--- Time Elements ---');
    timeElements.forEach(t => {
      console.log(`  ${t.text}: datetime=${t.datetime || 'MISSING ⚠️'}`);
    });

    // Check for images with alt text
    const images = await page.evaluate(() => {
      return Array.from(document.querySelectorAll('img')).map(img => ({
        src: img.getAttribute('src'),
        alt: img.getAttribute('alt'),
      }));
    });

    console.log('\n--- Images ---');
    images.forEach(img => {
      console.log(`  ${img.src}: alt="${img.alt || 'MISSING ⚠️'}"`);
    });

    // Check for progress bars with aria attributes
    const progressBars = await page.evaluate(() => {
      return Array.from(document.querySelectorAll('.progress-ring, [role="progressbar"]')).map(p => ({
        class: p.className,
        role: p.getAttribute('role'),
        ariaValueNow: p.getAttribute('aria-valuenow'),
        ariaValueMin: p.getAttribute('aria-valuemin'),
        ariaValueMax: p.getAttribute('aria-valuemax'),
        ariaLabel: p.getAttribute('aria-label'),
      }));
    });

    console.log('\n--- Progress Bars ---');
    progressBars.forEach((p, i) => {
      console.log(`  Progress ${i + 1}:`);
      console.log(`    Role: ${p.role || 'MISSING ⚠️'}`);
      console.log(`    Value: ${p.ariaValueNow}/${p.ariaValueMax} (min: ${p.ariaValueMin})`);
      console.log(`    Label: ${p.ariaLabel || 'MISSING ⚠️'}`);
    });
  });

  test('Color contrast ratios', async ({ page }) => {
    await page.goto('/');
    await page.waitForLoadState('networkidle');

    console.log('\n========== COLOR CONTRAST TEST ==========');

    // Get all text elements and check contrast
    const contrastIssues = await page.evaluate(() => {
      function getLuminance(r: number, g: number, b: number): number {
        const [rs, gs, bs] = [r, g, b].map(c => {
          const channel = c / 255;
          return channel <= 0.03928 ? channel / 12.92 : Math.pow((channel + 0.055) / 1.055, 2.4);
        });
        return 0.2126 * rs + 0.7152 * gs + 0.0722 * bs;
      }

      function getContrastRatio(lum1: number, lum2: number): number {
        const lighter = Math.max(lum1, lum2);
        const darker = Math.min(lum1, lum2);
        return (lighter + 0.05) / (darker + 0.05);
      }

      function parseColor(color: string): [number, number, number] | null {
        const rgb = color.match(/rgba?\((\d+),\s*(\d+),\s*(\d+)/);
        if (rgb) {
          return [parseInt(rgb[1]), parseInt(rgb[2]), parseInt(rgb[3])];
        }
        return null;
      }

      const textElements = Array.from(document.querySelectorAll('*')).filter(el => {
        const hasText = el.textContent && el.textContent.trim().length > 0;
        const isVisible = window.getComputedStyle(el).display !== 'none';
        return hasText && isVisible && el.children.length === 0;
      });

      const issues: any[] = [];

      textElements.forEach(el => {
        const styles = window.getComputedStyle(el);
        const color = parseColor(styles.color);
        const bgColor = parseColor(styles.backgroundColor);

        if (!color || !bgColor) return;

        // Check if background is transparent, walk up tree
        let currentEl = el.parentElement;
        let effectiveBg = bgColor;

        while (currentEl && bgColor[0] === 0 && bgColor[1] === 0 && bgColor[2] === 0) {
          const parentBg = parseColor(window.getComputedStyle(currentEl).backgroundColor);
          if (parentBg && !(parentBg[0] === 0 && parentBg[1] === 0 && parentBg[2] === 0)) {
            effectiveBg = parentBg;
            break;
          }
          currentEl = currentEl.parentElement;
        }

        const textLum = getLuminance(color[0], color[1], color[2]);
        const bgLum = getLuminance(effectiveBg[0], effectiveBg[1], effectiveBg[2]);
        const ratio = getContrastRatio(textLum, bgLum);

        const fontSize = parseFloat(styles.fontSize);
        const fontWeight = styles.fontWeight;
        const isLarge = fontSize >= 18 || (fontSize >= 14 && parseInt(fontWeight) >= 700);
        const requiredRatio = isLarge ? 3 : 4.5;

        if (ratio < requiredRatio) {
          issues.push({
            text: el.textContent?.trim().substring(0, 50),
            tag: el.tagName,
            class: el.className,
            color: styles.color,
            backgroundColor: styles.backgroundColor,
            ratio: ratio.toFixed(2),
            required: requiredRatio,
            fontSize: styles.fontSize,
            fontWeight: styles.fontWeight,
            pass: false,
          });
        }
      });

      return issues;
    });

    console.log(`\nTotal contrast issues found: ${contrastIssues.length}`);

    contrastIssues.forEach((issue, i) => {
      console.log(`\n--- Issue ${i + 1} ---`);
      console.log(`  Text: "${issue.text}"`);
      console.log(`  Element: ${issue.tag}.${issue.class}`);
      console.log(`  Color: ${issue.color} on ${issue.backgroundColor}`);
      console.log(`  Ratio: ${issue.ratio}:1 (Required: ${issue.required}:1)`);
      console.log(`  Font: ${issue.fontSize} / ${issue.fontWeight}`);
    });

    // Check specific color variables
    const cssVariables = await page.evaluate(() => {
      const root = document.documentElement;
      const styles = getComputedStyle(root);
      return {
        bgDeep: styles.getPropertyValue('--bg-deep'),
        bgPrimary: styles.getPropertyValue('--bg-primary'),
        textPrimary: styles.getPropertyValue('--text-primary'),
        textSecondary: styles.getPropertyValue('--text-secondary'),
        textMuted: styles.getPropertyValue('--text-muted'),
        accentTeal: styles.getPropertyValue('--accent-teal'),
      };
    });

    console.log('\n--- CSS Custom Properties ---');
    Object.entries(cssVariables).forEach(([key, value]) => {
      console.log(`  --${key}: ${value}`);
    });
  });

  test('Responsive behavior and touch targets', async ({ page }) => {
    console.log('\n========== RESPONSIVE & TOUCH TARGETS TEST ==========');

    // Test desktop viewport
    await page.setViewportSize({ width: 1920, height: 1080 });
    await page.goto('/');
    await page.waitForLoadState('networkidle');

    console.log('\n--- Desktop (1920x1080) ---');
    const desktopMetrics = await page.evaluate(() => {
      const nav = document.querySelector('.main-nav');
      const metricsGrid = document.querySelector('.metrics-grid');
      return {
        navDisplay: nav ? window.getComputedStyle(nav).display : 'none',
        gridColumns: metricsGrid ? window.getComputedStyle(metricsGrid).gridTemplateColumns : 'none',
      };
    });
    console.log(`  Nav display: ${desktopMetrics.navDisplay}`);
    console.log(`  Grid columns: ${desktopMetrics.gridColumns}`);

    await page.screenshot({ path: '/tmp/responsive-desktop.png', fullPage: true });
    console.log('  Screenshot: /tmp/responsive-desktop.png');

    // Test tablet viewport
    await page.setViewportSize({ width: 768, height: 1024 });
    await page.waitForTimeout(500);

    console.log('\n--- Tablet (768x1024) ---');
    const tabletMetrics = await page.evaluate(() => {
      const metricsGrid = document.querySelector('.metrics-grid');
      const summaryItem = document.querySelector('.summary-item');
      return {
        gridColumns: metricsGrid ? window.getComputedStyle(metricsGrid).gridTemplateColumns : 'none',
        summaryDisplay: summaryItem ? window.getComputedStyle(summaryItem).gridTemplateColumns : 'none',
      };
    });
    console.log(`  Grid columns: ${tabletMetrics.gridColumns}`);
    console.log(`  Summary display: ${tabletMetrics.summaryDisplay}`);

    await page.screenshot({ path: '/tmp/responsive-tablet.png', fullPage: true });
    console.log('  Screenshot: /tmp/responsive-tablet.png');

    // Test mobile viewport
    await page.setViewportSize({ width: 375, height: 667 });
    await page.waitForTimeout(500);

    console.log('\n--- Mobile (375x667) ---');
    const mobileMetrics = await page.evaluate(() => {
      const metricsGrid = document.querySelector('.metrics-grid');
      const header = document.querySelector('.dashboard-header');
      const summaryItem = document.querySelector('.summary-item');
      return {
        gridColumns: metricsGrid ? window.getComputedStyle(metricsGrid).gridTemplateColumns : 'none',
        headerDirection: header ? window.getComputedStyle(header).flexDirection : 'none',
        summaryDisplay: summaryItem ? window.getComputedStyle(summaryItem).gridTemplateColumns : 'none',
      };
    });
    console.log(`  Grid columns: ${mobileMetrics.gridColumns}`);
    console.log(`  Header direction: ${mobileMetrics.headerDirection}`);
    console.log(`  Summary display: ${mobileMetrics.summaryDisplay}`);

    await page.screenshot({ path: '/tmp/responsive-mobile.png', fullPage: true });
    console.log('  Screenshot: /tmp/responsive-mobile.png');

    // Check touch target sizes (minimum 44x44px for WCAG 2.2)
    await page.setViewportSize({ width: 375, height: 667 });
    const touchTargets = await page.evaluate(() => {
      const interactive = Array.from(
        document.querySelectorAll('a, button, input, select, textarea')
      );

      return interactive.map(el => {
        const rect = el.getBoundingClientRect();
        return {
          tag: el.tagName,
          class: el.className,
          text: el.textContent?.trim().substring(0, 30),
          width: Math.round(rect.width),
          height: Math.round(rect.height),
          meetsMinimum: rect.width >= 44 && rect.height >= 44,
        };
      });
    });

    console.log('\n--- Touch Target Sizes (Mobile) ---');
    const failedTargets = touchTargets.filter(t => !t.meetsMinimum);
    console.log(`Total interactive elements: ${touchTargets.length}`);
    console.log(`Failed minimum size (44x44): ${failedTargets.length}`);

    failedTargets.forEach((target, i) => {
      console.log(`\n  Failed ${i + 1}:`);
      console.log(`    ${target.tag}.${target.class}`);
      console.log(`    "${target.text}"`);
      console.log(`    Size: ${target.width}x${target.height}px`);
    });
  });

  test('Screenshot capture for visual review', async ({ page }) => {
    await page.goto('/');
    await page.waitForLoadState('networkidle');

    // Capture full page
    await page.screenshot({
      path: '/tmp/dashboard-full.png',
      fullPage: true
    });
    console.log('Full page screenshot: /tmp/dashboard-full.png');

    // Capture navigation
    await page.locator('.main-nav').screenshot({
      path: '/tmp/navigation.png'
    });
    console.log('Navigation screenshot: /tmp/navigation.png');

    // Capture metrics grid
    const metricsGrid = page.locator('.metrics-grid');
    if (await metricsGrid.count() > 0) {
      await metricsGrid.screenshot({
        path: '/tmp/metrics-grid.png'
      });
      console.log('Metrics grid screenshot: /tmp/metrics-grid.png');
    }

    // Capture empty state if present
    const emptyState = page.locator('.empty-state');
    if (await emptyState.count() > 0) {
      await emptyState.screenshot({
        path: '/tmp/empty-state.png'
      });
      console.log('Empty state screenshot: /tmp/empty-state.png');
    }
  });
});
