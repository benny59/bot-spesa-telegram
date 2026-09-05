# frozen_string_literal: true

require_relative "../db"
require_relative "group_manager"
require_relative "item_action_message"
require_relative "../handlers/storico_manager"

module GroupOperationalNotifier
  module_function

  def item_action(bot:, item:, actor:, action:)
    return unless item

    notify(
      bot: bot,
      gruppo_id: item["gruppo_id"].to_i,
      topic_id: item["topic_id"].to_i,
      text: ItemActionMessage.text_for(actor, item["nome"], action)
    )
  end

  def scopetta(bot:, gruppo_id:, topic_id:, actor:, comprati:, cancellati:, mantenuti: [], force: false)
    notify(
      bot: bot,
      gruppo_id: gruppo_id,
      topic_id: topic_id,
      text: StoricoManager.notifica_scopetta_html(actor, comprati: comprati, cancellati: cancellati, mantenuti: mantenuti),
      force: force
    )
  end

  def notify(bot:, gruppo_id:, topic_id:, text:, disable_notification: nil, force: false)
    return if gruppo_id.to_i == 0
    return unless force || GroupManager.notifiche_operazioni_abilitate?(gruppo_id)

    chat_id = DataManager.get_real_chat_id(gruppo_id.to_i)
    return unless chat_id

    options = {
      chat_id: chat_id,
      message_thread_id: topic_id.to_i != 0 ? topic_id.to_i : nil,
      text: text,
      parse_mode: "HTML"
    }
    options[:disable_notification] = disable_notification unless disable_notification.nil?
    bot.api.send_message(**options)
  rescue => e
    puts "⚠️ [GROUP_NOTIFY] notifica fallita: #{e.class}: #{e.message}"
  end
end