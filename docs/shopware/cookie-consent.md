# Cookie consent

**Legal basis:** TKG §165 / DSGVO — consent required before any non-technically-necessary cookie fires.

**Active cookie groups:**

- "Technically required": session, CSRF, timezone
- "Comfort features": YouTube video, Vimeo video (both natively gated by Shopware CMS elements)

**No analytics, no marketing, no third-party tracking.**

**Snippet overrides in DB:**

- Banner text, German labels, accept button — custom copy
- `cookie.descriptionInfo` — hardcoded Datenschutz link, updated 2026-07-03 to `/Datenschutz/`
  (secondary offcanvas snippet, not the main banner).
- `cookie.messageTextPage` (main banner text) — overridden 2026-07-20 in both `de-DE` and `en-GB`
  BASE snippet sets with a hardcoded `/Datenschutz/` anchor. See the `/page/cms/Array` fix below.
- Cache cleared via `DELETE /api/_action/cache` after each snippet/config change.

## The `/page/cms/Array` bug (fixed 2026-07-20)

**Symptom:** the cookie banner's privacy link (and the footer legal links) rendered as
`/page/cms/Array`.

**Root cause — corrupted `system_config`, not a snippet/cache issue.** A 2026-06-29 bulk write
(the Footer service-navigation move) created **sales-channel-scoped** duplicate rows for the
`core.basicInformation.*Page` configs whose value was wrapped as `{"_value": "<uuid>"}` instead
of a bare UUID string. The storefront reads the value unguarded —
`path('frontend.cms.page.full', { id: config('core.basicInformation.privacyPage') })` in
`cookie-permission.html.twig` / `cookie-configuration.html.twig` — and Symfony casts the route
param with `(string)`, so `(string) ['_value' => …]` yields the literal `"Array"`. The footer
guards the same call only by truthiness, and a non-empty array is truthy, so it broke too. Eight
rows were affected: SC-scoped `imprintPage`, `privacyPage`, `tosPage`, `revocationPage`,
`shippingPaymentInfoPage`, `contactPage`, plus `phone` at both scopes (`{"_value": ""}`).

**Fix (two independent parts):**

1. **Data fix:** deleted the 8 corrupted `{"_value": …}` rows. Every affected key already had a
   correct **bare-UUID null-scope** row (Shopware stores scalars bare — cf. `shopName`, `email`),
   so the storefront now falls back to the good default. Verified live: `/page/cms/Array` gone
   from homepage, Music/Mixes, and footer. (`phone` was empty either way.)
2. **Snippet override:** the raw `frontend.cms.page.full` route has no SEO URL for the Privacy
   CMS page, so it would render `/page/cms/<uuid>` (functional but ugly). Overriding
   `cookie.messageTextPage` with a hardcoded `/Datenschutz/` anchor (rendered `|raw`, same pattern
   as `cookie.descriptionInfo`) guarantees the pretty link and is immune to the config entirely.

## Storefront settings (audited 2026-07-20)

Both are `core.basicInformation.*` configs, gating the native banner in `cookie-permission.html.twig`:

- **`useDefaultCookieConsent` = true** — keeps the native banner rendering at all. Correct, keep.
- **`acceptAllCookies` = false** (no DB row → core default) — banner shows Deny/Configure, no
  one-click "Accept all". **Kept OFF.** EU/AT compliance (best-effort, not legal advice): there is
  no legal duty to offer an accept-all button; omitting it is more privacy-protective. The EDPB
  "symmetry" concern only applies when an accept-all exists without an equally easy reject — N/A
  here. With only comfort cookies (all gated) nothing fires pre-consent.
- "Show Revoke a contract button in footer" is separate footer plumbing tied to `revocationPage`
  (which was one of the corrupted configs above — now fixed).

## Native vs. non-native gating

YouTube and Vimeo are gated natively — Shopware ships dedicated CMS element types with built-in JS
consent plugins that block the iframe until the user accepts. No custom code needed.

**Non-native embeds (e.g. SoundCloud)** have no equivalent, and in Shopware 6.7 registering a real
consent-manager entry needs **code** (a `CookieGroupCollectEvent` subscriber or an app-manifest
`<cookies>` block) — a snippet only supplies label text, it does **not** register an entry.

**Chosen approach: click-to-load facade** (Music/Mixes page, implemented 2026-07-20). The `html`
CMS slot holds a placeholder card + inline JS instead of the raw iframe: no request to
`soundcloud.com` fires until the visitor clicks "Load SoundCloud player" (strongest-compliance
opt-in, DSGVO/TKG-safe). Consent is remembered in first-party `localStorage` (`sc-consent`), not a
cookie, so returning visitors auto-load. No plugin, no consent-manager entry needed — applied via
`PATCH /api/cms-slot` (base + both language translations). The live shop sets no CSP header, so the
inline script runs.

## Third-party CMP decision threshold

Native Shopware consent + per-embed facades remain sufficient as long as:

- Non-native third-party embeds stay few and are wired as click-to-load facades
- No audit trail / documented per-user consent records required
- No auto-scanning of all page cookies needed

**Note:** there is **no** free Shopware "cookieman" plugin — `dmind/cookieman` is a TYPO3 extension
only. If generic embed gating for many services is ever needed, evaluate a custom
`CookieGroupCollectEvent` plugin or a paid marketplace CMP (ACRIS, Cookiebot, Usercentrics); do not
plan around a non-existent `frosh/cookieman`.
