require_relative 'output'

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
      @qmp = nil
      @qmp_port = nil
      @vnc_port = nil
      @ssh_port = nil

      Susi::debug "Searching for VM #{name}"

      ps = `ps aux | grep qemu-system-x86_64`
      Susi::debug ps
      ps.split("\n").each do |line|
        next unless line.match /\-name/
        m = line.match(/-name ([a-zA-Z0-9\-_\.]+)\s/)
        Susi::debug "match: #{m[1]}"
        n = m[1]
        next unless n == @name
        Susi::debug "Found VM #{n}"

        m = line.match(/-qmp tcp:localhost:(\d+)/)
        @qmp_port = m[1].to_i
        Susi::debug "Found QMP port #{@qmp_port}"
      end
      @qmp = QMP.new(@qmp_port)

      if block_given?
        yield(self)

        @qmp.close
      end
    end

    def quit
      #QMP.new(@qmp_port) { |q| q.quit }
      @qmp.quit
    end

    def disk
      d = ''
      #QMP.new(@qmp_port) { |q| d = q.execute("query-block")[0]['inserted']['file'] }
      d = @qmp.execute("query-block")[0]['inserted']['file']
      d
    end

    def vnc_port
      @vnc_port ||= begin
        port = -1
        #QMP.new(@qmp_port) { |q| port = q.execute("query-vnc")['service'] }
        port = @qmp.execute("query-vnc")['service']
        port.to_i
      end
    end

    def vnc_www_port
      vnc_port - 100
    end

    def vnc_websocket_port
      vnc_port - 200
    end

    def ssh_port
      @ssh_port ||= begin
        port = -1
        #QMP.new(@qmp_port) do |q|
          #resp = q.execute_with_args("human-monitor-command", {"command-line" => "info usernet"})
          resp = @qmp.execute_with_args("human-monitor-command", {"command-line" => "info usernet"})
          resp = resp.split("\r\n")[2].split
          src_port = resp[3].to_i
          dst_port = resp[5].to_i
          if dst_port == 22
            port = src_port
          end
        #end
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
      vnc_www_port = vnc_port - 100
      vnc_websocket_port = vnc_port - 200

      Susi::debug "Starting VM #{name} with QMP on port #{qmp_port}, VNC on port #{vnc_port}, SSH on port #{ssh_port}"

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

      cmd = cmd.join(" ")
      Susi::debug cmd
      system(cmd)

      QMP.new(qmp_port).close
    end

    def self.ls
      ps = `ps aux | grep qemu-system-x86_64`
      ps.split("\n").each do |line|
        next unless line.match /\-name/

        # get VM access
        m = line.match(/-name (\w+)/)
        n = m[1]
        VM.new(n) do |vm|
          # get local device name or IP
          ip = vm.ip

          puts <<-EOF
VM: #{n}
  - Disk: #{vm.disk}
  - QMP: #{vm.qmp_port}
  - VNC: vnc://#{ip}:#{vm.vnc_port}
  - Screen: http://#{ip}:#{vm.vnc_www_port}/
  - Websocket: ws://#{ip}:#{vm.vnc_websocket_port}/
  - SSH: ssh -p #{vm.ssh_port} dabo@#{ip}
EOF
        end
      end
    end
  end
end