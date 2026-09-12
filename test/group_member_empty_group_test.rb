# frozen_string_literal: true

require_relative "../db"

ERASMA_ID = 91_001
FERRAGOSTO_CHAT_ID = -100_091_001

FakeMember = Struct.new(:status)

class FakeTelegramApi
  def get_chat_member(chat_id:, user_id:)
    raise "utente inatteso" unless user_id == ERASMA_ID

    FakeMember.new(chat_id == FERRAGOSTO_CHAT_ID ? "member" : "left")
  end
end

DB.transaction
begin
  DB.execute(
    "INSERT INTO gruppi (nome, chat_id, creato_da) VALUES (?, ?, ?)",
    ["Ferragosto 2026", FERRAGOSTO_CHAT_ID, 91_999]
  )
  gruppo_id = DB.last_insert_row_id

  raise "il gruppo di prova non deve contenere item" unless DB.get_first_value(
    "SELECT COUNT(*) FROM items WHERE gruppo_id = ?",
    [gruppo_id]
  ).zero?
  raise "la precondizione richiede membership locale assente" if DataManager.prendi_gruppi_accessibili(ERASMA_ID).any? do |row|
    row["id"].to_i == gruppo_id
  end

  DataManager.sincronizza_memberships_telegram(ERASMA_ID, FakeTelegramApi.new)

  gruppi = DataManager.prendi_gruppi_accessibili(ERASMA_ID)
  raise "Ferragosto 2026 non visibile a Erasma" unless gruppi.any? { |row| row["id"].to_i == gruppo_id }

  puts "empty group member visibility ok"
ensure
  DB.rollback
end