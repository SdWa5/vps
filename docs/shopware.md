# sdwa5.org Shopware Documentation

**Shopware 6.7** · dockware container · https://sdwa5.org
Admin: https://sdwa5.org/admin · `admin` / see project memory

## Admin API

### User credentials (password grant)

For scripting and one-off automation. Token expires after 10 minutes.

```bash
TOKEN=$(curl -s -X POST https://sdwa5.org/api/oauth/token \
  -H "Content-Type: application/json" \
  -d '{"grant_type":"password","client_id":"administration","username":"admin","password":"<admin-password>"}' \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")

curl -s https://sdwa5.org/api/product \
  -H "Authorization: Bearer $TOKEN"
```

### Integration (client credentials grant)

Integration "Claude MCP" (admin=true) registered in `/home/stefanr/.claude.json` (project scope) as `shopware-admin-mcp`
MCP server.

```bash
TOKEN=$(curl -s -X POST https://sdwa5.org/api/oauth/token \
  -H "Content-Type: application/json" \
  -d '{"grant_type":"client_credentials","client_id":"<accessKey>","client_secret":"<secretAccessKey>"}' \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")
```

MCP tools: `product_list/get/create/update`, `category_list/create/update/delete`, `order_list/detail/update`,
`sales_channel_list/update`, `theme_config_get/change`, `upload_media_by_url`, `dal_aggregate`, `fetch_entity_list`,
`fetch_single_entity_schema`

### Key API patterns

```bash
# Search / filter
POST /api/search/product   body: {"filter":[{"type":"equals","field":"active","value":true}]}

# PATCH requires versionId on cms_slot
PATCH /api/cms-slot/<id>   body: {"versionId":"0fa91ce3e96a4bc2be4bd9ce752c3425", ...}

# CMS slot with bilingual content
PATCH /api/cms-slot/<id>   body: {"versionId":"...", "translations": {"<langId>": {"config": {"content": {"value": "<html>", "source": "static"}}}}}

# Snippet override (per locale)
POST /api/snippet   body: {"setId":"<snippetSetId>","translationKey":"<key>","value":"<val>","author":"user"}
# Known snippet keys: detail.reachable = "No longer available" label on out-of-stock products (isCloseout=true, stock=0)

# System config
POST /api/_action/system-config   body: {"null":{"core.basicInformation.shopName":"SdWa5"}}

# Clear HTTP cache
DELETE /api/_action/cache
```

### CMS slot types

- `text` — richtext, goes through HTML sanitizer (strips iframes, scripts)
- `html` — raw HTML via `|raw`, **no sanitizer** — use for iframes/embeds
- `visibility: {"mobile": true, "tablet": true, "desktop": true}` required on blocks or they won't render
- New blocks created via API default `visibility: null` — must be patched explicitly
- Sanitizer allows `class` attribute on `table`/`div` (verified 2026-07-02, PATCH via Admin API then
  render-check on storefront) — Bootstrap utility classes below work in `text` slots, no need to fall
  back to `html` slots just to style a table.

### CMS table styling convention

Tables inside `text` slots (e.g. Hardware page spec tables) use the theme's existing Bootstrap table
CSS — no custom CSS needed:

```html

<div class="table-responsive">
    <table class="table table-bordered table-striped">...</table>
</div>
```

- `table-responsive` wrapper: horizontal scroll on narrow viewports instead of overflow/squash.
- `table table-bordered table-striped`: cell borders + row striping (theme ships full Bootstrap
  table CSS already; a bare `<table>` with no class renders borderless with browser-default zero
  cell padding).
- **Units go in the column header, not repeated in every cell** — e.g. `<th>Freq Range (Hz)</th>`
  with cell values `38–200`, not `<td>38–200 Hz</td>` repeated per row. Applies to any column where
  every cell shares the same unit.
- **Equipment identity: separate `Model` + `Brand` columns**, not combined free text (e.g. not
  `<td>Pioneer XDJ-RR</td>`). Column order is `Model` then `Brand` (matches the original
  Enclosures/Amplifiers tables — kept consistent across Hardware page, 2026-07-02 rework).
- **Units go in the column header, not repeated in every cell** — e.g. `<th>Freq Range (Hz)</th>`
  with cell values `38–200`, not `<td>38–200 Hz</td>` repeated per row. Applies to any column where
  every cell shares the same unit.

