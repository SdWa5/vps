import { test, expect, type APIRequestContext, type Page } from '@playwright/test';
import { gunzipSync } from 'node:zlib';

// The storefront's Content-Security-Policy is the `header @storefront` line of
// the Caddyfile (docs/caddy.md#hardening), which run.sh passes in. Each test
// enforces it on every same-origin page in place of the header the server sent,
// so it checks the policy that the next deploy ships, also on the local mirror,
// which has no Caddy in front. A source the policy does not allow raises a
// securitypolicyviolation event, and any event fails the test. report-uri is
// left out, so a failing run sends no report to the site.
const POLICY = (process.env.SDWA5_CSP_POLICY ?? '').replace(/;\s*report-uri [^;]*/, '');

const SITEMAPS = ['/sitemap.xml', '/de/sitemap.xml'];
const UNLISTED = ['/checkout/cart', '/account/login', '/account/register', '/search?search=sticker'];
const SOUNDCLOUD = 'https://w.soundcloud.com/player/';

type Violation = { directive: string; blocked: string; disposition: string };

declare global {
  interface Window {
    cspViolations: Violation[];
  }
}

// Installed before any script of a page runs, so no event is missed.
function listen(): void {
  window.cspViolations = [];
  document.addEventListener('securitypolicyviolation', (e) => {
    window.cspViolations.push({ directive: e.effectiveDirective, blocked: e.blockedURI, disposition: e.disposition });
  });
}

async function enforcePolicy(page: Page, baseURL: string): Promise<void> {
  expect(POLICY, 'SDWA5_CSP_POLICY, which run.sh reads from the Caddyfile').not.toBe('');
  const origin = new URL(baseURL).origin;
  await page.route((url) => url.origin === origin, async (route) => {
    if (route.request().resourceType() !== 'document') {
      return route.fallback();
    }
    // A redirect goes back to the browser, which requests its target through this route again.
    const response = await route.fetch({ maxRedirects: 0 });
    const headers = response.headers();
    // The fetched body arrives decoded and whole.
    for (const name of ['content-security-policy', 'content-security-policy-report-only', 'content-encoding', 'content-length', 'transfer-encoding']) {
      delete headers[name];
    }
    await route.fulfill({ response, headers: { ...headers, 'content-security-policy': POLICY } });
  });
  await page.addInitScript(listen);
}

async function violations(page: Page, path: string): Promise<string[]> {
  const found = await page.evaluate(() => window.cspViolations);
  return found.map((v) => `${path}: ${v.directive} ${v.blocked} (${v.disposition})`);
}

// The mirror of tools/shopware/dev-instance.sh serves production's sitemap
// files, whose entries name sdwa5.org, so only their paths count.
function locations(xml: string): string[] {
  return [...xml.matchAll(/<loc>([^<]+)<\/loc>/g)].map((match) => {
    const url = new URL(match[1].replace(/&amp;/g, '&'));
    return url.pathname + url.search;
  });
}

async function sitemapPages(request: APIRequestContext): Promise<string[]> {
  const pages: string[] = [];
  for (const index of SITEMAPS) {
    const response = await request.get(index);
    expect(response.ok(), `${index} answers ${response.status()}`).toBe(true);
    for (const part of locations(await response.text())) {
      const body = await (await request.get(part)).body();
      // Shopware serves the parts as application/x-gzip without a Content-Encoding.
      const xml = body[0] === 0x1f && body[1] === 0x8b ? gunzipSync(body) : body;
      pages.push(...locations(xml.toString('utf8')));
    }
  }
  return pages;
}

test('no storefront page raises a CSP violation', async ({ page, request, baseURL }) => {
  test.setTimeout(10 * 60_000);
  const pages = [...new Set([...(await sitemapPages(request)), ...UNLISTED])];
  expect(pages.length, 'pages found').toBeGreaterThan(UNLISTED.length);

  await enforcePolicy(page, baseURL!);
  const found: string[] = [];
  for (const path of pages) {
    const response = await page.goto(path, { waitUntil: 'networkidle' });
    expect.soft(response?.status(), `${path} status`).toBeLessThan(400);
    found.push(...(await violations(page, path)));
  }
  expect(found).toEqual([]);
});

// The Music/Mixes page loads the SoundCloud player only after a click
// (docs/shopware/cookie-consent.md). The stub keeps the test from contacting
// SoundCloud; the browser checks the policy before the request is routed.
test('the SoundCloud player loads behind its facade', async ({ page, baseURL }) => {
  await enforcePolicy(page, baseURL!);
  await page.route(`${SOUNDCLOUD}**`, (route) => route.fulfill({ contentType: 'text/html', body: '<!doctype html><title>stub</title>' }));
  await page.goto('/Music-Mixes/', { waitUntil: 'networkidle' });

  const loaded = page
    .waitForEvent('framenavigated', { predicate: (frame) => frame.url().startsWith(SOUNDCLOUD), timeout: 10_000 })
    .catch(() => null);
  await page.locator('#sc-facade .sc-load').click();
  const frame = await loaded;
  // Let a queued violation event run before reading the list.
  await page.evaluate(() => new Promise((resolve) => requestAnimationFrame(resolve)));

  expect(await violations(page, '/Music-Mixes/')).toEqual([]);
  expect(frame, 'the player frame navigated to SoundCloud').not.toBeNull();
});
