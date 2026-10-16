import { test, expect, type Locator, type Page } from '@playwright/test';

// Box centres may differ by sub-pixel rounding, not by a nudge. The fixes of
// SdWa5Theme 1.2.2 to 1.2.4 removed offsets of 0.8 to 3.2 px.
const TOLERANCE = 0.5;

async function centreY(locator: Locator): Promise<number> {
  const box = await locator.boundingBox();
  expect(box, `${locator} is not rendered`).not.toBeNull();
  return box!.y + box!.height / 2;
}

async function expectLevel(reference: Locator, pieces: Record<string, Locator>): Promise<void> {
  const line = await centreY(reference);
  for (const [name, piece] of Object.entries(pieces)) {
    expect.soft(Math.abs((await centreY(piece)) - line), `${name} off the centre line`).toBeLessThanOrEqual(TOLERANCE);
  }
}

async function openHome(page: Page): Promise<void> {
  await page.goto('/');
  await page.evaluate(() => document.fonts.ready);
}

async function openOffcanvas(page: Page): Promise<Locator> {
  await openHome(page);
  await page.locator('.nav-main-toggle-btn:visible').click();
  const offcanvas = page.locator('.offcanvas');
  await expect(offcanvas.locator('.sdwa5-donate-offcanvas')).toBeVisible();
  // The panel slides in. Wait for its transition before measuring or shooting.
  await page.waitForFunction(() => {
    const panel = document.querySelector('.offcanvas.show');
    return panel !== null && panel.getAnimations().every((a) => a.playState === 'finished');
  });
  return offcanvas;
}

test('header logo has as much visible space above as below', async ({ page }) => {
  await openHome(page);
  const row = await page.locator('.header-row').boundingBox();
  const logo = await page.locator('.header-logo-main-img').boundingBox();
  // The fixed accent stripe covers the top of the header.
  const stripe = await page.evaluate(() => parseFloat(getComputedStyle(document.body, '::before').height));

  const above = logo!.y - row!.y - stripe;
  const below = row!.y + row!.height - (logo!.y + logo!.height);
  expect(Math.abs(above - below), `${above} px above against ${below} px below`).toBeLessThanOrEqual(TOLERANCE);
});

// One page per CMS layout in use. The Gallery is a full-width section, whose
// block row stuck out 20 px on each side before SdWa5Theme 1.2.6.
for (const path of ['/', '/Gallery/', '/About-SdWa5', '/Hardware/']) {
  test(`${path} does not scroll sideways`, async ({ page }) => {
    await page.goto(path);
    await page.waitForLoadState('networkidle');
    const { scroll, client } = await page.evaluate(() => ({
      scroll: document.documentElement.scrollWidth,
      client: document.documentElement.clientWidth,
    }));
    expect(scroll, `page is ${scroll} px wide in a ${client} px viewport`).toBeLessThanOrEqual(client);
  });
}

test.describe('desktop header', () => {
  test.beforeEach(({}, testInfo) => {
    test.skip(!testInfo.project.name.startsWith('desktop'), 'the settings column shows from 992 px');
  });

  test('settings share the header row centre', async ({ page }) => {
    await openHome(page);
    const settings = page.locator('.sdwa5-header__settings');

    await expectLevel(settings.locator('xpath=..'), {
      'toggle icon': settings.locator('.dne-storefront-dark-mode-btn .icon:visible svg'),
      'language flag': settings.locator('.top-bar-language .dropdown-toggle .language-flag'),
      'language text': settings.locator('.top-bar-language .dropdown-toggle .top-bar-nav-text'),
      'donate button': page.locator('.sdwa5-donate-btn'),
    });
    await expect(settings).toHaveScreenshot('header-settings.png');
  });

  // The share bar pads the content between 992 and 1400 px, and the hero image
  // stopped 36 px short of the right edge until SdWa5Theme 1.2.7.
  for (const width of [1024, 1280]) {
    test(`hero image spans the viewport at ${width} px`, async ({ page }) => {
      await page.setViewportSize({ width, height: 800 });
      await openHome(page);
      const hero = await page.locator('.cms-section.sdwa5-hero img').first().boundingBox();
      expect(hero!.x, 'hero left edge').toBeLessThanOrEqual(TOLERANCE);
      expect(hero!.x + hero!.width, 'hero right edge').toBeGreaterThanOrEqual(width - TOLERANCE);
    });
  }

  test('homepage tiles end at their padding', async ({ page }) => {
    await openHome(page);
    const container = page.locator('.cms-section.sdwa5-tiles .cms-block-container').first();
    const lastParagraph = container.locator('.cms-element-text p:last-child');

    const [containerBox, paragraphBox] = [await container.boundingBox(), await lastParagraph.boundingBox()];
    const padding = await container.evaluate((e) => parseFloat(getComputedStyle(e).paddingBottom));
    const gap = containerBox!.y + containerBox!.height - (paragraphBox!.y + paragraphBox!.height);

    expect(Math.abs(gap - padding), `gap ${gap} px against padding ${padding} px`).toBeLessThanOrEqual(TOLERANCE);
  });
});

