# Shopware TODO

1. update email templates (order confirmation etc. still default Shopware copy)
    1. dont get too fancy (e.g. with corporate or blogging style expressions)
    2. en and de
2. Layout for 404 pages Assign layout...
3. Shop page layout for maintenance pages Select layout
4. Search: include CMS pages — storefront search currently returns only products. Extend to also surface CMS pages,
   ideally as primary/first results (sdwa5.org primarily used as homepage, online shop secondary functionality). If this
   todo isnt solvable using built-in Shopware features or free plugins, move this todo to the "Hide cart UI"
   todo
5. Merch / Products
    1. Make use of variants and other product related shopware features
    2. Add missing product images, remove background / opacity from existing images
    3. Non-binding preorders / interest capture — no native Shopware 6 core feature for this.
       `GET /api/product-notification` → 404 confirms. Options:
        - Contact form (zero effort): link from product/category pages to /Requests-Contact/ — captures interest via
          email, fully manual
        - Plugin (paid): back-in-stock / waitlist plugins on Shopware marketplace (e.g. ACRIS stock notification) —
          adds "notify me" button on out-of-stock products, admin sees subscriber list
    4. Actual preorders — accept binding, paid orders for merch that is not in stock yet, with a
       stated delivery date or window. **The reason is the money, not the feature.** Merch is
       markedly cheaper per piece in bulk, and the association cannot accumulate the capital for a
       bulk order before it has sold anything. A preorder run turns that around, because the
       customers fund the order they are waiting for. That gives the two variants a shared purpose
       and a clear split. 5.3 only counts interest, which sizes the bulk order but pays for nothing.
       This item takes the money up front, which is what actually unlocks the bulk price.
       Check first how far core Shopware carries it. The clearance sale flag, the stock and restock
       time fields and the delivery time of a product are the relevant settings, and a plugin is
       only needed if they are not enough. Three decisions belong to this.
        - When the money is taken, at order time or at dispatch. Only "at order time" finances the
          bulk order, so this is the decision the whole item rests on.
        - A minimum quantity below which the run does not happen, and what happens to the money
          then. A refund path has to exist before the first preorder is sold.
        - The legal wording for a binding prepaid sale with a later delivery date, which goes into
          the same AGB pass as item 13. Taking money for goods not yet ordered is the part a
          non-profit should get right on paper.
6. Checkout end-to-end test — no real order flow tested yet
   (deferred — not selling products yet)
7. SEO — meta titles/descriptions empty on all pages, no sitemap submitted
8. Switch store-installed plugins to composer install — FroshLazySizes, FroshPlatformFilterSearch, SwagPlatformSecurity,
   FroshShopmon are currently installed via the Shopware Store plugin manager and not in
   `composer.json`/`composer.lock` (unlike FroshPlatformThumbnailProcessor, FroshPlatformMailArchive). Their source is
   now tracked in git as a stopgap (see [infrastructure.md](../infrastructure.md)), but `composer require`
   would be the proper fix so `composer install` alone reproduces the install and updates go through Composer.
9. update mysql and php
10. frosh tools system-status
    1. System Health
    2. Performance recommendations
11. Hide cart UI when irrelevant — hide cart icon, minicart, and related shop chrome when cart is empty AND user is not
    on a PDP or category listing page. Reduces commercial appearance on content-only pages.
12. Content
    1. add images
    2. add "useful links" page
        1. grouped overview
        2. use everything useful from my firefox bookmarks
    3. Artists & Friends
        1. add links
        2. asked in SdWa5 Family Whatsapp group who wants to be featured -> wait for responses
13. Apply legal-page wording fixes from
    [privacy-tos-review-2026-07-22.md](privacy-tos-review-2026-07-22.md) — pending Obmann/board sign-off, in
    particular the €0-donation-mechanic characterization decision (Path 1 vs. Path 2 in that doc's section A1),
    before editing the live Datenschutz/AGB/Impressum/Widerrufsrecht CMS pages.
