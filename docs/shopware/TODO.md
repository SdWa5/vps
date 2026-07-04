# Shopware TODO

1. Cookie consent
    1. SoundCloud embed — register cookie entry in "Comfort features" group + gate iframe behind consent
    2. `cookie.messageTextPage` (the main consent banner text) still renders its link as `/page/cms/Array` —
       confirmed live 2026-07-03, not just a stale-cache issue. `cookie.descriptionInfo` (a separate, secondary
       snippet — not the main banner) was fixed and confirmed pointing at the current Datenschutz URL.
2. update email templates (order confirmation etc. still default Shopware copy)
    1. dont get too fancy (e.g. with corporate or blogging style expressions)
    2. en and de
3. Search: include CMS pages — storefront search currently returns only products. Extend to also surface CMS
   pages, ideally as primary/first results (sdwa5.org primarily used as homepage, online shop secondary functionality).
   If this todo isnt solvable using built-in Shopware features or free plugins, move this todo to the "Hide cart UI"
   todo
4. Merch / Products
    1. Make use of variants and other product related shopware features
    2. Add missing product images, remove background / opacity from existing images
    3. Non-binding preorders / interest capture — no native Shopware 6 core feature for this.
       `GET /api/product-notification` → 404 confirms. Options:
        - Contact form (zero effort): link from product/category pages to /Requests-Contact/ — captures
          interest via email, fully manual
        - Plugin (paid): back-in-stock / waitlist plugins on Shopware marketplace (e.g. ACRIS stock
          notification) — adds "notify me" button on out-of-stock products, admin sees subscriber list
5. Checkout end-to-end test — no real order flow tested yet
6. SEO — meta titles/descriptions empty on all pages, no sitemap submitted
7. Switch store-installed plugins to composer install — FroshLazySizes, FroshPlatformFilterSearch,
   SwagPlatformSecurity, FroshShopmon are currently installed via the Shopware Store plugin manager and not in
   `composer.json`/`composer.lock` (unlike FroshPlatformThumbnailProcessor, FroshPlatformMailArchive). Their
   source is now tracked in git as a stopgap (see [infrastructure.md](../infrastructure.md)), but `composer require`
   would be the proper fix so `composer install` alone reproduces the install and updates go through Composer.
8. update mysql and php
9. frosh tools system-status
    1. System Health
    2. Performance recommendations
10. Hide cart UI when irrelevant — hide cart icon, minicart, and related shop chrome when cart is empty AND user
    is not on a PDP or category listing page. Reduces commercial appearance on content-only pages.
11. Privacy + ToS pages — legal text review by Austrian lawyer (DSGVO, AGB)
12. Content
    1. add images
    2. add "useful links" page
        1. grouped overview
        2. use everything useful from my firefox bookmarks
    3. Artists & Friends
        1. add links
        2. asked in SdWa5 Family Whatsapp group who wants to be featured -> wait for responses
