require_relative '../db'
require 'sqlite3'

db = DB.db

def column_exists?(db, table, column)
  info = db.execute2("PRAGMA table_info(#{table})")
  info.drop(1).any? { |row| row[1] == column }
end

table = 'products' # adjust if your table is named differently

columns = {
  'energy_kcal'    => 'REAL',
  'fat_g'          => 'REAL',
  'saturated_fat_g'=> 'REAL',
  'carbohydrates_g'=> 'REAL',
  'sugars_g'       => 'REAL',
  'proteins_g'     => 'REAL',
  'salt_g'         => 'REAL',
  'fiber_g'        => 'REAL'
}

columns.each do |name, type|
  unless column_exists?(db, table, name)
    puts "Adding column #{name} to #{table}"
    db.execute("ALTER TABLE #{table} ADD COLUMN #{name} #{type}")
  else
    puts "Column #{name} already exists"
  end
end

puts "Migration finished."