test.describe('offcanvas menu', () => {
  test.beforeEach(({}, testInfo) => {
    test.skip(testInfo.project.name.startsWith('desktop'), 'the burger menu shows below 992 px');
  });

  test('toggle and language share one centre line', async ({ page }, testInfo) => {
    const actions = (await openOffcanvas(page)).locator('.navigation-offcanvas-actions');
    const language = actions.locator('.top-bar-language .dropdown-toggle');

    const pieces: Record<string, Locator> = {
      'toggle icon': actions.locator('.dne-storefront-dark-mode-btn .icon:visible svg'),
      'language flag': language.locator('.language-flag'),
    };
    // The language name shows from 768 px.
    if (testInfo.project.name.startsWith('tablet')) {
      pieces['language text'] = language.locator('.top-bar-nav-text');
    }

    await expectLevel(language, pieces);
    await expect(actions).toHaveScreenshot('offcanvas-actions.png');
  });

  test('donate heart is level with its text', async ({ page }) => {
    const donate = (await openOffcanvas(page)).locator('.sdwa5-donate-offcanvas');

    await expectLevel(donate.locator('span:not(.icon)'), { heart: donate.locator('.icon svg') });
  });
});

test.describe('footer', () => {
  test.beforeEach(async ({ page }) => {
    await openHome(page);
    // The core footer plugin collapses the columns on mobile once its script has run.
    await page.waitForLoadState('networkidle');
  });

  // Below 768 px the last column's border is the visible edge above the line.
  // From 768 px the columns have no border and end below their text, so the
  // box gap says nothing about what the eye sees there.
  test('donation line has as much space above as below', async ({ page }, testInfo) => {
    test.skip(!testInfo.project.name.startsWith('phone'), 'the columns have a visible edge below 768 px');
    const gaps = await page.evaluate(() => {
      const box = (selector: string) => document.querySelector(selector)!.getBoundingClientRect();
      const columns = document.querySelectorAll('.footer-column');
      const line = box('.sdwa5-donate-line');
      return {
        above: line.top - columns[columns.length - 1].getBoundingClientRect().bottom,
        below: box('.footer-bottom').top - line.bottom,
      };
    });
    expect(Math.abs(gaps.above - gaps.below), `${gaps.above} px above against ${gaps.below} px below`).toBeLessThanOrEqual(TOLERANCE);
  });

  test('column toggles stay hidden from 768 px', async ({ page }, testInfo) => {
    test.skip(testInfo.project.name.startsWith('phone'), 'the columns collapse below 768 px');
    await expect(page.locator('.footer-column-toggle').first()).toBeHidden();
  });

  test.describe('collapsed below 768 px', () => {
    test.beforeEach(({}, testInfo) => {
      test.skip(!testInfo.project.name.startsWith('phone'), 'the columns collapse below 768 px');
    });

    test('columns are equally tall', async ({ page }) => {
      const heights = await page.locator('.footer-column').evaluateAll((columns) => columns.map((c) => c.getBoundingClientRect().height));
      for (const height of heights) {
        expect(Math.abs(height - heights[0]), `heights ${heights.join(', ')}`).toBeLessThanOrEqual(TOLERANCE);
      }
    });

    test('titles and toggles share the headline centre', async ({ page }) => {
      const offsets = await page.locator('.footer-column-headline').evaluateAll((headlines) => headlines.map((headline) => {
        const box = headline.getBoundingClientRect();
        const centre = box.top + box.height / 2;
        // The title is a bare text node, or a link around one, so measure the text itself.
        const walker = document.createTreeWalker(headline, NodeFilter.SHOW_TEXT, { acceptNode: (n) => (n.textContent!.trim() ? NodeFilter.FILTER_ACCEPT : NodeFilter.FILTER_SKIP) });
        const range = document.createRange();
        range.selectNodeContents(walker.nextNode()!);
        const text = range.getBoundingClientRect();
        const icon = headline.querySelector('.footer-column-toggle .icon:not([style*="none"]) svg')!.getBoundingClientRect();
        return { title: headline.textContent!.trim(), text: text.top + text.height / 2 - centre, icon: icon.top + icon.height / 2 - centre };
      }));
      for (const { title, text, icon } of offsets) {
        expect.soft(Math.abs(text), `${title} text off centre`).toBeLessThanOrEqual(TOLERANCE);
        expect.soft(Math.abs(icon), `${title} toggle off centre`).toBeLessThanOrEqual(TOLERANCE);
      }
    });
  });
});
