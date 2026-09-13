# Shopware TODO

1. **Five Shopware AG service apps are installed and four are active**, namely `ShopwarePayments`,
   `Swag3DModelPipeline`, `SwagAIImageEditor` and `SwagCopilot`, with `ShopwareNexusIngestionService`
   present but inactive. Found 2026-09-08 while draining the message queue. They install and update
   themselves through the `services.install` scheduled task and phone home to
   `registry.services.shopware.io`. None of them appears in
   the 2026-07-22 legal review, which now lives in Google Drive, so whether a non-profit wants
   an AI image editor, a Copilot and an event ingestion service active on its shop is open. Decide per
   app, then either deactivate the unwanted ones or cover them in the same privacy pass as item 14
   (`decision`)
2. update email templates (order confirmation etc. still default Shopware copy)
    1. dont get too fancy (e.g. with corporate or blogging style expressions)
    2. en and de
3. Layout for 404 pages Assign layout...
4. Shop page layout for maintenance pages Select layout
5. Search: include CMS pages — **measured 2026-09-08 and confirmed**. `?search=Hoodie` returns products,
   while `Membership`, `Hardware`, `Impressum`, `Datenschutz` and `Gallery` return nothing at all, even though all
   five exist as CMS pages and all five are in the sitemap. So the storefront search is product-only as suspected.
   Extend it to also surface CMS pages, ideally as primary results, since sdwa5.org is primarily a homepage and the
   shop is secondary. Shopware core has no CMS-page search, so this needs a plugin. **Whether a free one exists is
   the open question**, and per the original note, if there is none this moves to the "Hide cart UI" item
6. Merch / Products
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
          the same AGB pass as item 14. Taking money for goods not yet ordered is the part a
          non-profit should get right on paper.
7. Checkout end-to-end test — no real order flow tested yet
   (deferred — not selling products yet)
8. SEO — **the sitemap is fine and regenerating again.** Re-measured 2026-09-08: it exists at
   `https://sdwa5.org/sitemap.xml`, returns HTTP 200, is a valid `sitemapindex`, holds **32 URLs** covering the
   homepage, 13 CMS pages, 5 category listings and 13 products, and `robots.txt` advertises it **twice**, for the
   default and the `/de/` sales channel. Its `lastmod` was frozen at 2026-07-22 because
   `shopware.sitemap_generate` had stopped, and the worker now runs it again. **What is left is whether it has ever
   been submitted to Google Search Console**, which needs the account and cannot be answered from the host, plus the
   meta titles and descriptions, which were never measured
9. Switch store-installed plugins to composer install — FroshLazySizes, FroshPlatformFilterSearch, SwagPlatformSecurity,
   FroshShopmon are currently installed via the Shopware Store plugin manager and not in
   `composer.json`/`composer.lock` (unlike FroshPlatformThumbnailProcessor, FroshPlatformMailArchive). Their source is
   now tracked in git as a stopgap (see [infrastructure.md](../infrastructure.md)), but `composer require`
   would be the proper fix so `composer install` alone reproduces the install and updates go through Composer.
10. update mysql and php
11. frosh tools system-status
    1. System Health
    2. Performance recommendations
12. Hide cart UI when irrelevant — hide cart icon, minicart, and related shop chrome when cart is empty AND user is not
    on a PDP or category listing page. Reduces commercial appearance on content-only pages.
13. Content
    1. add images
    2. add "useful links" page
        1. grouped overview
        2. use everything useful from my firefox bookmarks
    3. Artists & Friends
        1. add links
        2. asked in SdWa5 Family Whatsapp group who wants to be featured -> wait for responses
14. Apply the legal-page wording fixes from the 2026-07-22 review before editing the live
    Datenschutz, AGB, Impressum and Widerrufsrecht CMS pages. **The review itself lives in Google
    Drive and deliberately not here**, decided 2026-09-13: it is a dated, itemised list of gaps on a
    live Austrian webshop written by its own operator, and in a public repository that is a ready-made
    checklist for anybody minded to send an Abmahnung. Its findings are therefore not restated in this
    file either. One of them is a characterization decision that needs the Obmann or the board rather
    than a wording patch, and that is the item this one waits on (`decision`)
