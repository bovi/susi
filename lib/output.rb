module Susi
  def self.debug(msg)
    puts msg if DEBUG
  end

  def self.info(msg)
    puts msg
  end

  def self.check_command(cmd)
    unless system("which #{cmd} > /dev/null 2>&1")
      raise "Required command '#{cmd}' is not installed. Please install it first."
    end
  end
end
