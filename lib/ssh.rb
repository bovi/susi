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
      VM.new(name) do |vm|
        Net::SSH.start(vm.ip, 'dabo', port: vm.ssh_port, keys: [File.expand_path('~/.ssh/id_ed25519')]) do |ssh|
          Susi::debug "Setting up VM hostname..."

          output = ssh.exec!("sudo hostnamectl set-hostname #{name}")
          Susi::debug "Setting hostname: #{output}"

          output = ssh.exec!("sudo sed -i 's/susi/#{name}/' /etc/hosts")
          Susi::debug "Updating /etc/hosts: #{output}"

          Susi::debug "Hostname setup complete."
        end
      end
    end

    def self.setup_virtio_filesystem(name)
      VM.new(name) do |vm|
        Net::SSH.start(vm.ip, 'dabo', port: vm.ssh_port, keys: [File.expand_path('~/.ssh/id_ed25519')]) do |ssh|
          Susi::debug "Setting up virtio filesystem..."

          output = ssh.exec!("echo 'susi_virtio_share /mnt/susi 9p trans=virtio,version=9p2000.L,rw 0 0' | sudo tee -a /etc/fstab")
          Susi::debug "Adding virtio share to /etc/fstab: #{output}"

          output = ssh.exec!("sudo mkdir -p /mnt/susi")
          Susi::debug "Creating mount point: #{output}"

          output = ssh.exec!("sudo systemctl daemon-reload")
          Susi::debug "Reloading systemd: #{output}"

          output = ssh.exec!("sudo mount -a")
          Susi::debug "Mounting all filesystems: #{output}"

          # Check if the mount was successful
          output = ssh.exec!("mount | grep susi_virtio_share")
          if output.empty?
            Susi::debug "Warning: virtio share mount not found. Checking dmesg for errors..."
            dmesg_output = ssh.exec!("dmesg | tail -n 20")
            Susi::debug "Recent dmesg output: #{dmesg_output}"
          else
            Susi::debug "Virtio share mounted successfully: #{output}"
          end
          Susi::debug "Virtio filesystem setup complete."
        end
      end
    end
  end
end