require 'socket'
require 'net/ssh'

require_relative 'output'

module Susi
  class SSH
    def self.open(name)
      vm = VM.new(name)
      exec "ssh -p #{vm.ssh_port} dabo@#{vm.ip}"
    end

    def self.set_hostname(name)
      vm = VM.new(name)
      Net::SSH.start(vm.ip, 'dabo', port: vm.ssh_port, keys: [File.expand_path('~/.ssh/id_ed25519')]) do |ssh|
        Susi::debug "Setting up VM..."
        ssh.exec!("sudo hostnamectl set-hostname #{name}")
        ssh.exec!("sudo sed -i 's/susi/#{name}/' /etc/hosts")
      end
    end
  end
end