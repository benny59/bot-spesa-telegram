# models/context.rb
require_relative "../db"

class Context
  attr_reader :chat_id, :topic_id, :user_id, :scope, :config

  def initialize(chat_id:, user_id:, topic_id: 0, scope: :group)
    @chat_id = chat_id
    @user_id = user_id
    @topic_id = topic_id || 0
    @scope = scope.to_sym

    # Caricamento automatico della configurazione tramite il Monitor DataManager
    @config = DataManager.carica_config_utente(user_id)

    puts "[CONTEXT] 🧩 Creato Stato -> U:#{@user_id} | S:#{@scope} | T:#{@topic_id}"
  end

  # ==============================================================================
  # FACTORY METHODS (ENTRY POINTS)
  # ==============================================================================

  def self.from_message(msg)
    chat = msg.chat
    scope = (chat.type == "private") ? :private : :group
    t_id = msg.respond_to?(:message_thread_id) ? (msg.message_thread_id || 0) : 0

    new(
      chat_id: chat.id,
      user_id: msg.from.id,
      topic_id: t_id,
      scope: scope,
    )
  end

  def self.from_callback(callback)
    chat = callback.message.chat
    scope = (chat.type == "private") ? :private : :group
    t_id = callback.message.respond_to?(:message_thread_id) ? (callback.message.message_thread_id || 0) : 0

    new(
      chat_id: chat.id,
      user_id: callback.from.id,
      topic_id: t_id,
      scope: scope,
    )
  end

  # ==============================================================================
  # LOGICA DI STATO (PREDICATI)
  # ==============================================================================

  def private_chat?
    @scope == :private
  end

  def group_chat?
    @scope == :group || @scope == :supergroup
  end

  # Determina se l'utente sta lavorando sulla lista personale (Gruppo 0)
  # Lo è se è in privato e NON ha una configurazione di gruppo attiva
  def lista_personale?
    private_chat? && @config.nil?
  end

  # ==============================================================================
  # GESTIONE CONTESTO ATTIVO (DELEGATA A DATAMANAGER)
  # ==============================================================================

  # Imposta il "telecomando" per operare su un gruppo dalla chat privata
  def self.set_private_context(user_id, gruppo_id, topic_id = 0, topic_name = "Generale")
    new_config = {
      "db_id" => gruppo_id,
      "topic_id" => topic_id,
      "topic_name" => topic_name,
      "set_at" => Time.now.to_i,
    }
    DataManager.salva_config_utente(user_id, new_config)
    puts "[CONTEXT] 🎯 Context salvato per U:#{user_id} -> G:#{gruppo_id} T:#{topic_id}"
  end

  def self.clear_private_context(user_id)
    # Rimuovendo la config, il bot torna a puntare alla Lista Personale (Gruppo 0)
    DB.execute("DELETE FROM config WHERE key = ?", ["context:#{user_id}"])
    puts "[CONTEXT] 🧹 Context rimosso per U:#{user_id} (Ritorno a Lista Personale)"
  end

  # ==============================================================================
  # METODI ELIMINATI (Obsoleti o Fuori Responsabilità)
  # ==============================================================================
  # - edit_or_send: Spostato in UI/Handler (Un modello non deve conoscere l'API Bot)
  # - notify_private_activated: Spostato in UI/Handler
  # - show_group_selector: Spostato in MessageHandler/KeyboardGenerator
  # - update_garbage_collector: Gestito ora da CleanupManager
end
