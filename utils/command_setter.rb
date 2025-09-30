class CommandSetter
  def self.aggiorna_comandi(bot)
    # TUTTI vedono TUTTI i comandi, ma nel codice controlli i permessi
    tutti_cmds = [
      Telegram::Bot::Types::BotCommand.new(command: "start", description: "Avvia il bot"),
      Telegram::Bot::Types::BotCommand.new(command: "newgroup", description: "Registra nuovo gruppo"),
      Telegram::Bot::Types::BotCommand.new(command: "carte", description: "Gestione carte personali"),
      Telegram::Bot::Types::BotCommand.new(command: "addcarta", description: "Aggiungi carta: NOME CODICE"),
      Telegram::Bot::Types::BotCommand.new(command: "cartegruppo", description: "Carte condivise del gruppo"),
      Telegram::Bot::Types::BotCommand.new(command: "addcartagruppo", description: "Aggiungi carta gruppo: NOME CODICE"),
      Telegram::Bot::Types::BotCommand.new(command: "delcartagruppo", description: "Rimuovi carta dal gruppo"),
      Telegram::Bot::Types::BotCommand.new(command: "lista", description: "Mostra lista della spesa"),
      Telegram::Bot::Types::BotCommand.new(command: "checklist", description: "Controlla lista completata"),
      Telegram::Bot::Types::BotCommand.new(command: "ss", description: "Screenshot lista (PDF)"),
      Telegram::Bot::Types::BotCommand.new(command: "delgroup", description: "Cancella gruppo"),
      Telegram::Bot::Types::BotCommand.new(command: "listagruppi", description: "Mostra gruppi registrati"),
      Telegram::Bot::Types::BotCommand.new(command: "whitelist_show", description: "Visualizza whitelist"),
      Telegram::Bot::Types::BotCommand.new(command: "pending_requests", description: "Richieste in attesa"),
      Telegram::Bot::Types::BotCommand.new(command: "whitelist_add", description: "Aggiungi utente: ID"),
      Telegram::Bot::Types::BotCommand.new(command: "whitelist_remove", description: "Rimuovi utente: ID"),
      Telegram::Bot::Types::BotCommand.new(command: "cleanup", description: "Pulisci gruppi/utenti orfani"),
      Telegram::Bot::Types::BotCommand.new(command: "reportcarte", description: "Report carte condivise nei gruppi"),
    ]

    bot.api.set_my_commands(commands: tutti_cmds)
    puts "✅ Comandi aggiornati con parametri"
  end
end
