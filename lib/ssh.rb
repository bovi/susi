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
      login(name) do |vm, ssh|
        Susi::debug "Setting up VM hostname..."

        output = ssh.exec!("sudo hostnamectl set-hostname #{name}")
        Susi::debug "Setting hostname: #{output}"

        output = ssh.exec!("sudo sed -i 's/susi/#{name}/' /etc/hosts")
        Susi::debug "Updating /etc/hosts: #{output}"

        Susi::debug "Hostname setup complete."
      end
    end

    def self.setup_virtio_filesystem(name)
      login(name) do |vm, ssh|
        Susi::debug "Setting up virtio filesystem..."

        output = ssh.exec!("echo 'susi_virtio_share /mnt/susi 9p trans=virtio,version=9p2000.L,msize=512000,rw 0 0' | sudo tee -a /etc/fstab")
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

        output = ssh.exec!("ln -s /mnt/susi /home/dabo/susi")
        Susi::debug "Creating symlink: #{output}"
      end
    end

    def self.apt_update(name)
      login(name) do |vm, ssh|
        Susi::debug "apt update"
        output = ssh.exec!("sudo apt update -y")
      end
    end

    def self.apt_upgrade(name)
      login(name) do |vm, ssh|
        Susi::debug "apt upgrade"
        output = ssh.exec!("sudo apt upgrade -y")
      end
    end

    def self.update(name)
      login_w_pw(name, 'dabo') do |vm, ssh|
        Susi::debug "update VM via apt"
        output = ssh.exec!("sudo apt update -y")
        output = ssh.exec!("sudo apt upgrade -y")
        output = ssh.exec!("sudo shutdown -h now")
      end
    end

    def self.install_dpkg(name, dpkg)
      login(name) do |vm, ssh|
        Susi::debug "Installing dpkg..."
        output = ssh.exec!("sudo apt-get update")
        Susi::debug "Updating package list: #{output}"

        output = ssh.exec!("sudo apt-get install -y #{dpkg.join(' ')}")
        Susi::debug "Installing dpkg: #{output}"
      end
    end

    def self.reboot(name)
      login(name) do |vm, ssh|
        Susi::debug "Rebooting the VM..."
        output = ssh.exec!("sudo reboot")
      end
    end

    def self.login(name, &block)
      VM.new(name) do |vm|
        Net::SSH.start(vm.ip, 'dabo', port: vm.ssh_port, keys: [File.expand_path('~/.ssh/id_ed25519')]) do |ssh|
          Susi::debug "Logged into VM #{name}"
          block.call(vm, ssh)
        end
      end
    end

    def self.login_w_pw(name, pass, &block)
      VM.new(name) do |vm|
        Net::SSH.start(vm.ip, 'dabo', port: vm.ssh_port, password: pass) do |ssh|
          Susi::debug "Logged into VM #{name} via password"
          block.call(vm, ssh)
        end
      end
    end
  end
end
