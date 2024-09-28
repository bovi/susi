require 'socket'
require 'net/ssh'

module Susi
  class SSH
    def self.open(name)
      vm = VM.new(name)
      exec "ssh -p #{vm.ssh_port} dabo@#{vm.ip}"
    end

    def self.set_hostname(name)
      vm = VM.new(name)
      Net::SSH.start(vm.ip, 'dabo', port: vm.ssh_port, keys: [File.expand_path('~/.ssh/id_ed25519')]) do |ssh|
        puts "setting up VM..."
        ssh.exec!("sudo hostnamectl set-hostname #{name}")
      end
    end
  end
end