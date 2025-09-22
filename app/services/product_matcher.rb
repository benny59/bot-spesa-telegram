class ProductMatcher
  STOP_WORDS = %w[e il lo la gli le un una di da del dal al per con su nel nello sulla].freeze

  def self.normalize(s)
    return [] unless s
    str = s.to_s.downcase
    str = str.gsub(/[^\p{Alnum}\s]/u, ' ')
    tokens = str.split.map { |t| t.strip }.reject { |t| t.length < 2 || STOP_WORDS.include?(t) }
    tokens.uniq
  end

  # product: hash (OFF data) or String product name
  # items: array of hashes with at least :id and :text
  # returns { item: item_hash, score: float } or nil
  def self.match_against_items(product, items, threshold: 0.45)
    name = if product.is_a?(Hash)
             [product['name'], product['brand'], product['product_name'], product['brands']].compact.join(' ')
           else
             product.to_s
           end

    prod_tokens = normalize(name)
    return nil if prod_tokens.empty? || items.nil? || items.empty?

    best = nil
    items.each do |it|
      text = it[:text] || it['text'] || it[:description] || it['description'] || ''
      item_tokens = normalize(text)
      next if item_tokens.empty?
      inter = (prod_tokens & item_tokens).size
      score = inter.to_f / [prod_tokens.size, item_tokens.size].min
      if best.nil? || score > best[:score]
        best = { item: it, score: score, prod_tokens: prod_tokens, item_tokens: item_tokens }
      end
    end

    return nil if best.nil? || best[:score] < threshold
    best
  end
end