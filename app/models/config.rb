class Config
  attr_accessor :key, :value

  def initialize(key, value)
    @key = key
    @value = value
  end

  def self.find(db, key)
    result = db.execute("SELECT value FROM config WHERE key = ?", [key])
    result.empty? ? nil : result[0][0]
  end

  def self.all(db)
    db.execute("SELECT * FROM config")
  end

  def save(db)
    db.execute("INSERT OR REPLACE INTO config (key, value) VALUES (?, ?)", [@key, @value])
  end
end