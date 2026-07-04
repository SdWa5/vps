# Content & CMS

## CMS slot types

- `text` — richtext, goes through HTML sanitizer (strips iframes, scripts)
- `html` — raw HTML via `|raw`, **no sanitizer** — use for iframes/embeds
- `visibility: {"mobile": true, "tablet": true, "desktop": true}` required on blocks or they won't render
- New blocks created via API default `visibility: null` — must be patched explicitly
- Sanitizer allows `class` attribute on `table`/`div` (verified 2026-07-02, PATCH via Admin API then
  render-check on storefront) — Bootstrap utility classes below work in `text` slots, no need to fall
  back to `html` slots just to style a table.

## CMS table styling convention

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
