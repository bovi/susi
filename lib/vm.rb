module Susi
  class VM
    def self.running?(name)
      ps = `ps aux | grep qemu-system-x86_64`
      ps.split("\n").each do |line|
        next unless line.match /\-name/
        m = line.match(/-name (\w+)/)
        n = m[1]
        return true if n == name
      end
      return false
    end

    def initialize(name)
      @name = name
      @qmp_port = nil
      @vnc_port = nil
      @ssh_port = nil

      ps = `ps aux | grep qemu-system-x86_64`
      ps.split("\n").each do |line|
        next unless line.match /\-name/
        m = line.match(/-name (\w+)/)
        n = m[1]
        next unless n == @name

        m = line.match(/-qmp tcp:localhost:(\d+)/)
        @qmp_port = m[1].to_i
      end
    end

    def quit
      QMP.new(@qmp_port) { |q| q.quit }
    end

    def disk
      d = ''
      QMP.new(@qmp_port) { |q| d = q.execute("query-block")[0]['inserted']['file'] }
      d
    end

    def vnc_port
      @vnc_port ||= begin
        port = -1
        QMP.new(@qmp_port) { |q| port = q.execute("query-vnc")['service'] }
        port.to_i
      end
    end

    def vnc_www_port
      vnc_port - 5900 + 5800
    end

    def vnc_websocket_port
      vnc_port - 5900 + 5700
    end

    def ssh_port
      @ssh_port ||= begin
        port = -1
        QMP.new(@qmp_port) do |q|
          resp = q.execute_with_args("human-monitor-command", {"command-line" => "info usernet"})
          resp = resp.split("\r\n")[2].split
          src_port = resp[3].to_i
          dst_port = resp[5].to_i
          if dst_port == 22
            port = src_port
          end
        end
        port.to_i
      end
    end

    def ip
      ip = Socket.ip_address_list.find { |ai| ai.ipv4? && !ai.ipv4_loopback? }
      ip.ip_address
    end

    def qmp_port
      @qmp_port
    end

    def self.quit(name)
      vm = VM.new(name)
      vm.quit
    end

    def self.install(name, disk, iso)
      self.start(name, disk, cdrom: iso)
    end

    def self.get_free_port(start_port, end_port)
      (start_port..end_port).each do |port|
        begin
          server = TCPServer.new('127.0.0.1', port)
          server.close
          return port
        rescue Errno::EADDRINUSE
          next
        end
      end
      raise "No free port found in range #{start_port}..#{end_port}"
    end

    def self.start(name, disk, cdrom: nil)
      qmp_port = self.get_free_port(4000, 4099)
      ssh_port = self.get_free_port(2000, 2099)
      vnc_port = self.get_free_port(5900, 5999)
      vnc_www_port = 5800 + vnc_port - 5900
      vnc_websocket_port = 5700 + vnc_port - 5900

      puts "QMP Port: #{qmp_port}"
      puts "SSH Port: #{ssh_port}"
      puts "VNC Port: #{vnc_port}"
      puts "VNC WWW Port: #{vnc_www_port}"
      puts "VNC WebSocket Port: #{vnc_websocket_port}"

      cmd = []

      cmd << "qemu-system-x86_64"

      # general setup
      cmd << "-name #{name}"
      cmd << "-m 2048"
      cmd << "-hda #{disk}.qcow2"
      cmd << "-daemonize"
      cmd << "-enable-kvm"

      # control interfaces
      cmd << "-qmp tcp:localhost:#{qmp_port},server,nowait"
      cmd << "-vnc :#{vnc_port-5900},websocket=on"

      # Network capabilities
      cmd << "-nic user,model=virtio-net-pci,hostfwd=tcp::#{ssh_port}-:22"

      # cdrom for installation
      if cdrom
        cmd << "-cdrom #{cdrom}"
      end

      puts cmd.join(" ")
      system(cmd.join(" "))

      QMP.new(qmp_port).close
    end

    def self.ls
      ps = `ps aux | grep qemu-system-x86_64`
      ps.split("\n").each do |line|
        next unless line.match /\-name/

        # get VM access
        m = line.match(/-name (\w+)/)
        n = m[1]
        vm = VM.new(n)

        # get local device name or IP
        ip = Socket.ip_address_list.find { |ai| ai.ipv4? && !ai.ipv4_loopback? }

        puts <<-EOF
VM: #{n}
  - Disk: #{vm.disk}
  - QMP: #{vm.qmp_port}
  - VNC: vnc://#{ip.ip_address}:#{vm.vnc_port}
  - Screen: http://#{ip.ip_address}:#{vm.vnc_www_port}/
  - SSH: ssh -p #{vm.ssh_port} dabo@#{ip.ip_address}
EOF
      end
    end
  end
end