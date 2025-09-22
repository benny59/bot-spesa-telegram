# Bot Spesa Telegram

Lightweight Telegram bot to manage shared shopping lists (spesa).  
This fork adds barcode scanning + OpenFoodFacts integration, product storage and PDF export.

--- 

## Quick overview

- Users send messages / photos to the bot to add items to shared lists.
- When a photo containing a barcode is uploaded, the bot:
  - downloads the image,
  - scans it (server-side) with `zbarimg` (CLI),
  - queries OpenFoodFacts for product characteristics,
  - attempts to match the OFF product name with items in the current list,
  - prompts the user to confirm removal/mark-as-bought if a good match is found,
  - stores product characteristics in the `products` table,
  - includes product details in generated PDFs.

---

## Prerequisites

- Ruby 2.7+ (recommended 3.x)
- Bundler
- SQLite3 (used by the app)
- `zbarimg` (zbar-tools) installed on the server (see below)
- Telegram bot token

---

## Install dependencies

From repo root (PowerShell on Windows):

```powershell
cd "C:\Spesa\bot-spesa-telegram-1"
bundle install
```

From repo root (Linux / macOS):

```bash
cd "/path/to/bot-spesa-telegram"
bundle install
```

---

## Setup

1. **Copy `.env.example` to `.env`** and edit it to configure your Telegram bot token and other settings.

2. **Run database setup** (creates SQLite DB file and runs migrations):

   ```bash
   ruby scripts/setup_db.rb
   ```

3. **Start the bot**:

   ```bash
   ruby app/bot_spesa.rb
   ```

---

## Usage

- Interact with the bot through Telegram by sending commands and scanning barcodes.
- Use the PDF export feature to save product information for later reference.

---

## Contributing

Contributions are welcome! Please submit a pull request or open an issue for any enhancements or bug fixes.

---

## License

This project is licensed under the MIT License. See the LICENSE file for details.

---

## Acknowledgements

- [OpenFoodFacts](https://world.openfoodfacts.org/) - For the product database API.
- [ZBar](http://zbar.sourceforge.net/) - For the barcode scanning library.