## Infrastructure

- Docker: dockware image, ports 8001 (HTTP) / 8443 (HTTPS), reverse-proxied via nginx
- Volume: `./shopware-html-data:/var/www/html`, `./shopware-mysql-data:/var/lib/mysql`
- APP_URL: `https://sdwa5.org` (set in `/opt/docker/shopware-html-data/.env`)
- DockwareSamplePlugin: uninstalled
- `composer.json`/`.lock`, `symfony.lock` and `config/{packages,routes*,services.yaml,bundles.php}` are tracked
  in the repo (everything else in `shopware-html-data/` — `.env`, `var/`, `vendor/`, `public/`, `files/`,
  `config/jwt/` — stays gitignored)
- Store-installed plugins **FroshLazySizes, FroshPlatformFilterSearch, SwagPlatformSecurity, FroshShopmon** are
  tracked too — they're not in `composer.lock` (Store install, not `composer require`), so without a repo copy
  they'd only be recoverable via the Shopware Store account. `FroshPlatformThumbnailProcessor` and
  `FroshPlatformMailArchive` don't need this — they're real composer requires.

## Shop identity

- Display name: Scheiß die Wand an 5 (SdWa5)
- Legal name: Musikverein Schmeiß die Wand an 5
- Address: Mühlenstraße 24, 5121 Ostermiething, Österreich
- ZVR: 1115343752 · Obmann: Stefan Ripper
- Email: shop@sdwa5.org
- Language: English primary, German enabled in storefront SC
- Single domain sdwa5.org with language switcher (no separate de.sdwa5.org)

## Languages & domains

Two languages on the Storefront Sales Channel, subpath domain structure (set up 2026-07):

| Domain                 | Language | Snippet set   | Currency | Units  |
|------------------------|----------|---------------|----------|--------|
| `https://sdwa5.org`    | English (default) | BASE en-GB | Euro | Metric |
| `https://sdwa5.org/de` | Deutsch  | BASE de-DE    | Euro     | Metric |

- Built-in language switcher in storefront header: purely **URL-based** (no cookie), toggles
  `sdwa5.org` ↔ `sdwa5.org/de`
- Hreflang: "Localisation according to language" → plain `de`/`en` tags (not `en-GB` etc.), because the
  channel serves multiple countries (DE, AT, GR, UK, IE, IS) under one English domain — region codes
  would be inaccurate
- Browser-language auto-redirect: done at **Caddy level**, not in Shopware (no solid free plugin exists;
  paid options are all subscription). German-language browsers hitting `/` get a one-time 302 to `/de`;
  a `lang_redirect` cookie marks "already redirected", so a manual switch back to English sticks. The
  redirect is answered by Caddy directly and never reaches Shopware, so it can't poison the HTTP cache.
  Config + test commands: see [caddy.md](caddy.md)
- `en_US`: deliberately **not** configured. US browsers send `Accept-Language: en-US`, don't match the
  `^de` redirect, and land on the English root anyway; hreflang `en` covers US searchers. Activating
  en_US (inheriting en_GB) would add a third domain and snippet maintenance for zero gain — revisit only
  if US-specific content or USD pricing is ever wanted
- `http://` domain entries were removed from the Sales Channel; Caddy redirects http→https itself

## SMTP

- Host: smtp.gmail.com:587, STARTTLS
- Auth user: ripper@sdwa5.org (Google Workspace App Password)
- Sender: shop@sdwa5.org / "Scheiß die Wand an 5"

## Tax / Payment / Shipping

- Tax: Kleinunternehmer §6 Abs. 1 Z 27 UStG — no VAT on any product or invoice
- Payment: Prepayment (bank transfer) only — invoice and COD disabled
- Shipping zones: Austria, Germany, Self Pickup (free at events)
- All items distributed as voluntary donations, no commercial sale

## Navigation & CMS pages

Main nav root: "SdWa5" category (homepage → Homepage CMS page)

Top-level order (Clothing & Merch deliberately **last** — non-commercial intent):

