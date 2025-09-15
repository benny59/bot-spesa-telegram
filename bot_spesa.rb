#!/usr/bin/env ruby
# bot_spesa.rb
require 'telegram/bot'
require_relative 'db'
require_relative 'models'

# recupera token dal DB (config key/value)
token = DB.get_first_value("SELECT value FROM config WHERE key = 'token'")

if token.nil? || token.to_s.strip.empty?
  puts "⚙️ Inserisci il token nella tabella config: ruby config_tool.rb token 123456:ABC..."
  exit 1
end

# Metodo spostato FUORI dal blocco Telegram::Bot::Client.run
def genera_lista(bot, chat_id, gruppo_id, user_id, message_id = nil)
  items = Lista.tutti(gruppo_id)
  buttons = []

  if items.empty?
    text = "📝 *La lista della spesa è vuota!*"
  else
    text = "📝 *Lista della spesa:*"
    items.each do |item|
      item_text = item['comprato'] == 1 ? "~~#{item['nome']}~~" : item['nome']
      emoji = item['comprato'] == 1 ? "✅" : "🛒"
      user_badge = item['user_initials'] ? "#{item['user_initials']}-" : "??-"
      
      buttons << [
        Telegram::Bot::Types::InlineKeyboardButton.new(text: "#{emoji} #{user_badge}#{item_text}", callback_data: "comprato:#{item['id']}:#{gruppo_id}"),
        Telegram::Bot::Types::InlineKeyboardButton.new(text: "❌", callback_data: "cancella:#{item['id']}:#{gruppo_id}")
      ]
    end
  end

  # pulsanti di controllo sempre presenti
  buttons << [
    Telegram::Bot::Types::InlineKeyboardButton.new(text: "➕ Aggiungi", callback_data: "aggiungi:#{gruppo_id}"),
    Telegram::Bot::Types::InlineKeyboardButton.new(text: "🗑 Cancella Tutti", callback_data: "cancella_tutti:#{gruppo_id}")
  ]

  markup = Telegram::Bot::Types::InlineKeyboardMarkup.new(inline_keyboard: buttons)

  begin
    if message_id
      bot.api.edit_message_text(chat_id: chat_id, message_id: message_id, text: text, parse_mode: 'Markdown', reply_markup: markup)
    else
      bot.api.send_message(chat_id: chat_id, text: text, parse_mode: 'Markdown', reply_markup: markup)
    end
  rescue Telegram::Bot::Exceptions::ResponseError => e
    # ignora "message is not modified"
    raise unless e.message&.include?("message is not modified")
  end
end

