class CommandSetter
  def self.aggiorna_comandi(bot)
    # TUTTI vedono TUTTI i comandi, ma nel codice controlli i permessi
    tutti_cmds = [
      Telegram::Bot::Types::BotCommand.new(command: "start", description: "Avvia il bot"),
      Telegram::Bot::Types::BotCommand.new(command: "newgroup", description: "Registra nuovo gruppo"),
      Telegram::Bot::Types::BotCommand.new(command: "carte", description: "Gestione carte"),
      Telegram::Bot::Types::BotCommand.new(command: "addcarta", description: "Aggiungi una carta"),
      Telegram::Bot::Types::BotCommand.new(command: "lista", description: "Mostra lista"),
      Telegram::Bot::Types::BotCommand.new(command: "checklist", description: "Controlla lista"),
      Telegram::Bot::Types::BotCommand.new(command: "ss", description: "Screenshot"),
      Telegram::Bot::Types::BotCommand.new(command: "delgroup", description: "Cancella gruppo"),
      Telegram::Bot::Types::BotCommand.new(command: "listagruppi", description: "Mostra gruppi registrati"),
      Telegram::Bot::Types::BotCommand.new(command: "whitelist_show", description: "Visualizza whitelist"),
      Telegram::Bot::Types::BotCommand.new(command: "pending_requests", description: "Richieste in attesa"),
      Telegram::Bot::Types::BotCommand.new(command: "whitelist_add", description: "Aggiungi utente in whitelist"),
      Telegram::Bot::Types::BotCommand.new(command: "cleanup", description: "Pulisci gruppi/utenti orfani")
    ]

    bot.api.set_my_commands(commands: tutti_cmds)
    puts "✅ Tutti i comandi impostati (controllo permessi via codice)"
  end
end