| Category           | URL                      | CMS page                                                  |
|--------------------|--------------------------|-----------------------------------------------------------|
| About SdWa5        | /About-SdWa5/            | About SdWa5                                               |
| ↳ Membership       | /About-SdWa5/Membership/ | Membership info + contact form (bilingual)                |
| Events             | /Events/                 | Events                                                    |
| ↳ Event Inquiry    | /Events/Event-Inquiry/   | Contact form + what-to-include checklist (bilingual)      |
| Music / Mixes      | /Music-Mixes/            | SoundCloud embed + Genre Overview + yt-dlp link (biling.) |
| Artists & Friends  | /Artists-Friends/        | 🚧 in progress — DJs (MEQ1) + Friends (bilingual)         |
| Hardware           | /Hardware/               | Speakers, amps, DSP, DJ gear, lighting (bilingual)        |
| Gallery            | /Gallery/                | Galerie (11 Flyer images, image-gallery block)            |
| Requests & Contact | /Requests-Contact/       | Booking & Contact                                         |
| Clothing & Merch   | /Clothing-Merch/         | → Clothing, Stickers, Accessories, Buttons (last)         |

Order set via `afterCategoryId` linked-list chain. CMS page names carry no "page" suffix (renamed "Music / Mixes page"
→ "Music / Mixes", "Booking & Contact page" → "Booking & Contact"). Homepage has link tiles: About, Events, Merch,
Music / Mixes, Hardware.

### Form pages (Event Inquiry / Membership)

Each page = compact text block (form-critical info only) + Shopware native `form` block (`type: contact`, posts to
`/form/contact`). Crosslinked from Events, About SdWa5, and Requests & Contact slots (EN+DE).

- Form slot config must carry full `{type, mailReceiver, confirmationText}` — if you pass partial `config` via
  `translations`, it **overwrites** the base config and drops `type: contact`, leaving an empty/broken form. Set the
  full config in both the base `config` and each language translation.
- Native contact-form element has **no field for instructional text inside the form** — only fixed fields + post-submit
  `confirmationText`. Injecting text into the form body would require overriding `cms-element-form.html.twig` or
  `contact.*` snippets, both site-wide (affects Requests & Contact too) = core change, avoided. Instructional text kept
  as a minimal CMS text block above the form instead.

## Legal pages

"Rechtliches" is the sales channel's **Footer service navigation** root (`serviceCategoryId`) —
renders as a flat link row in the footer-bottom bar, not a footer column. Old `/Rechtliches/*/`
URLs 301-redirect to the new ones (Shopware kept the superseded SEO URLs as redirects).
System configs wired: imprintPage, privacyPage, tosPage, revocationPage, shippingPaymentInfoPage

| Page           | URL              | Content                                                       |
|----------------|------------------|---------------------------------------------------------------|
| Impressum      | /Impressum/      | §5 ECG — name, address, ZVR, Obmann, Kleinunternehmer         |
| Datenschutz    | /Datenschutz/    | DSGVO — Art. 6, rights Art. 15–22, DSB contact, BAO retention |
| AGB            | /AGB/            | Bilingual — German AGB + English T&C, donation model, no VAT  |
| Widerrufsrecht | /Widerrufsrecht/ | §11 FAGG Widerrufsbelehrung + Muster-Formular                 |

## Footer

- **Footer navigation** (`footerCategoryId`, rendered as columns): **Follow Us** (Facebook,
  Instagram, YouTube), **Admin** (ERP erp.sdwa5.org, Vault vault.sdwa5.org)
- **Footer service navigation** (`serviceCategoryId`, rendered as a flat bottom-bar link row):
  Rechtliches — Impressum, Datenschutz, AGB, Widerrufsrecht
