# models/pending_action.rb
class PendingAction
  def self.create(chat_id:, gruppo_id:, action:, initiator_id:, topic_id: 0)
    sql = "INSERT OR REPLACE INTO pending_actions (chat_id, action, gruppo_id, initiator_id, topic_id, creato_il) VALUES (?, ?, ?, ?, ?, datetime('now'))"
    params = [chat_id, action, gruppo_id, initiator_id, topic_id]

    puts "DEBUG [PA:Create] SQL: #{sql} | PARAMS: #{params.inspect}"
    begin
      DB.execute(sql, params)
      puts "✅ [PA:Create] Successo"
    rescue => e
      puts "❌ [PA:Create] CRASH: #{e.message}"
      raise e
    end
  end

  def self.fetch(chat_id:, topic_id: 0)
    sql = "SELECT * FROM pending_actions WHERE chat_id = ? ORDER BY creato_il DESC LIMIT 1"
    params = [chat_id]

    puts "DEBUG [PA:Fetch] SQL: #{sql} | PARAMS: #{params.inspect}"
    begin
      row = DB.get_first_row(sql, params)
      puts row ? "✅ [PA:Fetch] Trovato: #{row["action"]}" : "⚠️ [PA:Fetch] Nessuna azione"
      row
    rescue => e
      puts "❌ [PA:Fetch] CRASH: #{e.message}"
      raise e
    end
  end

  def self.clear(chat_id:, topic_id: 0)
    sql = "DELETE FROM pending_actions WHERE chat_id = ?"
    params = [chat_id]

    puts "DEBUG [PA:Clear] SQL: #{sql} | PARAMS: #{params.inspect}"
    begin
      DB.execute(sql, params)
      puts "✅ [PA:Clear] Successo"
    rescue => e
      puts "❌ [PA:Clear] CRASH: #{e.message}"
      raise e
    end
  end
end
