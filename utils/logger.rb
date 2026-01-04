# utils/logger.rb
class Logger
  def self.debug(msg, data = {}); puts "[DEBUG] #{msg} #{data}"; end
  def self.info(msg, data = {}); puts "[INFO] #{msg} #{data}"; end
  def self.warn(msg, data = {}); puts "[WARN] #{msg} #{data}"; end
  def self.error(msg, data = {}); puts "[ERROR] #{msg} #{data}"; end
end
