# Cookie consent

**Legal basis:** TKG §165 / DSGVO — consent required before any non-technically-necessary cookie fires.

**Active cookie groups:**

- "Technically required": session, CSRF, timezone
- "Comfort features": YouTube video, Vimeo video (both natively gated by Shopware CMS elements)

**No analytics, no marketing, no third-party tracking.**

**Snippet overrides in DB:**

- Banner text, German labels, accept button — custom copy
- `cookie.descriptionInfo` — hardcoded Datenschutz link, updated 2026-07-03 to `/Datenschutz/`
  (was `/Rechtliches/Datenschutz/` before the Footer service navigation move, see TODO history).
  Not the main banner text — see open TODO item re: `cookie.messageTextPage`'s `/page/cms/Array` bug.
- Cache cleared 2026-06-29: `docker exec shopware php bin/console cache:clear`

## Native vs. non-native gating

YouTube and Vimeo are gated natively — Shopware ships dedicated CMS element types with built-in JS
consent plugins that block the iframe until the user accepts. No custom code needed.

**Non-native embeds (e.g. SoundCloud)** have no equivalent. To add one compliantly:

- Register a new cookie entry in the "Comfort features" group via `POST /api/snippet`
- Gate the iframe manually: inline JS in the HTML CMS slot that reads Shopware's `cookie-preference`
  browser cookie and swaps in the iframe on consent — OR write a small custom Storefront JS plugin

**Shopware services** (Analytics, AI Copilot, etc.) self-register their consent entries in the native
system automatically — no custom wiring needed.

## Third-party CMP decision threshold

Native Shopware consent (current setup) remains sufficient as long as:

- Non-native third-party embeds stay few (≤2) and are wired manually
- No audit trail / documented per-user consent records required
- No auto-scanning of all page cookies needed

Switch to **frosh/cookieman** (Shopware plugin, free, open source) if 3+ non-native services are added —
it provides generic embed gating without full SaaS CMP overhead.

Switch to a **SaaS CMP** (Cookiebot, Usercentrics) only if scale grows significantly or AT authority
scrutiny requires proof-of-consent infrastructure.