- **Contact column**: shop@sdwa5.org + link to /Requests-Contact/ (via `footer.serviceHotline*` snippets — default "
  Service hotline" block repurposed)

## Merch catalog (currently shown as: "no longer available")

Prices: selling price = €0 (voluntary donation), list price = Verkaufswert (crossed out), purchase price = Stückkosten

| Product                              | Purchase price | List price |
|--------------------------------------|----------------|------------|
| T-Shirt                              | €6,59          | €20,00     |
| Hoodie 3-colour (black/white/red)    | €18,43         | €30,00     |
| Hoodie 2-colour (black/white)        | €17,59         | €30,00     |
| Hoodie 1-colour (white)              | €16,75         | €30,00     |
| Hospital Gown                        | —              | —          |
| Propeller Hat                        | —              | —          |
| Logo Button                          | €0,10          | €1,00      |
| Logo Sticker                         | €0,10          | €1,00      |
| Piss on your local techno DJ Sticker | €0,10          | €1,00      |
| "Laut hier" Sticker                  | €0,10          | €1,00      |
| Keychain                             | €1,00          | €3,00      |
| Mini Speaker                         | €5,00          | €10,00     |
| Battery Beer Crate                   | €1,80          | €5,00      |
| Face Pin Badges                      | €0,10          | €1,00      |
| Business Cards                       | €1,00          | €3,00      |
| Tubes                                | €1,00          | €2,00      |
| DJ USB Drive                         | €15,00         | €30,00     |

Product numbers: SDWA5-* · Images added

## Cookie consent

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

### Native vs. non-native gating

YouTube and Vimeo are gated natively — Shopware ships dedicated CMS element types with built-in JS
consent plugins that block the iframe until the user accepts. No custom code needed.

**Non-native embeds (e.g. SoundCloud)** have no equivalent. To add one compliantly:

- Register a new cookie entry in the "Comfort features" group via `POST /api/snippet`
- Gate the iframe manually: inline JS in the HTML CMS slot that reads Shopware's `cookie-preference`
  browser cookie and swaps in the iframe on consent — OR write a small custom Storefront JS plugin

**Shopware services** (Analytics, AI Copilot, etc.) self-register their consent entries in the native
system automatically — no custom wiring needed.

### Third-party CMP decision threshold

Native Shopware consent (current setup) remains sufficient as long as:

- Non-native third-party embeds stay few (≤2) and are wired manually
- No audit trail / documented per-user consent records required
- No auto-scanning of all page cookies needed

Switch to **frosh/cookieman** (Shopware plugin, free, open source) if 3+ non-native services are added —
it provides generic embed gating without full SaaS CMP overhead.

Switch to a **SaaS CMP** (Cookiebot, Usercentrics) only if scale grows significantly or AT authority
scrutiny requires proof-of-consent infrastructure.

## Theme / Design

Theme: Shopware default Storefront — assigned to Storefront SC only. All values saved via Admin UI.

Note: `theme_config_get` API returns an incomplete view (not all saved fields). Source of truth is
Admin → Themes → edit theme config.

**Colors (explicitly set):**

| Variable                 | Light value | Light lightness | Dark lightness |
|--------------------------|-------------|-----------------|----------------|
| `sw-color-brand-primary` | `#1fe51f`   | 51%             | 51% (excluded) |
| `sw-color-buy-button`    | `#e5231f`   | 51%             | 51% (excluded) |
| `sw-border-color`        | `#c2c2c2`   | 76%             | 24%            |
| `sw-text-color`          | `#595959`   | 35%             | 65%            |
| `sw-headline-color`      | `#141414`   | 8%              | 92%            |

All other colors: Storefront theme defaults. Border/Text/Headline light values were picked specifically
so the Dark Mode plugin's lightness inversion (`L_dark = 100% - L_light`, see plugin section below) lands
them in the recommended dark-mode target ranges. Primary/Buy button are brand colors — high saturation
keeps them above the plugin's saturation threshold, so it leaves them untouched in both modes.

**Logos / images (all replaced):**

- Desktop logo: media `019f1316…`
- Mobile logo: media `019f1316…` (same as desktop)
- Tablet logo: media `019f1316…` (same as desktop)
- Favicon: media `019f130c…`
- Share image (OG): media `019f130d…`

### Dark Mode Storefront plugin

Plugin "Dark Mode Storefront" (technical name `DneStorefrontDarkMode`, composer `dne/storefront-dark-mode`,
v4.0.0) installed — applies to all themes. Inverts lightness of colors below the saturation threshold to
generate a dark counterpart at runtime (post-CSS, via a Sabberworm CSS rewrite pass); colors above the
threshold (vivid brand colors) are left untouched in both modes.

| Setting                                                        | Value   |
|----------------------------------------------------------------|---------|
| Percentage of minimum lightness                                | 8       |
| Percentage threshold for color contrast (saturation threshold) | 65      |
| All other settings                                             | default |

**Known bug — Admin save fails with false "SCSS Value ... is not valid for type color":**

Happens when setting *any* low-saturation/gray color (Border, Text colour, Headline color, Background,
etc. — anything under the saturation threshold above) via Admin → Themes → edit theme config. Root cause:
the plugin decorates Shopware core's `ScssPhpCompiler` service globally (`services.xml`:
`decorates="Shopware\Storefront\Theme\ScssPhpCompiler"`). Shopware's own save-time validator
(`SCSSValidator::validateTypeColor`) compiles a throwaway one-line snippet through that same decorated
service to sanity-check the color; the plugin's rewrite pass injects extra `:root` / `@media` blocks into
that snippet, which breaks the validator's greedy unanchored regex and produces a false "invalid color"
error. Vivid/high-saturation colors (Primary, Buy button) are unaffected — they're above the saturation
threshold, so the plugin skips rewriting them, and validation sees clean CSS.

