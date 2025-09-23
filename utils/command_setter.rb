# helpers/command_setter.rb
class CommandSetter
  def self.aggiorna_comandi(bot)
    begin
      # Comandi per CHAT PRIVATE
      private_commands = [
        {
          command: 'start',
          description: 'Avvia il bot e mostra help'
        },
        {
          command: 'newgroup', 
          description: 'Crea un nuovo gruppo virtuale'
        },
        {
          command: 'listagruppi',
          description: 'Lista dei gruppi creati (solo creatore)'
        },
        {
          command: 'whitelist_show',
          description: 'Mostra whitelist (solo creatore)'
        },
        {
          command: 'pending_requests',
          description: 'Richieste in sospeso (solo creatore)'
        }
      ]

      # Comandi per GRUPPI
      group_commands = [
        {
          command: 'lista',
          description: 'Visualizza la lista della spesa'
        },
        {
          command: 'checklist',
          description: 'Articoli frequenti da aggiungere'
        },
        {
          command: 'ss',
          description: 'Esporta lista in PDF'
        },
        {
          command: 'delgroup',
          description: 'Cancella il gruppo (solo creatore)'
        },
        {
        command: 'cleanup',
        description: 'Pulizia database (solo creatore)'
        }
      ]

      # Imposta comandi per chat private
      bot.api.set_my_commands(
        commands: private_commands, 
        scope: { type: 'default' }
      )
      puts "✅ Comandi privati impostati: #{private_commands.map { |c| c[:command] }.join(', ')}"

      # Imposta comandi per gruppi
      bot.api.set_my_commands(
        commands: group_commands, 
        scope: { type: 'all_group_chats' }
      )
      puts "✅ Comandi gruppo impostati: #{group_commands.map { |c| c[:command] }.join(', ')}"

      puts "🎉 Comandi aggiornati con successo!"

    rescue => e
      puts "⚠️ Avviso: Impossibile aggiornare i comandi (forse token senza permessi?): #{e.message}"
    end
  end
end
