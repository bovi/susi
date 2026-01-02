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
        Susi::debug line
        m = line.match(/-name\s(.*?)\s/)
        Susi::debug m.inspect
        Susi::debug "match: #{m[1]}"
        n = m[1]
        next unless n == @name
        n = n.split(/\//).last
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

    def shutdown
      Susi::debug "Initiating shutdown for VM #{@name}"
      @qmp.execute("system_powerdown")
    end

    def quit
      Susi::debug "Quitting QMP for VM #{@name}"
      @qmp.quit
    end

    def disk
      d = ''
      d = @qmp.execute("query-block")[0]['inserted']['file']
      d
    end

    def vnc_port
      @vnc_port ||= begin
        port = -1
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
        resp = @qmp.execute_with_args("human-monitor-command", {"command-line" => "info usernet"})
        Susi::debug resp.to_s
        resp = resp.lines.grep(/HOST_FORWARD/).first.split
        src_port = resp[3].to_i
        dst_port = resp[5].to_i
        if dst_port == 22
          port = src_port
        end
        port.to_i
      end
    end

    def forwarded_ports
      @forwarded_ports ||= begin
        _fwports = []
        resp = @qmp.execute_with_args("human-monitor-command", {"command-line" => "info usernet"})
        Susi::debug resp.to_s
        resp = resp.lines.grep(/HOST_FORWARD/)
        resp.each do |fwport|
          fwport = fwport.split
          src_port = fwport[3].to_i
          Susi::debug "src_port: #{src_port}"
          dst_port = fwport[5].to_i
          Susi::debug "dst: #{dst_port}"
          next if dst_port == 22
          _fwports << { src_port: src_port, dst_port: dst_port }
        end
        _fwports
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

    def self.prepare_update(name, disk)
      self.start(name, disk)
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

    def self.start(name, disk, cdrom: nil, usb: nil,
                    shared_dir: nil, cpu_count: 1, memory: 2048,
                    forwarded_ports: [])
      qmp_port = self.get_free_port(4000, 4099)
      ssh_port = self.get_free_port(2000, 2099)
      vnc_port = self.get_free_port(5900, 5999)
      vnc_www_port = vnc_port - 100
      vnc_websocket_port = vnc_port - 200

      Susi::debug "Starting VM #{name} with QMP on port #{qmp_port}, VNC on port #{vnc_port}, SSH on port #{ssh_port}, CPU count: #{cpu_count}"

      cmd = []

      cmd << "sudo"
      cmd << `which qemu-system-x86_64`.strip

      # general setup
      cmd << "-name #{name}"
      cmd << "-m #{memory}"
      cmd << "-smp #{cpu_count}"
      cmd << "-drive file=#{File.expand_path(disk)}.qcow2,format=qcow2,index=0,media=disk"
      cmd << "-daemonize"
      cmd << "-enable-kvm"
      cmd << "-audiodev none,id=noaudio"

      # Add shared directory passthrough if specified
      if shared_dir
        Susi::debug "Adding shared directory #{shared_dir}"
        shared_dir_path = File.expand_path(shared_dir)
        cmd << "-fsdev local,security_model=passthrough,id=fsdev0,path=#{shared_dir_path}"
        cmd << "-device virtio-9p-pci,fsdev=fsdev0,mount_tag=susi_virtio_share"
      end

      # control interfaces
      cmd << "-qmp tcp:localhost:#{qmp_port},server,nowait"
      cmd << "-vnc :#{vnc_port-5900},websocket=on"

      # Network capabilities
      fw_ports = ["#{ssh_port}-:22"]
      forwarded_ports.each do |x|
        fw_ports << "#{x}-:#{x}"
      end
      cmd << "-nic user,model=virtio-net-pci,#{fw_ports.map {|p| "hostfwd=tcp::#{p}"}.join(',')}"

      # cdrom for installation
      if cdrom
        #cmd << "-cdrom #{cdrom}"
        cmd << "-drive file=#{File.expand_path(cdrom)},format=raw,index=1,media=cdrom"
      end

      if usb
        cmd << "-device qemu-xhci"
        usb.each do |usbstr|
          vendor, product = usbstr.split(':')
          cmd << "-device usb-host,vendorid=0x#{vendor},productid=0x#{product}"
        end
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
        m = line.match(/-name\s(.*?)\s/)
        n = m[1]
        n = n.split('/').last
        VM.new(n) do |vm|
          # get local device name or IP
          ip = vm.ip

          shared_dir = line.match(/-fsdev.*path=([^\s,]+)/)
          shared_dir_info = shared_dir ? "  - Shared Directory: #{shared_dir[1]}" : ""

          if vm.forwarded_ports.size > 0
            forwarded_ports = vm.forwarded_ports.map {|p| "    - #{ip}:#{p[:src_port]} -> :#{p[:dst_port]}"}.join("\n")
            forwarded_ports = "  - Forwarded Ports:\n#{forwarded_ports}"
          else
            forwarded_ports = ""
          end

          puts <<-EOF
VM: #{n}
  - Disk: #{vm.disk}
  - QMP: #{vm.qmp_port}
  - VNC: vnc://#{ip}:#{vm.vnc_port}
  - Screen: http://#{ip}:#{vm.vnc_www_port}/
  - Websocket: ws://#{ip}:#{vm.vnc_websocket_port}/
  - SSH: ssh -p #{vm.ssh_port} dabo@#{ip}
#{shared_dir_info}
#{forwarded_ports}
EOF
        end
      end
    end
  end
end
