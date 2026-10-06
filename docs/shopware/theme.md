# Theme / Design

The Storefront sales channel runs **`SdWa5Theme`**, a theme plugin that lives in this repository at
[`shopware-html-data/custom/static-plugins/SdWa5Theme/`](../../shopware-html-data/custom/static-plugins/SdWa5Theme/).
It is a port of the Chimo Diazz theme (`ChimodiazzTheme` 1.16.3 in `chimodiazz/website`) with the SdWa5
colours, a small graffiti logo, low-key voluntary donation links and a full-width homepage hero. It
replaces the Shopware default Storefront theme, whose stored config stays as the rollback target.

`tests/shopware-theme.bats` guards the parts that fail silently, see [What the tests guard](#what-the-tests-guard).

## Layout of the plugin

| Path under `src/Resources/` | Content |
|---|---|
| `theme.json` | views `[@Storefront, @Plugins, @SdWa5Theme]`, the `sw-*` colours and fonts, `sdwa5-donation-url` |
| `app/storefront/src/scss/base.scss` | entry point, imports the partials below |
| `…/_tokens.scss` | **every colour literal of the theme**, as light and dark token maps |
| `…/_fonts.scss`, `_base-elements.scss` | fonts, body, headings, links, buttons, badges, offcanvas |
| `…/_header.scss` | sticky glass header, logo, donation button, shop context |
| `…/_hero.scss` | homepage hero crop, hero text, link tiles |
| `…/_footer.scss` | footer, donation line, share bar |
| `app/storefront/src/assets/` | fonts with their OFL licence, `logo/sdwa5-logo.webp` |
| `views/storefront/` | Twig overrides, each block calls `parent()` unless it replaces it on purpose |
| `snippet/{en_GB,de_DE}/` | every text the theme adds, under `sdwa5.*` |

The theme config merges in this order, measured in Shopware's `DatabaseConfigLoader`: the Storefront
theme's `theme.json` and its stored admin values, then this theme's `theme.json` and its stored values.
So the colours in our `theme.json` win over what was saved for Storefront in the admin, while the
favicon and the share image, which this theme does not set, still come from Storefront's stored config.

## Colours and the dark mode plugin

Dark mode comes from the **Dark Mode Storefront** plugin (`DneStorefrontDarkMode` 4.0.0), which applies
to every theme. It does not use a dark palette. It rewrites the compiled CSS and appends, for every rule
that holds a colour, a dark copy under `:root[data-theme="dark"]` and under
`@media (prefers-color-scheme: dark){:root:not([data-theme="light"])}`. Read in its
`ThemeCompileSubscriber` on 2026-10-06, the rewrite works like this:

- A colour whose natural saturation `max(S − |L − 50|, 0)` is at most the threshold (65) gets the
  lightness `L' = min(100 − L + L · 8 / 100, 100)` with hue and saturation kept. A more saturated colour
  stays as it is.
- Every colour with an alpha channel is converted, and so are named colours such as `white`.
- `box-shadow` is skipped, and so is **every property whose name ends in `-immutable`**.

The theme uses that last rule. Its own components read custom properties named `--sdwa5-*-immutable`,
which DNE never touches, and `_tokens.scss` writes the dark values for them itself, under the same
selector pair DNE uses. Core Shopware and Bootstrap read the `sw-*` values from `theme.json` instead,
and those are light values chosen so that DNE's inversion lands on the Chimo Diazz dark colours.

| Token | Light | Dark | Used for |
|---|---|---|---|
| `bg` | `#f5f5f8` | `#0a0a0f` | page background |
| `surface` | `#fcfcfd` | `#12121b` | cards, header, also `sw-background-color` |
| `text` | `#101018` | `#e8e8f0` | body text, also `sw-text-color` |
| `headline` | `#0a0a0f` | `#f0f0f5` | headings, also `sw-headline-color` |
| `muted` | `#55556a` | `#9d9db0` | secondary text, VAT line, copyright |
| `border` | `#e1e1e9` | `#252532` | also `sw-border-color` |
| `green` | `#1fe51f` | `#1fe51f` | fills only, also `sw-color-brand-primary` |
| `green-text` | `#0a7d0a` | `#1fe51f` | green text and focus ring |
| `red` | `#e5231f` | `#e5231f` | fills and large text, also `sw-color-brand-secondary` and `sw-color-buy-button` |
| `link` / `link-hover` | `#006b73` / `#0a7d0a` | `#00f0ff` / `#1fe51f` | links |
| `on-green` / `on-red` | `#0a0a0f` / `#ffffff` | the same | text on a green or red fill |
| `glass`, `share-bg`, `logo-shadow` | alpha colours | alpha colours | sticky header, share bar, logo halo |

The DNE outputs in the `Dark` column were computed from its formula, so `#fcfcfd` becomes `#12121b`,
`#101018` becomes `#e8e8f0` and `#e1e1e9` becomes `#252532`. `#1fe51f`, `#e5231f` and `#006b73` stay
unchanged. Text on the green or red fill is always set from `on-green` or `on-red`. Before the theme,
DNE turned the text on `.btn-primary` white in dark mode and the text on `.badge` white in light mode,
which put white on `#1fe51f` at a contrast of about 1.7:1. The measured WCAG contrasts now are 11.56:1
for `#0a0a0f` on green, 4.57:1 for white on red, 5.76:1 for the light link colour and 4.88:1 for
`green-text` on the light background.

Three rules keep this working, and the tests enforce the first two.

1. **A colour literal appears only in `_tokens.scss`.** Anywhere else DNE would invert it, and it would
   no longer match its token in dark mode.
2. **The dark blocks hold nothing but the token mixin and `color-scheme`.** A literal there would be
   inverted a second time.
3. **An alpha colour is a token**, because DNE converts every alpha colour regardless of saturation.

`TcinnCopyrightCustom` prints its copyright line with an inline `color:#fff`. The footer overrides it
with the `muted` token.

## Header, logo and navigation

- **A sticky glass bar with two rows on desktop.** The first row holds the logo, search, the account
  menu, the settings column with the DNE toggle, language and currency, the cart and the donation
  button. The second row is the main navigation in monospaced caps. A 3 px gradient in green, cyan and
  red runs above the page. The Storefront top bar is emptied, because its contents moved into the
  first row.
- **Below 992 px** the row holds the burger, the logo, the donation button and the cart, and search
  takes a line of its own on phones. The settings column is hidden, because DNE injects its toggle into
  the offcanvas menu there and language and currency are in the offcanvas as well.
- **The logo** is `assets/logo/sdwa5-logo.webp`, 213×88 px shown at 107×44 px, built from the live
  `Graffiti_Banner_cut.png` in Drive. It is read through `asset('…', 'theme')`, so the logo media stored
  in Storefront's config is ignored by this theme. A faint light halo keeps it legible in dark mode. To
  rebuild it:

  ```bash
  docker run --rm -v "$PWD:/w" -w /w alpine:3.20 sh -c 'apk add --no-cache imagemagick imagemagick-webp;
    magick Graffiti_Banner_cut.png -trim +repage -resize 213x88 -strip -quality 90 \
      -define webp:alpha-quality=95 -define webp:method=6 sdwa5-logo.webp'
  ```

  If the graffiti logo does not convince at this size, a text wordmark is the fallback, filed in
  [TODO.md](TODO.md).

### Shop context

sdwa5.org is primarily the association's homepage, so the shop chrome shows only where it is needed.
`views/storefront/base.html.twig` adds the body class `sdwa5-shop-context` on product pages, search
results, the wishlist, checkout and account pages, and on every CMS page of the type `product_list`,
which covers the merch categories. Without that class the header hides search, the account menu and the
currency switcher, and it hides the cart unless the cart holds something.

The class sits on `<body>` rather than in the header template, because the header is rendered as an
ESI sub-request and cannot see which page it belongs to. It depends only on the URL, so the HTTP cache
stays correct. "The cart holds something" is `.header-cart:has(.header-cart-badge)`, because Shopware
adds the badge client-side when the cart widget loads. The header cart total is hidden everywhere,
because every merch price is €0.

## Voluntary donation

Three links lead to `https://paypal.me/SdWa5`, which is the association's only channel because it has
no bank account. One is an outline button with a heart in the header, one is an entry in the offcanvas
menu, and one is a line above the footer bottom. All three open in a new tab with
`rel="noopener noreferrer"`.

The URL is the theme config field **`sdwa5-donation-url`**, editable under Admin → Themes → SdWa5Theme,
with the PayPal page as its default. It is `scss: false`, so changing it needs no theme compile.

The copy says "Voluntary Donation" and "Freiwillige Spende". It never calls the association
gemeinnützig or charitable and never promises a tax benefit, because the association is registered
only as not aimed at profit. It also never ties a donation to merch, because that legal question is
open. A test fails on any of those words in the donation snippets.

## Share links

Every page except checkout and account carries plain links to share it on WhatsApp, Telegram and by
e-mail. There is no JavaScript and no third-party script, so nothing loads before a click. From 992 px
they form a vertical bar fixed at the right edge of the screen. Below that they form a row at the end
of the main content. Between 992 and 1400 px the content and the footer get right padding, because the
container runs edge to edge there and the bar covered up to 18 px of it.

They are deliberately not in the offcanvas menu, where Chimo Diazz has them. The offcanvas is part of
the ESI header, so a link built there always shares the site root. Measured on 2026-10-06 on a Chimo
Diazz subpage, where the aside shared the subpage and the offcanvas shared the root. That bug is filed
in the root [TODO.md](../../TODO.md).

## Homepage hero and tiles

The theme styles two homepage sections by CSS class, and the classes live in the database:

| Section | Position | Setting | Effect |
|---|---|---|---|
| Hero image | 0 | `sizingMode: full_width`, class `sdwa5-hero` | the image spans the screen, cropped top and bottom to `clamp(14rem, 42vw, 34rem)` |
| Hero text | 1 | class `sdwa5-hero-text` | caps headline, monospaced stats line, slogan in red |
| Link tiles | 2 | class `sdwa5-tiles` | the five tiles become a card grid |

[`tools/shopware/set-homepage-sections.sh`](../../tools/shopware/set-homepage-sections.sh) sets
positions 0 and 2, dry run by default. The crop keeps the point `--sdwa5-hero-focus` (default
`50% 45%`, in `_tokens.scss`) in view. **Removing a class or the full-width mode in the admin breaks the
layout**, see [content-cms.md](content-cms.md).

## Not ported from Chimo Diazz

These parts of `ChimodiazzTheme` are Chimo Diazz content rather than design, so they stayed behind:

- **The anchor navigation.** Chimo Diazz is a one-page site with an empty category tree, and its navbar
  links hard-coded `#booking` and `#kooperation` sections. sdwa5 has nine real categories, which take
  that place in the same styling. The `scroll-margin-top` for the sticky header came along.
- **The booking cards' copy.** Club-Set, Festival-Show and Corporate/Event are CMS content in the Chimo
  Diazz database. The card styling came along and styles the homepage tiles.
- **The booking button in the header.** Its slot holds the donation button.
- **The meta and title fallbacks.** sdwa5 keeps its own SEO settings.
- **Hiding the buy button and the price on product pages.** sdwa5 is a shop.
- **Blanking the footer hotline.** sdwa5 uses the hotline snippets for its Contact column.
- **The vertical rhythm rules** `.cms-section + .cms-section` and `.cms-block + .cms-block`. They would
  break the tiles grid, and sdwa5's CMS blocks carry their own spacing.

The footer VAT line keeps its wording, because that wording is part of the pending legal pass. The
theme overrides neither of its snippets, and only its look changed.

## Deploy

The theme is a composer path package. `shopware-html-data/composer.json` requires
`sdwa5/sdwa5-theme` at its exact version, and `composer install` symlinks it into `vendor/` from
`custom/static-plugins/SdWa5Theme`, see [plugins.md](plugins.md). The first install on the host:

```bash
cd /opt/docker && git pull --ff-only
chown -R 33:33 shopware-html-data/custom/static-plugins/SdWa5Theme
flock /run/lock/shopware-worker.lock sh -c 'set -e
  docker exec shopware composer install --no-interaction
  docker exec shopware bin/console plugin:refresh
  docker exec shopware bin/console plugin:install --activate SdWa5Theme
  docker exec shopware bin/console theme:change SdWa5Theme --sales-channel 019c36d914f7706bbebf391b033a74d0 --sync
  docker exec shopware bin/console cache:clear'
docker exec -u root shopware sh -c 'kill -USR2 "$(pgrep -f "php-fpm: master")"'
tools/shopware/set-homepage-sections.sh            # from a workstation, then again with --apply
```

A later change to the theme needs the pull, a version bump in the three places the tests compare,
`composer install`, `plugin:update SdWa5Theme`, `theme:compile` and `cache:clear`. The deploy marker
`<meta name="sdwa5:theme" content="…">` in every page head shows which version is live. Automating
this is filed in the root [TODO.md](../../TODO.md).

## Rollback

About one minute. The sections go first, because the Storefront theme would otherwise show the uncropped
4:3 hero across the full width.

```bash
tools/shopware/set-homepage-sections.sh --revert --apply           # from a workstation
flock /run/lock/shopware-worker.lock sh -c 'docker exec shopware bin/console theme:change Storefront --sales-channel 019c36d914f7706bbebf391b033a74d0 --sync && docker exec shopware bin/console cache:clear'
```

The Storefront theme's stored config was never touched, so the old look returns exactly. It holds
primary `#1fe51f`, buy button `#e5231f`, border `#c2c2c2`, text `#595959`, headline `#141414` and the
graffiti banner as logo. The plugin can stay installed.

## Known bug in the dark mode plugin: admin save rejects grey colours

Saving any low-saturation colour under Admin → Themes → edit theme config fails with a false
"SCSS Value … is not valid for type color". It affects every colour under the saturation threshold,
which includes the theme's background, text, headline and border colours.

The cause is that the plugin decorates core's `ScssPhpCompiler` globally (`services.xml`:
`decorates="Shopware\Storefront\Theme\ScssPhpCompiler"`). Shopware's save-time validator
`SCSSValidator::validateTypeColor` compiles a one-line snippet through that decorated service, the
plugin's rewrite adds its `:root` and `@media` blocks to the snippet, and the validator's greedy
unanchored regex then fails. Saturated colours pass, because the plugin skips them. This is not a real
compile problem, because `bin/console theme:compile` succeeds with the same value.

The colours of `SdWa5Theme` come from `theme.json`, so the bug matters only when one is overridden in
the admin. The workaround then is:

1. `bin/console plugin:deactivate DneStorefrontDarkMode` and `cache:clear`
2. save the colour in the admin
3. `bin/console plugin:activate DneStorefrontDarkMode` and `cache:clear`

4.0.0 is the latest version of the plugin, so no upstream fix exists. The bug is worth reporting to the
plugin author, for the global decoration, or to Shopware, for the fragile validator regex.

## What the tests guard

`tests/shopware-theme.bats`:

- every JSON file parses, and the English and German snippets have the same keys
- every `sdwa5.*` snippet a template uses exists in both languages
- the plugin version, the root require, the lock and the meta marker agree
- the views order, the fonts with their licence, and the logo file
- colour literals only in `_tokens.scss`, equal light and dark token sets, dark blocks with tokens only
- the donation copy, its label, its default URL and `rel` on every external link
- the VAT wording is untouched, and every override calls `parent()` unless it replaces a block on purpose

`tests/shopware-homepage-sections.bats` covers the sections script, including that the classes it sets
are the ones `_hero.scss` styles.
