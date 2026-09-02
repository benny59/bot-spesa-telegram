require "tmpdir"

Dir.mktmpdir do |dir|
  Dir.chdir(dir) do
    require File.expand_path("../db", __dir__)

    user_id = 1
    group_id = DB.execute(
      "INSERT INTO gruppi (nome, chat_id) VALUES (?, ?)",
      ["Test", -1001]
    ).then { DB.last_insert_row_id }

    # Bug reale: "A, B, C & categoria" deve assegnare la categoria a TUTTI gli item,
    # non solo all'ultimo segmento dove il parser trova per primo il carattere "&".
    ids = DataManager.aggiungi_articoli(
      gruppo_id: group_id,
      user_id: user_id,
      items_text: "2 prese premontate,1 premontata da esterno, 2 spine luce & cipir"
    )
    raise "Attesi 3 item creati, trovati #{ids.size}" unless ids.size == 3

    items = ids.map { |id| DB.get_first_row("SELECT nome, categoria_id FROM items WHERE id = ?", [id]) }
    items.each do |item|
      parsed = DataManager.parse_nome_categoria(item["nome"], item["categoria_id"], item["categoria_id"], group_id, 0)
      raise "Categoria mancante per '#{item["nome"]}'" if parsed[:categoria_nome].to_s.strip.empty?
      raise "Categoria errata per '#{item["nome"]}': #{parsed[:categoria_nome].inspect}" unless parsed[:categoria_nome].to_s.downcase == "cipir"
    end

    # Le categorie esplicite per singolo item restano indipendenti (nessuna distribuzione forzata).
    ids_espliciti = DataManager.aggiungi_articoli(
      gruppo_id: group_id,
      user_id: user_id,
      items_text: "Pane & Panetteria, Latte & Latticini"
    )
    nomi_categorie = ids_espliciti.map do |id|
      item = DB.get_first_row("SELECT nome, categoria_id FROM items WHERE id = ?", [id])
      DataManager.parse_nome_categoria(item["nome"], item["categoria_id"], item["categoria_id"], group_id, 0)[:categoria_nome].to_s
    end
    raise "Categorie esplicite per-item alterate: #{nomi_categorie.inspect}" unless nomi_categorie.map(&:downcase).sort == ["latticini", "panetteria"]

    # Nessuna distribuzione quando il segmento con "&" non è l'ultimo (comportamento invariato).
    ids_non_trailing = DataManager.aggiungi_articoli(
      gruppo_id: group_id,
      user_id: user_id,
      items_text: "Chiodi & Ferramenta, Viti, Bulloni"
    )
    item_viti = DB.get_first_row("SELECT nome, categoria_id FROM items WHERE id = ?", [ids_non_trailing[1]])
    parsed_viti = DataManager.parse_nome_categoria(item_viti["nome"], item_viti["categoria_id"], item_viti["categoria_id"], group_id, 0)
    raise "Viti non doveva ricevere categoria" unless parsed_viti[:categoria_nome].to_s.strip.empty?

    # "modifica item" (singolo, senza split) non è mai interessato dallo split per virgola:
    # deve continuare a funzionare item per item, senza alcuna distribuzione.
    parsed_singolo = DataManager.parse_nome_categoria("Detersivo & pulizia", nil, nil, group_id, 0)
    raise "Modifica item singolo alterata" unless parsed_singolo[:categoria_nome].to_s.downcase == "pulizia"

    puts "Distribuzione categoria condivisa su item multipli coerente (nuovo item e modifica item)."
  end
end
