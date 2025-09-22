source "https://rubygems.org"

gem "sqlite3"
gem "telegram-bot-ruby"
gem "httparty"
gem "prawn"  # For PDF generation
# rmagick removed to reduce footprint on small servers; use zbar CLI instead
gem "barby"   # For barcode generation and recognition
gem "barby-barcode" # Barcode formats
gem "openfoodfacts-api" # For interacting with Open Food Facts API

group :development do
  gem "pry"  # For debugging
end

group :test do
  gem "rspec"  # For testing
  gem "factory_bot"  # For test data generation
end