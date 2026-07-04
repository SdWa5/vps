# Theme / Design

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

## Dark Mode Storefront plugin

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
