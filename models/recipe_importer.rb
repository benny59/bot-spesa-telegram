require_relative "giallo_zafferano_client"
require_relative "monsieur_cuisine_client"
require_relative "ebsn_shop_client"
require_relative "conad_client"
require_relative "guacci_client"

class RecipeImporter
  PROVIDERS = [MonsieurCuisineClient, GialloZafferanoClient, EbsnShopClient, ConadClient, GuacciClient].freeze
  SHOP_PROVIDERS = [EbsnShopClient, ConadClient, GuacciClient].freeze

  class Error < StandardError; end

  def self.supports?(url)
    PROVIDERS.any? { |provider| provider.supports?(url) }
  end

  # Foto di un prodotto: scaricata solo dal negozio a cui appartiene l'URL
  def self.fetch_image(url)
    provider = SHOP_PROVIDERS.find { |candidate| candidate.image_host?(url) }
    raise EbsnShopClient::Error, "Immagine non valida" unless provider

    provider.fetch_image(url)
  end

  def self.preview(url)
    provider = PROVIDERS.find { |candidate| candidate.supports?(url) }
    raise Error, "Sito di ricette non supportato" unless provider

    provider.preview(url)
  rescue MonsieurCuisineClient::Error, GialloZafferanoClient::Error, EbsnShopClient::Error => e # ConadClient e GuacciClient::Error sono lo stesso di EbsnShopClient
    raise Error, e.message
  end
end