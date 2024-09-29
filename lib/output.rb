module Susi
  DEBUG = false

  def self.debug(msg)
    puts msg if DEBUG
  end

  def self.info(msg)
    puts msg
  end
end
