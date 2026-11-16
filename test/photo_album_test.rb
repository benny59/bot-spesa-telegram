# frozen_string_literal: true

require "tmpdir"
ENV["SPESA_DB"] = File.join(Dir.tmpdir, "photo_album_test_#{Process.pid}.db") if ENV["SPESA_DB"].to_s.empty?
require "telegram/bot"
require_relative "../db"
require_relative "../handlers/photo_album"

%w[item_images items gruppi photo_albums].each { |t| DB.execute("DELETE FROM #{t}") }
DB.execute("INSERT INTO gruppi (id, nome, chat_id) VALUES (1, 'Test', -100)")

def nuovo(nome, comprato, n_foto)
  DB.execute("INSERT INTO items (gruppo_id, topic_id, creato_da, nome, comprato, deleted) VALUES (1, 7, 42, ?, ?, 0)", [nome, comprato])
  id = DB.get_first_value("SELECT last_insert_rowid()")
  n_foto.times { |k| DB.execute("INSERT INTO item_images (item_id, file_id, file_unique_id) VALUES (?, ?, ?)", [id, "F#{id}_#{k}", "U#{id}_#{k}"]) }
  id
end

# 11 articoli da comprare con foto (=> album da 10 + foto singola), 2 comprati, 1 senza foto
11.times { |i| nuovo("Da comprare #{i}", "", 1) }
2.times { |i| nuovo("Comprato #{i}", "42", 1) }
nuovo("Senza foto", "", 0)

class FakeApi
  attr_reader :calls
  Msg = Struct.new(:message_id, :photo)
  def initialize; @calls = []; @n = 100; end
  def send_media_group(**a); @calls << [:group, a]; a[:media].map { Msg.new(@n += 1, nil) }; end
  def send_photo(**a); @calls << [:photo, a]; Msg.new(@n += 1, nil); end
  def send_message(**a); @calls << [:msg, a]; Msg.new(@n += 1, nil); end
  def delete_message(**a); @calls << [:del, a]; true; end
end
Bot = Struct.new(:api)

def tipo(api, t) = api.calls.select { |c| c[0] == t }

api = FakeApi.new
bot = Bot.new(api)
album = PhotoAlbum.apri(bot, -100, 1, 7)
raise "album non creato" unless album.is_a?(Integer)
raise "atteso 1 album da 10" unless tipo(api, :group).size == 1 && tipo(api, :group)[0][1][:media].size == 10
raise "atteso 1 foto singola per l'undicesima" unless tipo(api, :photo).size == 1
raise "i comprati non vanno mostrati di default" if api.calls.any? { |c| c[1].to_s.include?("Comprato") }
raise "thread non passato" unless tipo(api, :group)[0][1][:message_thread_id] == 7
ctrl = tipo(api, :msg)[0][1]
bottoni = ctrl[:reply_markup].inline_keyboard.flatten.map(&:callback_data)
raise "manca 'anche comprati'" unless bottoni.include?("photo_switch:#{album}:1")
raise "manca chiudi" unless bottoni.include?("photo_close:#{album}")
ids = JSON.parse(DB.get_first_value("SELECT message_ids FROM photo_albums WHERE id = ?", [album]))
raise "id messaggi non salvati (10+1+controllo)" unless ids.size == 12

# Riclic: l'album precedente viene cancellato, resta un solo record
api.calls.clear
album2 = PhotoAlbum.apri(bot, -100, 1, 7)
raise "riclic non cancella il precedente" unless tipo(api, :del).size == 12
raise "record vecchio non rimosso" unless DB.get_first_value("SELECT COUNT(*) FROM photo_albums") == 1

# Switch: anche i comprati
api.calls.clear
PhotoAlbum.cambia(bot, -100, album2, true)
inviate = tipo(api, :group).sum { |c| c[1][:media].size } + tipo(api, :photo).size
raise "con 'tutti' attese 13 foto, trovate #{inviate}" unless inviate == 13

# Chiudi: cancella tutto e rimuove il record
api.calls.clear
album3 = DB.get_first_value("SELECT id FROM photo_albums")
raise "chiudi fallita" unless PhotoAlbum.chiudi(bot, -100, album3)
raise "chiudi non cancella tutti i messaggi" unless tipo(api, :del).size == 14
raise "record non rimosso" unless DB.get_first_value("SELECT COUNT(*) FROM photo_albums") == 0
raise "chiudi su id inesistente deve dare false" if PhotoAlbum.chiudi(bot, -100, 9999)

# Lista senza foto
DB.execute("DELETE FROM item_images")
raise "lista senza foto deve dare :vuoto" unless PhotoAlbum.apri(bot, -100, 1, 7) == :vuoto

puts "photo album ok"
