require 'httparty'
require 'logger'
require 'timeout'
require 'json'
require 'net/http'
require 'uri'

module OpenFoodFactsClientHelper
  OFF_BASE = 'https://world.openfoodfacts.org'

  # returns nil or a hash with nutrient values (per 100g) and product name
  def self.fetch_by_barcode(barcode)
    uri = URI("#{OFF_BASE}/api/v0/product/#{URI.encode_www_form_component(barcode)}.json")
    res = Net::HTTP.get_response(uri)
    return nil unless res.is_a?(Net::HTTPSuccess)

    payload = JSON.parse(res.body)
    return nil unless payload['status'] == 1 && payload['product']

    p = payload['product']
    nutriments = p['nutriments'] || {}

    {
      name: p['product_name'] || p['product_name_en'] || p['brands'],
      energy_kcal: (nutriments['energy-kcal_100g'] || nutriments['energy_100g'] || nutriments['energy-kcal'] || nutriments['energy-kcal_100g']).to_f,
      fat_g: (nutriments['fat_100g'] || 0).to_f,
      saturated_fat_g: (nutriments['saturated-fat_100g'] || nutriments['saturated_fat_100g'] || 0).to_f,
      carbohydrates_g: (nutriments['carbohydrates_100g'] || 0).to_f,
      sugars_g: (nutriments['sugars_100g'] || 0).to_f,
      proteins_g: (nutriments['proteins_100g'] || 0).to_f,
      salt_g: (nutriments['salt_100g'] || 0).to_f,
      fiber_g: (nutriments['fiber_100g'] || 0).to_f
    }
  rescue => e
    warn "OFF request failed: #{e}"
    nil
  end
end

class OpenFoodFactsClient
  BASE_URL = ENV.fetch('OPENFOODFACTS_BASE', 'https://world.openfoodfacts.org/api/v0/product/')
  TIMEOUT = (ENV['OPENFOODFACTS_TIMEOUT'] || 5).to_i
  RETRIES = (ENV['OPENFOODFACTS_RETRIES'] || 2).to_i
  USER_AGENT = "bot-spesa-telegram/1.0"

  @logger = Logger.new($stdout)
  @cache = {} # simple in-memory cache: { barcode => [result_hash, timestamp] }
  CACHE_TTL = (ENV['OFF_CACHE_TTL'] || 3600).to_i

  class << self
    # Returns a Hash with keys:
    #  :ok (true/false), :barcode, :data (parsed characteristics) or :error
    def fetch_product_info(barcode)
      barcode = normalize_barcode(barcode)
      return { ok: false, error: 'invalid_barcode' } unless valid_barcode?(barcode)

      cached = read_cache(barcode)
      return { ok: true, barcode: barcode, data: cached } if cached

      url = "#{BASE_URL}#{barcode}.json"
      attempts = 0
      begin
        attempts += 1
        resp = nil
        Timeout.timeout(TIMEOUT) do
          resp = HTTParty.get(url, headers: { 'User-Agent' => USER_AGENT, 'Accept' => 'application/json' })
        end

        unless resp && resp.code == 200
          code = resp&.code || 'no_response'
          @logger.warn("OpenFoodFacts: non-200 (#{code}) for #{barcode}")
          return { ok: false, barcode: barcode, error: "http_#{code}" }
        end

        body = resp.parsed_response || {}
        product = body['product']
        return { ok: false, barcode: barcode, error: 'not_found' } unless product.is_a?(Hash)

        parsed = parse_product_data(product)
        write_cache(barcode, parsed)
        { ok: true, barcode: barcode, data: parsed }
      rescue Timeout::Error, Errno::ETIMEDOUT => e
        @logger.warn("OpenFoodFacts timeout: #{e.message}")
        retry if attempts <= RETRIES
        { ok: false, barcode: barcode, error: 'timeout' }
      rescue SocketError => e
        @logger.warn("Network error: #{e.message}")
        { ok: false, barcode: barcode, error: 'network' }
      rescue => e
        @logger.error("OpenFoodFacts unexpected error: #{e.class}: #{e.message}")
        { ok: false, barcode: barcode, error: 'internal' }
      end
    end

    def parse_product_data(product_data)
      {
        barcode: product_data['code'],
        name: (product_data['product_name'] || product_data['generic_name'] || 'N/A'),
        brand: product_data['brands'] || 'N/A',
        quantity: product_data['quantity'] || 'N/A',
        ingredients: product_data['ingredients_text'] || 'N/A',
        nutriments: (product_data['nutriments'] || {}),
        raw: product_data # include raw payload for advanced use / debugging
      }
    end

    private

    def valid_barcode?(b)
      s = b.to_s.strip
      # Accept 8, 12, 13 digits and simple numeric check; checksum can be added if desired.
      !!(s =~ /\A\d{8,13}\z/)
    end

    def normalize_barcode(b)
      b.to_s.strip
    end

    def read_cache(barcode)
      entry = @cache[barcode]
      return nil unless entry
      value, ts = entry
      return nil if (Time.now - ts) > CACHE_TTL
      value
    end

    def write_cache(barcode, value)
      @cache[barcode] = [value, Time.now]
    end
  end
end
