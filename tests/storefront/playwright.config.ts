import { defineConfig, type Project } from '@playwright/test';

// Three widths, because the theme changes at 992 px (settings column versus
// offcanvas) and at 768 px (the offcanvas language text appears). Each in both
// colour schemes, because the DNE toggle shows a different icon in each.
const viewports = {
  desktop: { viewport: { width: 1280, height: 800 } },
  tablet: { viewport: { width: 800, height: 1024 }, isMobile: true, hasTouch: true },
  phone: { viewport: { width: 390, height: 844 }, isMobile: true, hasTouch: true },
};

const projects: Project[] = Object.entries(viewports).flatMap(([name, use]) =>
  (['light', 'dark'] as const).map((colorScheme) => ({
    name: `${name}-${colorScheme}`,
    use: { browserName: 'chromium' as const, ...use, colorScheme },
  })),
);

export default defineConfig({
  testDir: '.',
  forbidOnly: true,
  retries: 0,
  reporter: 'list',
  use: {
    baseURL: process.env.SDWA5_STOREFRONT_URL || 'https://sdwa5.org',
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
  },
  expect: {
    // Baselines and runs come from the same pinned image. Ten pixels of slack
    // cover antialiasing, while a 1 px shift of the offcanvas flag measured
    // 88 differing pixels on 2026-10-16.
    toHaveScreenshot: { maxDiffPixels: 10, animations: 'disabled' },
  },
  projects,
});
