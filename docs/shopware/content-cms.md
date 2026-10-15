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

## Editing text slots

Text in a `text` slot is changed with `tools/shopware/edit-slots.sh` and an edits file, rather than by
hand-written PATCH calls. Each edit names the slot, the language, the exact old text and the new text. The old
text has to occur exactly once, and every edit is checked before the first write, so a typo leaves the page
untouched. A slot's config is one JSON column, so the script writes the whole config back with only the content
string changed. The edits that were run stay in `tools/shopware/slot-edits/` as a record and as examples.

```bash
tools/shopware/edit-slots.sh tools/shopware/slot-edits/hardware-m2122.json            # what would change
tools/shopware/edit-slots.sh tools/shopware/slot-edits/hardware-m2122.json --apply    # write it
```

The same tool edits mail templates. An edit with `"target": "mail-template"` names the template id in
`template` and the field in `field`, `contentHtml`, `contentPlain`, `subject` or `senderName`, instead of a slot. All edits to one
template and language go out in one PATCH under that language. An insertion keeps its anchor in the new text,
and the tool counts it as current once the new text is there, so a second run does not insert it twice.
`order-mail-donation.json` adds the voluntary donation note to the order confirmation mail in English and
German, wrapped in a Twig condition that prints it only when the order holds a donation item.

```bash
tools/shopware/edit-slots.sh tools/shopware/slot-edits/order-mail-donation.json --apply
```

### Order mail copy and verification

`order-mail-copy.json` corrects the confirmation and cancellation templates in EN and DE, in HTML and
plain text. Both use the sender name SdWa5 and a single greeting. Confirmation mails show payment
instructions only when `order.amountTotal > 0`; a free order keeps the donation-at-pickup note without
asking for payment or offering an additional payment. Cancellation subjects name the cancellation and
order number, and the body names SdWa5. Both templates format order dates in `Europe/Vienna` explicitly,
so an event rendered with a UTC context still shows local time, including daylight saving time.

```bash
tools/shopware/edit-slots.sh tools/shopware/slot-edits/order-mail-copy.json
tools/shopware/edit-slots.sh tools/shopware/slot-edits/order-mail-copy.json --apply
tools/shopware/check-order-mail.sh ORDER_ID
```

The last command only renders. It does not send mail or modify an order. It checks the persisted templates
in strict mode against the selected order, checks both payment branches with synthetic totals, and checks
winter and summer time conversion. It requires the same API credentials as the editing tool. Its synthetic
checks use the no-send build endpoint provided by the project's pinned Shopware 6.7.

On 2026-10-15 guest test order 10000 contained two top models at a payable total of €0 and a suggested
donation of €10. The guest checkout completed, the owner confirmed receipt of the confirmation and
cancellation emails, and the order state was verified as cancelled. The copy corrections above were then
verified with strict no-send previews in both languages and formats, including the same 09:15 local order
time while the input context used UTC. Inbox delivery of another corrected email has not been checked.

Slot ids come from a read-only search on `cms-slot-translation`, filtered by a word of the old text. Mail
template ids come from one on `mail-template-translation`.
`set-address.sh` predates the tool and keeps its own slot logic, because it also writes the system config and
the document templates.

## Navigation & CMS pages

Main nav root: "SdWa5" category (homepage → Homepage CMS page)

Top-level order (Clothing & Merch deliberately **last** — non-commercial intent):

| Category           | URL                      | CMS page                                                  |
|--------------------|--------------------------|-----------------------------------------------------------|
| About SdWa5        | /About-SdWa5/            | About SdWa5                                               |
| ↳ Membership       | /About-SdWa5/Membership/ | Membership info + contact form (bilingual)                |
| Events             | /Events/                 | Events                                                    |
| ↳ Event Inquiry    | /Events/Event-Inquiry/   | Contact form + what-to-include checklist (bilingual)      |
| Music / Mixes      | /Music-Mixes/            | SoundCloud embed (click-to-load facade, consent-gated) + Genre Overview + yt-dlp link (biling.) |
| Artists & Friends  | /Artists-Friends/        | 🚧 in progress — DJs (MEQ1) + Friends incl. darkbloc 🇹🇷; PSL (IG) + Scheiterhaufen (FB) linked (bilingual) |
| Hardware           | /Hardware/               | Speakers, amps, DSP, DJ gear, lighting (bilingual)        |
| Gallery            | /Gallery/                | Galerie (11 Flyer images, image-gallery block)            |
| Requests & Contact | /Requests-Contact/       | Booking & Contact                                         |
| Clothing & Merch   | /Clothing-Merch/         | → Clothing, Stickers, Accessories, Buttons (last)         |

Order set via `afterCategoryId` linked-list chain. CMS page names carry no "page" suffix (renamed "Music / Mixes page"
→ "Music / Mixes", "Booking & Contact page" → "Booking & Contact"). Homepage has link tiles: About, Events, Merch,
Music / Mixes, Hardware.

**The homepage sections carry the classes the theme styles, and they have to stay.** The hero image section
(position 0) is `full_width` with the class `sdwa5-hero`, the hero text section (position 1) has
`sdwa5-hero-text`, and the tiles section (position 2) has `sdwa5-tiles`. Without them the hero is no longer
cropped and the tiles lose their card grid. A rebuilt homepage needs them set again, and its new section ids
pinned in `tools/shopware/set-homepage-sections.sh`. See [theme.md](theme.md#homepage-hero-and-tiles).

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
System configs wired: imprintPage, privacyPage, tosPage, revocationPage, shippingPaymentInfoPage,
contactPage. **2026-07-20:** removed SC-scoped `{"_value": uuid}`-corrupted duplicate rows of these
(from the 2026-06-29 footer-nav write) that caused `/page/cms/Array` links — storefront now uses the
correct bare-UUID null-scope defaults. See [cookie-consent.md](cookie-consent.md).

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