This is *not* a real compile problem — `bin/console theme:compile` succeeds fine even when Admin save
rejects the value. Confirmed via direct scssphp test (raw compiler compiles the "invalid" colors without
issue) and via services.xml (decoration target confirmed).

**Workaround** when setting a new gray/muted color via Admin:

1. `bin/console plugin:deactivate DneStorefrontDarkMode` (+ `cache:clear`)
2. Set the color in Admin → Themes → edit theme config, save (validation now uses the undecorated
   compiler, passes)
3. `bin/console plugin:activate DneStorefrontDarkMode` (+ `cache:clear`)

No upstream fix applied — plugin is at latest available version (4.0.0, not upgradeable per
`plugin:list`). Worth reporting to the plugin author (global compiler decoration corrupting core's
validation-only compiles) or Shopware core (validator regex too fragile — should be non-greedy/anchored).

## TODO

1. Language switching — done except: home page in German isn't up to date with English (and broken
   design). Setup documented under [Languages & domains](#languages--domains)
2. update email templates (order confirmation etc. still default Shopware copy)
    1. dont get too fancy (e.g. with corporate or blogging style expressions)
    2. en and de
3. Search: include CMS pages — storefront search currently returns only products. Extend to also surface CMS
   pages, ideally as primary/first results (content pages are more likely what visitors search for than merch).
4. Cookie consent
    1. SoundCloud embed — register cookie entry in "Comfort features" group + gate iframe behind consent
    2. `cookie.messageTextPage` (the main consent banner text) still renders its link as `/page/cms/Array` —
       confirmed live 2026-07-03, not just a stale-cache issue. `cookie.descriptionInfo` (a separate, secondary
       snippet — not the main banner) was fixed and confirmed pointing at the current Datenschutz URL.
5. Merch / Products
    1. Make use of variants and other product related shopware features
    2. Add missing product images, remove background / opacity from existing images
    3. Non-binding preorders / interest capture — no native Shopware 6 core feature for this.
       `GET /api/product-notification` → 404 confirms. Options:
        - Contact form (zero effort): link from product/category pages to /Requests-Contact/ — captures
          interest via email, fully manual
        - Plugin (paid): back-in-stock / waitlist plugins on Shopware marketplace (e.g. ACRIS stock
          notification) — adds "notify me" button on out-of-stock products, admin sees subscriber list
6. Checkout end-to-end test — no real order flow tested yet
7. SEO — meta titles/descriptions empty on all pages, no sitemap submitted
8. Switch store-installed plugins to composer install — FroshLazySizes, FroshPlatformFilterSearch,
   SwagPlatformSecurity, FroshShopmon are currently installed via the Shopware Store plugin manager and not in
   `composer.json`/`composer.lock` (unlike FroshPlatformThumbnailProcessor, FroshPlatformMailArchive). Their
   source is now tracked in git as a stopgap (see [infrastructure.md](infrastructure.md)), but `composer require`
   would be the proper fix so `composer install` alone reproduces the install and updates go through Composer.
9. update mysql and php
10. frosh tools system-status
    1. System Health
    2. Performance recommendations
11. Hide cart UI when irrelevant — hide cart icon, minicart, and related shop chrome when cart is empty AND user
    is not on a PDP or category listing page. Reduces commercial appearance on content-only pages.
12. Privacy + ToS pages — legal text review by Austrian lawyer (DSGVO, AGB)
13. Content
    1. add images
    2. add "useful links" page
        1. grouped overview
        2. use everything useful from my firefox bookmarks
    3. Artists & Friends
        1. add links
        2. asked in SdWa5 Family Whatsapp group who wants to be featured -> wait for responses
