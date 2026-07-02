# 4.0.11

- Fixed the [GHSA-gq96-5pfx-f4vc](https://github.com/shopware/shopware/security/advisories/GHSA-gq96-5pfx-f4vc) fix on Shopware versions prior to 6.7.9.0. The core `MediaUploadService` constructor only gained the thumbnail repository arguments in 6.7.9.0, so on older versions the patched service received the `FileUrlValidator` in the wrong position (`Argument #6 ($thumbnailRepository) must be of type EntityRepository, FileUrlValidator given`) and every media upload failed with HTTP 500. The patched service now forwards the original core arguments verbatim, staying compatible across the whole affected range (6.7.0.0 – 6.7.10.0).

# 4.0.10

- Added fix for [GHSA-f8q6-3g5w-jjr6](https://github.com/shopware/shopware/security/advisories/GHSA-f8q6-3g5w-jjr6)
- Added fix for [GHSA-9v5m-39wh-5chq](https://github.com/shopware/shopware/security/advisories/GHSA-9v5m-39wh-5chq) (payment processing without customer check). The HandlePaymentMethod route is now decorated to verify the order belongs to the current customer before processing payment.
- Added fix for [GHSA-xvhc-gm7j-mhmc](https://github.com/shopware/shopware/security/advisories/GHSA-xvhc-gm7j-mhmc). Expanded the default SVG allowlist to cover the W3C SVG2 presentation attribute set, ARIA accessibility attributes, `lang`/`xml:lang`, and the structural elements `a`, `image`, `marker`, `metadata`, `switch`, `symbol`, and `view`. All value-level security checks (external `url(...)` rejection, `@import` block, event-handler rejection, fragment-only reference enforcement, foreign-namespace rejection, `LIBXML_NONET`) remain unchanged.
- Added fix for [GHSA-gq96-5pfx-f4vc](https://github.com/shopware/shopware/security/advisories/GHSA-gq96-5pfx-f4vc)
- Added fix for [GHSA-7w52-7jvm-m9vw](https://github.com/shopware/shopware/security/advisories/GHSA-7w52-7jvm-m9vw)
- Added fix for [GHSA-8v9p-g828-v98f](https://github.com/shopware/shopware/security/advisories/GHSA-8v9p-g828-v98f)
- Added fix for [GHSA-gv8p-48fr-4fxg](https://github.com/shopware/shopware/security/advisories/GHSA-gv8p-48fr-4fxg)
- Added fix for [GHSA-v39m-97p8-gqg7](https://github.com/shopware/shopware/security/advisories/GHSA-v39m-97p8-gqg7)
- Added fix for [GHSA-4x3x-869w-xx3m](https://github.com/shopware/shopware/security/advisories/GHSA-4x3x-869w-xx3m)

# 4.0.9

- Fixed compatibility with older commercial version for fix [GHSA-gqc5-xv7m-gcjq](https://github.com/shopware/shopware/security/advisories/GHSA-gqc5-xv7m-gcjq)

# 4.0.8

- Fixed compatibility with older commercial version for fix [GHSA-7vvp-j573-5584](https://github.com/shopware/shopware/security/advisories/GHSA-7vvp-j573-5584)

# 4.0.7

- Added fix for [GHSA-c4p7-rwrg-pf6p](https://github.com/shopware/shopware/security/advisories/GHSA-c4p7-rwrg-pf6p)

Introduces a secure, asynchronous app secret rotation feature to the app system, including both API and CLI interfaces.
Added a new API endpoint and command for rotating app secrets, implemented the underlying rotation logic, and adjusted the app registration process to support secret updates and dual signature confirmation.
This increases security by enforcing a two-step verification process during app re-registration, ensuring that only authorized parties can update app secrets.

- Added fix for [GHSA-gqc5-xv7m-gcjq](https://github.com/shopware/shopware/security/advisories/GHSA-gqc5-xv7m-gcjq)
- Added fix for [GHSA-7vvp-j573-5584](https://github.com/shopware/shopware/security/advisories/GHSA-7vvp-j573-5584)
- Added fix for [GHSA-64rg-pgjv-4v33](https://github.com/shopware/shopware/security/advisories/GHSA-64rg-pgjv-4v33)

# 4.0.6

- Added fix for [GHSA-7cw6-7h3h-v8pf](https://github.com/shopware/shopware/security/advisories/GHSA-7cw6-7h3h-v8pf)

# 4.0.5

- Added fix for [GHSA-6w82-v552-wjw2](https://github.com/shopware/shopware/security/advisories/GHSA-6w82-v552-wjw2)

# 4.0.4

- Added fix for [GHSA-2w46-vq8h-98vh](https://github.com/shopware/shopware/security/advisories/GHSA-2w46-vq8h-98vh)

# 4.0.3

- Fixed compatibility with CMS Extensions plugin

# 4.0.2

- Added fix for [GHSA-6wh5-mw9h-5c3w](https://github.com/shopware/shopware/security/advisories/GHSA-6wh5-mw9h-5c3w)
- Added fix for [GHSA-r2vg-hvjm-fg38](jhttps://github.com/shopware/shopware/security/advisories/GHSA-r2vg-hvjm-fg38)
- Added fix for [GHSA-27c9-vp3w-6ww8](jhttps://github.com/shopware/shopware/security/advisories/GHSA-27c9-vp3w-6ww8)
- Added fix for [GHSA-3cpp-fv95-mpr5](https://github.com/shopware/shopware/security/advisories/GHSA-3cpp-fv95-mpr5)

# 4.0.1

- Fixed compatibility for shopware versions <6.7.2.0

# 4.0.0

- Compatibility with Shopware 6.7
- Added fix for [GHSA-9v82-vcjx-m76](https://github.com/shopware/shopware/security/advisories/GHSA-9v82-vcjx-m76j)

# 3.0.8

- Added fix for NEXT-39918
- Added fix for NEXT-40390
- Improved fix for NEXT-37397

# 3.0.7

- Improve fix NEXT-37397

# 3.0.6

- Improved the NEXT-37527 to fix performance issues

# 3.0.5

- Fixed JavaScript errors occurring in the administration

# 3.0.4

- Added fixes for NEXT-37399
- Added fixes for NEXT-37398
- Added fixes for NEXT-37397

# 3.0.3

- Added search term max length configuration

# 3.0.2

- Fixed disabling security fixes in the Administration

# 3.0.1

- Fixed cart restoring on account login after previous account logout

# 3.0.0

- Shopware 6.6 compatibility
- Symfony 7 compatibility
- Added fixes for NEXT-34608

# 2.0.1

- Added fixes for NEXT-23915

# 2.0.0

- Shopware 6.5 compatibility

# 1.0.22

- Added fixes for NEXT-23325

# 1.0.21

- Added fixes for PPI-737

# 1.0.20

- Added fixes for NEXT-24679
- Added fixes for NEXT-24677
- Added fixes for NEXT-24667
- Added fixes for NEXT-23325
- Added fixes for NEXT-22891

# 1.0.19

- Bugfix for NEXT-23562 for 6.3.1.x

# 1.0.18

- Added fixes for NEXT-23562

# 1.0.17

- Added fixes for NEXT-23464

# 1.0.16

- Added fixes for NEXT-21077
- Added fixes for NEXT-21078
- Added fixes for NEXT-21034

- # 1.0.15

- Added fixes for NEXT-20305
- Added fixes for NEXT-20307

# 1.0.14

- Added fixes for NEXT-19276
- Added fixes for NEXT-19820

# 1.0.13

- Added fixes for NEXT-17527

# 1.0.12

- Added fixes for NEXT-16429
- Added fixes for NEXT-15681
- Added fixes for NEXT-15677
- Added fixes for NEXT-15675
- Added fixes for NEXT-15673
- Added fixes for NEXT-15671
- Added fixes for NEXT-15669

# 1.0.11
- Added fixes for NEXT-15858
-
- # 1.0.10
- Added fixes for NEXT-15183
- Added fixes for NEXT-14871
- Added fixes for NEXT-14883
- Added fixes for NEXT-14744

# 1.0.9

- Bugfix for NEXT-14923 Customers cannot login before v6.3.3.0

# 1.0.8

- Fixed problems with the .htaccess

# 1.0.7
- Added fixes for NEXT-14533
- Added fixes for NEXT-14482
- Added fixes for NEXT-14188

# 1.0.6
- Added fixes for NEXT-13664
- Added fixes for NEXT-13896

# 1.0.5
- Added fixes for NEXT-12824
- Bugfix for NEXT-13671 Customers cannot login in v6.3.3.1
- Bugfix for NEXT-13657 Documents cannot be downloaded
- Bugfix for NEXT-13451 Plugin manager login doesn't work

# 1.0.4
- Added fixes for NEXT-13371
- Added fixes for NEXT-13247

# 1.0.3
- Added fixes for NEXT-12230
- Added fixes for NEXT-9689

# 1.0.2
- Added fixes for NEXT-10909
- Added fixes for NEXT-10905

# 1.0.1
- Added fixes for NEXT-10624

# 1.0.0
- Initial release of the plugin for Shopware 6
