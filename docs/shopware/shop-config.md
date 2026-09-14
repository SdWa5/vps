# Shop configuration

## Shop identity

- Display name: Scheiß die Wand an 5 (SdWa5)
- Legal name: Musikverein Schmeiß die Wand an 5
- Address: Egitlweg 6, 5322 Hof bei Salzburg, Österreich (since 2026-09-14)
- ZVR: 1115343752 · Obmann: Stefan Ripper
- The storefront Impressum, Datenschutz and AGB pages live in the Shopware database, not here.
  The AGB still name Ostermiething as the place of jurisdiction, and that is correct until the
  seat moves: the registered Sitz is still Ostermiething and only the postal address changed.
  See the parent repo's [`docs/organization.md`](../../../docs/organization.md).
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
  Config + test commands: see [caddy.md](../caddy.md)
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
