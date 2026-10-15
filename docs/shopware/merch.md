# Merch catalog (currently shown as: "no longer available")

Prices: selling price = €0 (voluntary donation), list price = suggested donation, purchase price = Stückkosten,
shown as the production cost estimate

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
| SdWa5 Top Model 1:12                 | €1,75          | €5,00      |
| SKRAM Model 1:12                     | €2,77          | €8,00      |
| SdWa5 Rig Model Set 1:12             | €19,10         | €45,00     |

Product numbers: SDWA5-* · Images added

The two print models (`SDWA5-MT-001`, `SDWA5-MS-001`) went online on 2026-10-15. The top can be ordered
since that day, printed to order with pick-up only; the SKRAM and the rig set wait on Josh Ricci's answer. Their purchase prices are
estimates from slicing the repo models in OrcaSlicer 2.4.2 for Sepp's Anycubic Kobra 3 Max (0.20 mm layers, 15 %
infill, 33 g and 1 h 36 min for the top, 56 g and 2 h 18 min for the SKRAM). They count PLA at €26.90/kg, 300 W at
€0.34/kWh and wear of €999 over 3000 hours, plus 10 % for failed prints. Labour is not included. The scale of
1:12 was measured from Sepp's photo against a cigarette pack of known size.

## Donation display

The storefront shows a product at €0 with a list price as a voluntary donation, with the list price as the
suggested donation and the purchase price as the production cost estimate. The cart, the confirm page and
the order confirmation mail add the suggested total. [theme.md](theme.md#merch-as-a-donation) lists the
templates. The Store API does not return purchase prices, so the storefront reads them from the custom field
`sdwa5_production_cost` of the set `sdwa5_merch`. The purchase price in the admin stays the only source.
`create-products.sh` fills the field for a new product, and `sync-production-cost.sh` copies it after a
purchase price changed.

## Tools

The three steps behind the print models are scripted under `tools/shopware/`, so the next product follows the
same path.

```bash
# Grams, print time and cost per piece. Defaults are the figures above, each overridable by environment
# (FILAMENT_EUR_KG, POWER_W, EUR_KWH, PRINTER_EUR, PRINTER_HOURS, FAILURE).
tools/shopware/print-cost/print-cost.sh tecnare-1to12.stl skram-1to12.stl

# Shop images. A jobs file holds one `shot` line per photo with its crop, erase boxes and perspective quad.
# `corners` writes grid zooms for reading a quad off a photo.
tools/shopware/images/shop-images.sh run tools/shopware/images/print-models.jobs PHOTO_DIR OUT_DIR
tools/shopware/images/shop-images.sh corners PHOTO.jpg zoom.jpg "0.36,0.18 0.62,0.17"

# Products from a data file, dry run first. The file holds the shop ids, prices, texts and image paths.
tools/shopware/create-products.sh tools/shopware/products/print-models.json
tools/shopware/create-products.sh tools/shopware/products/print-models.json --apply

# Existing products get their images in the order the data file lists them, the first as cover.
tools/shopware/create-products.sh tools/shopware/products/print-models.json --sync-media --apply

# Copy every purchase price into the production cost field the storefront shows.
tools/shopware/sync-production-cost.sh
tools/shopware/sync-production-cost.sh --apply
```

`print-cost.sh` builds an OrcaSlicer 2.4.2 image whose AppImage is pinned by checksum, and flattens the
Anycubic system profiles inside the image, so no slicer profile is stored in this repository. `shop-images.sh`
removes the background with rembg and BiRefNet and caches the model in `~/.cache/sdwa5-rembg`. The originals
of the photos are not in the repository. Only the finished images in `tools/shopware/products/media/` are.
