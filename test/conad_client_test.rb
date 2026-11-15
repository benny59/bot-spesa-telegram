require_relative "../models/recipe_importer"

url = "https://spesaonline.conad.it/p/conad-acqua-minerale-naturale-6-x-15-l--400100"
raise "URL Conad non riconosciuto" unless RecipeImporter.supports?(url) && ConadClient.supports?(url)
raise "codice con suffisso non riconosciuto" unless ConadClient.supports?("https://spesaonline.conad.it/p/yogurt-greco-150-g--7270889-1_N")
["http://spesaonline.conad.it/p/x--1", "https://spesaonline.conad.it.evil.example/p/x--1", "https://evil.example/p/x--1",
 "https://spesaonline.conad.it/categoria/acqua", "https://spesaonline.conad.it/p/senza-codice"].each do |u|
  raise "accettato: #{u}" if ConadClient.supports?(u)
end

html = <<~HTML
  <html><head>
  <meta property="og:image" content="https://spesaonline.conad.it/assets/products/x/ID-Shot.jpeg/renditions/large.jpeg">
  <script type="application/ld+json">{"@type":"BreadcrumbList"}</script>
  <script type="application/ld+json">{"@type":"Product","name":"Acqua & Sapori 6 x 1,5 l Conad | Conad","gtin":"8003170016330","sku":"400100"}</script>
  </head></html>
HTML
r = ConadClient.normalize(html, url: url)
raise "Titolo errato: #{r[:title]}" unless r[:title] == "Acqua e Sapori 6 x 1,5 l Conad"
raise "GTIN errato" unless r[:gtin] == "8003170016330"
raise "Foto errata" unless r[:image_url].end_with?("large.jpeg")
raise "kind errato" unless r[:kind] == "product" && r[:source_url] == url

begin
  ConadClient.normalize("<html></html>", url: url)
  raise "pagina senza Product accettata"
rescue ConadClient::Error
end

[ "https://evil.example/x.jpg", "http://spesaonline.conad.it/x.jpg" ].each do |u|
  begin
    RecipeImporter.fetch_image(u)
    raise "immagine accettata: #{u}"
  rescue EbsnShopClient::Error
  end
end
raise "host Conad non instradato" unless ConadClient.image_host?("https://spesaonline.conad.it/a.jpg") && !EbsnShopClient.image_host?("https://spesaonline.conad.it/a.jpg")

puts "OK"
