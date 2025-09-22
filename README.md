# Bot Spesa Telegram

## Overview
Bot Spesa Telegram is a Telegram bot designed to help users manage their grocery shopping by recognizing products through barcode scanning and providing detailed information about them. The bot integrates with the Open Food Facts API to fetch product characteristics and allows users to export this information in PDF format.

## Features
- **Barcode Scanning**: Use your phone camera to scan barcodes of grocery products.
- **Product Information**: Retrieve detailed product characteristics from the Open Food Facts database.
- **PDF Export**: Generate PDF documents containing product details for easy reference.
- **Configuration Management**: Store and manage bot configurations, including the Telegram token.

## Project Structure
```
bot-spesa-telegram
├── app
│   ├── bot_spesa.rb               # Main entry point for the Telegram bot
│   ├── start_config.rb            # Initial configuration setup
│   ├── handlers                    # Contains message and photo handlers
│   │   ├── message_handler.rb      # Logic for handling incoming messages
│   │   └── photo_handler.rb        # Logic for handling incoming photos
│   ├── services                    # Services for external interactions
│   │   ├── openfoodfacts_client.rb # Client for Open Food Facts API
│   │   ├── barcode_scanner.rb      # Logic for barcode scanning
│   │   └── pdf_exporter.rb         # PDF generation service
│   ├── models                      # Database models
│   │   ├── product.rb              # Product model
│   │   └── config.rb               # Configuration model
│   └── db                          # Database related files
│       ├── migrate                 # Migration files
│       │   └── 001_add_characteristics_to_products.rb # Migration for product characteristics
│       └── schema.rb               # Current database schema
├── config
│   └── database.yml                # Database configuration settings
├── lib
│   └── utilities.rb                # Utility functions
├── scripts
│   └── setup_db.rb                 # Database setup script
├── Gemfile                         # Ruby gem dependencies
├── Rakefile                        # Command line tasks
├── .env.example                    # Environment variable template
└── README.md                       # Project documentation
```

## Setup Instructions
1. **Clone the Repository**: 
   ```bash
   git clone <repository-url>
   cd bot-spesa-telegram
   ```

2. **Install Dependencies**: 
   Ensure you have Ruby installed, then run:
   ```bash
   bundle install
   ```

3. **Configure the Database**: 
   Edit `config/database.yml` to set your database connection details.

4. **Run Database Setup**: 
   Execute the setup script to create the database and run migrations:
   ```bash
   ruby scripts/setup_db.rb
   ```

5. **Configure the Bot**: 
   Run `app/start_config.rb` to set up the Telegram bot token and other configurations.

6. **Start the Bot**: 
   Launch the bot using:
   ```bash
   ruby app/bot_spesa.rb
   ```

## Usage
- Interact with the bot through Telegram by sending commands and scanning barcodes.
- Use the PDF export feature to save product information for later reference.

## Contributing
Contributions are welcome! Please submit a pull request or open an issue for any enhancements or bug fixes.

## License
This project is licensed under the MIT License. See the LICENSE file for details.