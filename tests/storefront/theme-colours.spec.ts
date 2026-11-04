import { test, expect } from '@playwright/test';

// Shopware's core CSS sets the theme's brand colours, the primary green and the
// secondary red, as literal text colours, which fail contrast on the light
// background. _base-elements.scss repeats each of those selectors later with a
// readable colour (docs/shopware/theme.md#colours-and-the-dark-mode-plugin).
// A core update can add such rules, so this test reads the compiled theme CSS
// and asks for an override for every selector that sets a literal brand colour
// as text colour. Rules scoped to data-theme belong to the dark mode plugin and
// are left out.
const LITERAL = /(?:^|;)color:#(?:1fe51f|e5231f)(?:;|!|$)/i;
const COLOUR = /(?:^|;)color:/i;

// Covered elsewhere, measured on 2026-11-04.
const COVERED_ELSEWHERE = new Map([
  ['.header-cart-total', 'hidden by _header.scss'],
  ['.alert-secondary .icon', 'icon: WCAG 1.4.11 asks 3:1, the red measures 4.20:1'],
  ['.icon-secondary', 'icon, as above'],
  ['.line-item-container .line-item-icon .icon', 'icon, as above'],
]);

// Splits a selector list at top-level commas, so :is(a, b) stays whole.
function selectors(list: string): string[] {
  const out: string[] = [];
  let depth = 0;
  let current = '';
  for (const ch of list) {
    if (ch === '(') depth++;
    if (ch === ')') depth--;
    if (ch === ',' && depth === 0) {
      out.push(current.trim());
      current = '';
    } else {
      current += ch;
    }
  }
  out.push(current.trim());
  return out;
}

test('every literal brand text colour of the core CSS has a readable override', async ({ request, baseURL }) => {
  const html = await (await request.get('/')).text();
  const href = html.match(/[^"'\s]*\/theme\/[^"'\s]*all\.css[^"'\s]*/)?.[0];
  expect(href, 'no theme CSS link on /').toBeTruthy();
  const css = await (await request.get(new URL(href!, baseURL).toString())).text();

  const rules = [...css.matchAll(/([^{}]+)\{([^{}]*)\}/g)].map((m) => ({
    at: m.index!,
    selectors: selectors(m[1].trim()),
    body: m[2],
  }));
  const missing = new Set<string>();
  for (const rule of rules) {
    if (!LITERAL.test(rule.body) || rule.selectors.some((s) => s.includes('data-theme'))) continue;
    for (const s of rule.selectors) {
      const overridden = rules.some(
        (later) => later.at > rule.at && later.selectors.includes(s) && COLOUR.test(later.body) && !LITERAL.test(later.body),
      );
      if (!overridden && !COVERED_ELSEWHERE.has(s)) missing.add(s);
    }
  }
  expect([...missing].sort()).toEqual([]);
});