Telegram::Bot::Client.run(token) do |bot|
  puts "🤖 Bot avviato!"
  bot_username = bot.api.get_me.username rescue nil
  puts "🔗 Username bot: @#{bot_username}" if bot_username

  # comandi ufficiali / menu
  begin
    bot.api.set_my_commands(commands: [
      {command: 'start', description: 'Avvia il bot'},
      {command: 'newgroup', description: 'Crea gruppo virtuale'},
      {command: 'lista', description: 'Mostra la lista della spesa'},
      {command: 'help', description: 'Mostra i comandi disponibili'}
    ])
  rescue => e
    puts "⚠️ set_my_commands fallito: #{e.message}"
  end

  Signal.trap("INT") { puts "\n🛑 Arresto del bot..."; exit }

  bot.listen do |msg|
    begin
      puts "=" * 40
      puts "📨 NUOVO: #{msg.class}"

      case msg
      when Telegram::Bot::Types::CallbackQuery
        chat_id = msg.message.respond_to?(:chat) ? msg.message.chat.id : msg.from.id
        user_id = msg.from.id
        data = msg.data.to_s
        puts "🖱 Callback: #{data} - User: #{user_id} - Chat: #{chat_id}"

        if data =~ /^comprato:(\d+):(\d+)$/
          item_id, gruppo_id = $1.to_i, $2.to_i
          nuovo = Lista.toggle_comprato(gruppo_id, item_id, user_id)
          bot.api.answer_callback_query(callback_query_id: msg.id, text: "Stato aggiornato")
          genera_lista(bot, chat_id, gruppo_id, user_id, msg.message.message_id)

        elsif data =~ /^cancella:(\d+):(\d+)$/
          item_id, gruppo_id = $1.to_i, $2.to_i
          if Lista.cancella(gruppo_id, item_id, user_id)
            bot.api.answer_callback_query(callback_query_id: msg.id, text: "Elemento cancellato")
            genera_lista(bot, chat_id, gruppo_id, user_id, msg.message.message_id)
          else
            bot.api.answer_callback_query(callback_query_id: msg.id, text: "❌ Non puoi cancellare questo elemento")
          end

        elsif data =~ /^cancella_tutti:(\d+)$/
          gruppo_id = $1.to_i
          if Lista.cancella_tutti(gruppo_id, user_id)
            bot.api.answer_callback_query(callback_query_id: msg.id, text: "Articoli comprati rimossi")
            genera_lista(bot, chat_id, gruppo_id, user_id, msg.message.message_id)
          else
            bot.api.answer_callback_query(callback_query_id: msg.id, text: "❌ Solo admin può cancellare tutti")
          end

        elsif data =~ /^aggiungi:(\d+)$/
          gruppo_id = $1.to_i
          DB.execute("INSERT OR REPLACE INTO pending_actions (chat_id, action, gruppo_id) VALUES (?, ?, ?)", [chat_id, "add:#{msg.from.first_name}", gruppo_id])
          bot.api.answer_callback_query(callback_query_id: msg.id)
          bot.api.send_message(chat_id: chat_id, text: "✍️ #{msg.from.first_name}, scrivi gli articoli separati da virgola:")
        end

      when Telegram::Bot::Types::Message
        chat_id = msg.chat.id
        user_id = msg.from.id if msg.from
        puts "💬 Messaggio: #{msg.text} - Chat: #{chat_id} - Type: #{msg.chat.type}"

        # Salva il nome utente quando ricevi un messaggio
        if msg.from
          GroupManager.salva_nome_utente(msg.from.id, msg.from.first_name, msg.from.last_name)
        end

        # privato
        if msg.chat.type == "private"
          case msg.text
          when '/newgroup'
            result = GroupManager.crea_gruppo(bot, user_id, msg.from.first_name)
            if result[:success]
              bot.api.send_message(chat_id: chat_id, text: "🎉 Gruppo virtuale creato (ID: #{result[:gruppo_id]})\nAggiungi il bot al gruppo e scrivi /start nel gruppo.")
            else
              bot.api.send_message(chat_id: chat_id, text: "❌ Errore: #{result[:error]}")
            end
            next
          when '/start'
            bot.api.send_message(chat_id: chat_id, text: "👋 Usa /newgroup per creare un gruppo virtuale.")
            next
          end
        end

        # gestione in gruppi
        if msg.chat.type == "group" || msg.chat.type == "supergroup"
          gruppo = GroupManager.get_gruppo_by_chat_id(chat_id)

          if msg.text == "/start"
            if gruppo.nil?
              GroupManager.associa_gruppo_automaticamente(bot, chat_id, user_id)
              next
            else
              bot.api.send_message(chat_id: chat_id, text: "✅ Gruppo già associato (ID: #{gruppo['id']}). Usa /lista.")
              next
            end
          end

          if gruppo
            if msg.text == '/lista'
              genera_lista(bot, chat_id, gruppo['id'], user_id)
              next
            end

            # pending actions (aggiungi)
            pending = DB.get_first_row("SELECT * FROM pending_actions WHERE chat_id = ?", [chat_id])
            if pending && pending['action'].to_s.start_with?('add') && pending['gruppo_id'] == gruppo['id']
              if msg.text == "/annulla"
                DB.execute("DELETE FROM pending_actions WHERE chat_id = ?", [chat_id])
                bot.api.send_message(chat_id: chat_id, text: "❌ Aggiunta annullata")
                next
              end

              if msg.text && !msg.text.start_with?('/')
                Lista.aggiungi(pending['gruppo_id'], user_id, msg.text)
                DB.execute("DELETE FROM pending_actions WHERE chat_id = ?", [chat_id])
                bot.api.send_message(chat_id: chat_id, text: "✅ #{msg.from.first_name} ha aggiunto: #{msg.text}")
                genera_lista(bot, chat_id, pending['gruppo_id'], user_id)
                next
              end
            end
          else
            bot.api.send_message(chat_id: chat_id, text: "❌ Gruppo non associato. In privato usa /newgroup.")
          end
        end
      end
    rescue => e
      puts "❌ Errore: #{e.message}"
      puts e.backtrace
    end
  end
end
