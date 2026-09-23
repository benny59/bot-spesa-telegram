require_relative "giallo_zafferano_client"
require_relative "monsieur_cuisine_client"

class RecipeImporter
  PROVIDERS = [MonsieurCuisineClient, GialloZafferanoClient].freeze

  class Error < StandardError; end

  def self.supports?(url)
    PROVIDERS.any? { |provider| provider.supports?(url) }
  end

  def self.preview(url)
    provider = PROVIDERS.find { |candidate| candidate.supports?(url) }
    raise Error, "Sito di ricette non supportato" unless provider

    provider.preview(url)
  rescue MonsieurCuisineClient::Error, GialloZafferanoClient::Error => e
    raise Error, e.message
  end
end