# models/preferences.rb
require_relative '../db'

class Preferences
  def self.get_view_mode(user_id)
    DB.get_first_value("SELECT view_mode FROM user_preferences WHERE user_id = ?", [user_id]) || 'compact'
  end

  def self.toggle_view_mode(user_id)
    current_mode = get_view_mode(user_id)
    new_mode = current_mode == 'compact' ? 'text_only' : 'compact'
    
    DB.execute("INSERT OR REPLACE INTO user_preferences (user_id, view_mode) VALUES (?, ?)", 
              [user_id, new_mode])
    
    new_mode
  end
end
