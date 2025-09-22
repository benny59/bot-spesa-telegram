source "https://rubygems.org"

gem "sqlite3"
gem "telegram-bot-ruby"
gem "httparty"
gem "prawn"  # For PDF generation
# rmagick removed to reduce footprint on small servers; use zbar CLI instead
gem "barby"   # For barcode generation and recognition
gem "barby-barcode" # Barcode formats
gem "openfoodfacts-api" # For interacting with Open Food Facts API
gem 'gruff'        # for radar/spider charts (requires rmagick)
gem 'rmagick'      # image backend for gruff
# optional: helper gem for OpenFoodFacts if you prefer
# gem 'openfoodfacts'

group :development do
  gem "pry"  # For debugging
  gem 'rubocop', require: false
end

group :test do
  gem "rspec"  # For testing
  gem "factory_bot"  # For test data generation
  gem 'webmock'
end