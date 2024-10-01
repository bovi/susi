module Susi
  def self.debug(msg)
    puts msg if DEBUG
  end

  def self.info(msg)
    puts msg
  end
end
