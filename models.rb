#!/usr/bin/env ruby
# models.rb
require_relative 'db'

class GroupManager

def self.salva_nome_utente(user_id, first_name, last_name = nil)
  DB.execute("INSERT OR REPLACE INTO user_names (user_id, first_name, last_name) VALUES (?, ?, ?)", 
            [user_id, first_name, last_name])
end


  def self.crea_gruppo(bot, user_id, user_name)
    DB.execute("INSERT INTO gruppi (nome, creato_da) VALUES (?, ?)", ["Lista Spesa di #{user_name}", user_id])
    gruppo_id = DB.last_insert_row_id
    DB.execute("INSERT INTO membri_gruppi (user_id, gruppo_id, is_admin) VALUES (?, ?, ?)", [user_id, gruppo_id, 1])
    bot_username = bot.api.get_me.username
    { success: true, gruppo_id: gruppo_id, invite_link: "https://t.me/#{bot_username}?startgroup=true" }
  rescue => e
    puts "❌ Errore creazione gruppo: #{e.message}"
    { success: false, error: e.message }
  end

  def self.associa_gruppo_automaticamente(bot, chat_id, user_id)
    gruppo = DB.get_first_row("SELECT * FROM gruppi WHERE chat_id IS NULL AND creato_da = ? ORDER BY id DESC LIMIT 1", [user_id])
    if gruppo
      DB.execute("UPDATE gruppi SET chat_id = ? WHERE id = ?", [chat_id, gruppo['id']])
      DB.execute("INSERT OR IGNORE INTO membri_gruppi (user_id, gruppo_id, is_admin) VALUES (?, ?, ?)", [user_id, gruppo['id'], 1])
      bot.api.send_message(chat_id: chat_id, text: "🎉 Gruppo associato (ID: #{gruppo['id']})")
      { success: true, gruppo_id: gruppo['id'] }
    else
      bot.api.send_message(chat_id: chat_id, text: "❌ Nessun gruppo virtuale trovato, usa /newgroup in privato")
      { success: false }
    end
  end

  def self.get_gruppo_by_chat_id(chat_id)
    DB.get_first_row("SELECT * FROM gruppi WHERE chat_id = ?", [chat_id])
  end

  def self.get_gruppo_by_id(gruppo_id)
    DB.get_first_row("SELECT * FROM gruppi WHERE id = ?", [gruppo_id])
  end

  def self.is_user_admin(user_id, gruppo_id)
    DB.get_first_value("SELECT is_admin FROM membri_gruppi WHERE user_id = ? AND gruppo_id = ?", [user_id, gruppo_id]).to_i == 1
  end
end

class Lista
  def self.aggiungi(gruppo_id, user_id, testo)
    testo.split(',').map(&:strip).reject(&:empty?).each do |nome|
      DB.execute("INSERT INTO items (nome, gruppo_id, creato_da) VALUES (?, ?, ?)", [nome, gruppo_id, user_id])
    end
  end

def self.trova(item_id)
  DB.get_first_row("SELECT * FROM items WHERE id = ?", [item_id])
end


def self.tutti(gruppo_id)
  items = DB.execute("SELECT i.* FROM items i WHERE i.gruppo_id = ? ORDER BY i.comprato, i.nome", [gruppo_id])
  
  # Prima passata: raccogli tutti gli user_id e genera iniziali di base
  user_initials_map = {}
  user_count = {}
  
  items.each do |item|
    user_id = item['creato_da']
    next unless user_id
    
    if !user_initials_map[user_id]
      user_name = DB.get_first_value("SELECT first_name, last_name FROM user_names WHERE user_id = ?", [user_id])
      
      if user_name
        name_parts = user_name.split
        base_initials = if name_parts.size >= 2
                          "#{name_parts[0][0]}#{name_parts[1][0]}".upcase
                        else
                          name_parts[0][0..1].upcase.ljust(2, '?')
                        end
        user_initials_map[user_id] = base_initials
      else
        user_initials_map[user_id] = "??"
      end
    end
  end
  
  # Seconda passata: risolvi conflitti e assegna iniziali uniche
  final_initials = {}
  used_initials = {}
  
  user_initials_map.each do |user_id, base_initials|
    if !used_initials[base_initials]
      final_initials[user_id] = base_initials
      used_initials[base_initials] = true
    else
      # Trova una variante unica
      counter = 1
      unique_initials = base_initials
      while used_initials[unique_initials]
        counter += 1
        unique_initials = "#{base_initials[0]}#{counter}"
      end
      final_initials[user_id] = unique_initials
      used_initials[unique_initials] = true
    end
  end
  
  # Terza passata: applica le iniziali agli items
  items.map do |item|
    user_id = item['creato_da']
    initials = user_id ? final_initials[user_id] : '??'
    item.merge('user_initials' => initials)
  end
end


  def self.cancella(gruppo_id, item_id, user_id)
    item = DB.get_first_row("SELECT comprato, creato_da FROM items WHERE id = ? AND gruppo_id = ?", [item_id, gruppo_id])
    return false unless item
    if item['comprato'] == 1 || item['creato_da'] == user_id || GroupManager.is_user_admin(user_id, gruppo_id)
      DB.execute("DELETE FROM items WHERE id = ? AND gruppo_id = ?", [item_id, gruppo_id])
      true
    else
      false
    end
  end

  def self.toggle_comprato(gruppo_id, item_id, user_id)
    item = DB.get_first_row("SELECT comprato FROM items WHERE id = ? AND gruppo_id = ?", [item_id, gruppo_id])
    return nil unless item
    nuovo = item['comprato'] == 1 ? 0 : 1
    DB.execute("UPDATE items SET comprato = ? WHERE id = ? AND gruppo_id = ?", [nuovo, item_id, gruppo_id])
    nuovo
  end

  def self.cancella_tutti(gruppo_id, user_id)
    if GroupManager.is_user_admin(user_id, gruppo_id)
      DB.execute("DELETE FROM items WHERE gruppo_id = ? AND comprato = 1", [gruppo_id])
      true
    else
      false
    end
  end
end
