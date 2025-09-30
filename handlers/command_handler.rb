# handlers/command_handler.rb
require_relative "../db"  # <-- AGGIUNGI QUESTO

class CommandHandler
  def self.handle_checklist_command(bot, message, gruppo_id)
    chat_id = message.chat.id
    user_id = message.from.id

    # Recupera il limite dalla tabella CONFIG del database
    checklist_limit = DB.get_first_value(
      "SELECT value FROM config WHERE key = 'checklist_limit'"
    )
    limite = (checklist_limit || 10).to_i  # <-- CORREGGI QUESTA RIGA

    top_articoli = StoricoHandler.top_articoli_gruppo(gruppo_id, limite)

    if top_articoli.empty?
      bot.api.send_message(
        chat_id: chat_id,
        text: "📊 *Checklist Articoli Frequenti*\n\nNessun articolo nello storico per questo gruppo.\n\nInizia aggiungendo articoli con /+ per popolare la checklist!",
        parse_mode: "Markdown",
      )
      return
    end

    # Crea la tastiera inline con gli articoli
    keyboard = []

    top_articoli.each do |articolo|
      nome = articolo["nome"].capitalize
      conteggio = articolo["conteggio"]

      keyboard << [
        {
          text: "➕ #{nome} (#{conteggio}x)",
          callback_data: "checklist_add:#{articolo["nome"]}:#{gruppo_id}:#{user_id}",
        },
      ]
    end

    # Aggiungi pulsante chiudi
    keyboard << [{ text: "❌ Chiudi", callback_data: "checklist_close:#{chat_id}" }]

    markup = { inline_keyboard: keyboard }

    bot.api.send_message(
      chat_id: chat_id,
      text: "📋 *Checklist Articoli Frequenti*\n\nClicca '+' per aggiungere direttamente alla lista:\n",
      parse_mode: "Markdown",
      reply_markup: markup,
    )
  rescue => e
    puts "❌ Errore in handle_checklist_command: #{e.message}"
    puts e.backtrace

    bot.api.send_message(
      chat_id: chat_id,
      text: "❌ Si è verificato un errore nel caricamento della checklist.",
    )
  end
end
