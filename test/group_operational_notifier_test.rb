# frozen_string_literal: true

require_relative "../db"
require_relative "../models/group_manager"
require_relative "../models/group_operational_notifier"

class FakeApi
  attr_reader :messages

  def initialize
    @messages = []
  end

  def send_message(**options)
    @messages << options
  end
end

class FakeBot
  attr_reader :api

  def initialize
    @api = FakeApi.new
  end
end

DB.execute("DELETE FROM gruppi")
DB.execute("INSERT INTO gruppi (id, nome, chat_id) VALUES (1, 'Test', -100)")

bot = FakeBot.new
item = { "gruppo_id" => 1, "topic_id" => 8, "nome" => "Pane" }

raise "le notifiche devono essere abilitate di default" unless GroupManager.notifiche_operazioni_abilitate?(1)

GroupOperationalNotifier.item_action(bot: bot, item: item, actor: "Marco", action: :carrello)
raise "notifica operativa non inviata" unless bot.api.messages.size == 1
raise "topic errato" unless bot.api.messages.first[:message_thread_id] == 8

GroupManager.imposta_notifiche_operazioni(1, false)
GroupOperationalNotifier.item_action(bot: bot, item: item, actor: "Marco", action: :soft_delete)
raise "quiet deve bloccare le notifiche operative" unless bot.api.messages.size == 1

GroupManager.imposta_notifiche_operazioni(1, true)
GroupOperationalNotifier.scopetta(
  bot: bot,
  gruppo_id: 1,
  topic_id: 0,
  actor: "Marco",
  comprati: ["Pane"],
  cancellati: []
)
raise "verbose deve riattivare le notifiche operative" unless bot.api.messages.size == 2

GroupOperationalNotifier.notify(bot: bot, gruppo_id: 0, topic_id: 0, text: "Ignora")
raise "la lista personale non deve inviare notifiche" unless bot.api.messages.size == 2

puts "group operational notifier ok"