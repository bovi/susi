require 'socket'

module Susi
  class SSH
    def self.open(name)
      vm = VM.new(name)
      port = vm.ssh_port
      ip = Socket.ip_address_list.find { |ai| ai.ipv4? && !ai.ipv4_loopback? }
      exec "ssh -p #{port} dabo@#{ip.ip_address}"
    end
  end
end