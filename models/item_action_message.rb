# frozen_string_literal: true

require "cgi"
require_relative "group_operational_notifier"

module ItemActionMessage
  module_function

  def text_for(actor, item_name, action)
    user_name = CGI.escapeHTML(actor.to_s.strip.empty? ? "Utente" : actor.to_s)
    item_label = CGI.escapeHTML(item_name.to_s)

    case action.to_s
    when "carrello"
      "🛒 <b>#{user_name}</b> ha messo nel carrello: <b>#{item_label}</b>"
    when "rimesso_in_lista", "restore"
      "↩️ <b>#{user_name}</b> ha rimesso in lista: <b>#{item_label}</b>"
    when "soft_delete", "eliminato"
      "🗑️ <b>#{user_name}</b> ha eliminato: <b>#{item_label}</b>"
    when "disponibile"
      "✅ <b>#{user_name}</b> ha segnato: <b>#{item_label}</b> come disponibile"
    when "non_disponibile"
      "🚫 <b>#{user_name}</b> ha segnato: <b>#{item_label}</b> come non disponibile"
    when "spostato"
      "➡️ <b>#{user_name}</b> ha spostato: <b>#{item_label}</b>"
    when "spostato_qui"
      "⬅️ <b>#{user_name}</b> ha spostato qui: <b>#{item_label}</b>"
    when "aggiunto"
      "➕ <b>#{user_name}</b> ha aggiunto: <b>#{item_label}</b>"
    when "rimosso"
      "➖ <b>#{user_name}</b> ha rimosso: <b>#{item_label}</b>"
    when "modificato"
      "✏️ <b>#{user_name}</b> ha modificato: <b>#{item_label}</b>"
    when "foto"
      "📸 <b>#{user_name}</b> ha aggiunto una foto: <b>#{item_label}</b>"
    else
      "<b>#{user_name}</b>: <b>#{item_label}</b>"
    end
  end

  def edit_text_for(actor, item_name, previous_name = nil, new_name = nil, previous_category = nil, new_category = nil)
    user_name = CGI.escapeHTML(actor.to_s.strip.empty? ? "Utente" : actor.to_s)
    item_label = CGI.escapeHTML(item_name.to_s)
    old_name = CGI.escapeHTML(previous_name.to_s)
    new_name_value = CGI.escapeHTML(new_name.to_s)
    old_category = CGI.escapeHTML(previous_category.to_s)
    new_category_value = CGI.escapeHTML(new_category.to_s)

    if old_name.strip != new_name_value.strip
      return "✏️ <b>#{user_name}</b> ha modificato: <s>#{old_name}</s> → <b>#{new_name_value}</b>"
    end

    if old_category.strip != new_category_value.strip
      return if old_category.strip.empty? && new_category_value.strip.empty?

      if old_category.strip.empty?
        "✏️ <b>#{user_name}</b> ha impostato la categoria: <b>#{new_category_value}</b> per <b>#{item_label}</b>"
      elsif new_category_value.strip.empty?
        "✏️ <b>#{user_name}</b> ha rimosso la categoria: <s>#{old_category}</s> da <b>#{item_label}</b>"
      else
        "✏️ <b>#{user_name}</b> ha modificato categoria: <s>#{old_category}</s> → <b>#{new_category_value}</b> per <b>#{item_label}</b>"
      end
    else
      "✏️ <b>#{user_name}</b> ha modificato: <b>#{item_label}</b>"
    end
  end

  def notify_group(bot, item_row, actor, action)
    GroupOperationalNotifier.item_action(
      bot: bot,
      item: item_row,
      actor: actor,
      action: action
    )
  end
end
