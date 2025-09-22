# Bot Spesa Telegram

Lightweight Telegram bot to manage shared shopping lists (spesa).  
This fork adds barcode scanning + OpenFoodFacts integration, product storage, nutrition facts and PDF export with a radar chart of aggregated nutrients.

---

## Quick overview

- Users send messages / photos to the bot to add items to shared lists.
- When a photo containing a barcode is uploaded, the bot:
  - downloads the image,
  - scans it (server-side) with `zbarimg` (CLI),
  - queries OpenFoodFacts for product characteristics and nutriments,
  - attempts to match the OFF product name with items in the current list,
  - prompts the user to confirm removal/mark-as-bought if a good match is found,
  - stores product characteristics and nutrition facts in the `products` table,
  - includes product details in generated PDFs.
- You can request a radar/web chart that aggregates nutrients bought so far with the command:
  - `/nutrients` or `/nutrition_stats`

---

## New files / services (added for barcode & nutrition)
- app/services/barcode_scanner.rb — scans images with `zbarimg`
- app/services/openfoodfacts_client.rb — queries OpenFoodFacts and extracts nutriments
- app/services/nutrition_chart.rb — generates radar (spider) charts (PNG) using Gruff
- app/models/product.rb — product persistence including nutrition fields
- scripts/add_nutrition_columns.rb — migration script to add nutrition columns to `products`
- handlers/message_handler.rb — integration: scan, save, match and /nutrients handler

---

## Prerequisites

- Ruby 2.7+ (recommended 3.x)
- Bundler
- SQLite3 (used by the app)
- `zbarimg` (zbar-tools) installed on the server (for barcode scanning)
- Telegram bot token

Notes:
- Charts are generated with ChunkyPNG (pure Ruby) — no ImageMagick / RMagick required.
- On Debian/Ubuntu: `sudo apt-get install zbar-tools sqlite3`

---

## Install dependencies

From repo root (PowerShell on Windows):

```powershell
cd "C:\Spesa\bot-spesa-telegram"
bundle install
```

Add this gem to your Gemfile if not present:
- chunky_png

Then `bundle install`.

---

## Database setup / migrations

1. Copy `.env.example` to `.env` and set your TELEGRAM token and settings.

2. Run main DB setup (creates SQLite DB and core tables):

```bash
ruby scripts/setup_db.rb
```

3. Add nutrition columns to `products` (safe, idempotent):

```bash
ruby scripts/add_nutrition_columns.rb
```

---

## Usage

- Send a photo containing a barcode to the bot (or upload a product photo). The bot scans the barcode, queries OpenFoodFacts and stores product data and nutrients in the DB.
- When an item is marked as bought and linked to a saved product, its nutrition values are associated and included in aggregates.
- Generate a radar chart of aggregated nutrients for a group:

  - In the group chat, send:
    /nutrients
    or
    /nutrition_stats

  The bot returns a PNG radar chart showing totals for Energy, Fat, SatFat, Carbs, Sugars, Proteins, Salt and Fiber.

---

## PDF export

PDF export now includes product characteristics and, when available, nutrition information. The radar chart generation is separate and triggered by the `/nutrients` command.

---

## Troubleshooting

- If barcode scanning fails, confirm `zbarimg` is installed and reachable from the bot process.
- If the chart generation fails, ensure ImageMagick is installed and the `rmagick` gem was built successfully.
- Check the bot log/output in the terminal to see warnings/errors from the barcode/OpenFoodFacts flow.

---

## Contributing

Contributions welcome. Suggested small changes:
- Normalize nutrient values per 100g / per serving
- Show averages instead of totals
- Add per-day or per-user nutrient breakdown

---

## License

This project is licensed under the MIT License. See the LICENSE file for details.

---

## Acknowledgements

- [OpenFoodFacts](https://world.openfoodfacts.org/) - product database API.
- [ZBar](http://zbar.sourceforge.net/) - barcode scanning.
- [ChunkyPNG](https://github.com/wvanbergen/chunky_png) - lightweight PNG generation.