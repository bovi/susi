#!/usr/bin/env ruby

require 'test/unit'
require 'socket'
require 'timeout'
require 'json'
require 'webrick'
require 'open-uri'

module Susi
  class SSH
    def self.open(name)
      vm = VM.new(name)
      port = vm.ssh_port
      ip = Socket.ip_address_list.find { |ai| ai.ipv4? && !ai.ipv4_loopback? }
      exec "ssh -p #{port} dabo@#{ip.ip_address}"
    end
  end

  class VNC
    def self.open(name)
      vm = VM.new(name)
      port = vm.vnc_www_port
      ip = Socket.ip_address_list.find { |ai| ai.ipv4? && !ai.ipv4_loopback? }
      token = (0...8).map { (65 + rand(26)).chr }.join
      url = "http://#{ip.ip_address}:#{port}/#{token}.html"

      # prepare paths and files
      path = File.expand_path(File.dirname(__FILE__))
      novnc_path = File.join(path, "novnc")
      html = File.read(File.join(novnc_path, "screen.html"))
      html.gsub!("###TOKEN###", token)
      html.gsub!("###HOST###", ip.ip_address)
      html.gsub!("###PORT###", vm.vnc_websocket_port.to_s)

      server = WEBrick::HTTPServer.new(:Port => port,
                                       :Logger => WEBrick::Log.new("/dev/null"),
                                       :AccessLog => [])
      server.mount_proc "/#{token}.html" do |req, res|
        # print access by someone on command line
        puts "[#{Time.now}] Access by: #{req.peeraddr[3]}"
        res.body = html
      end
      server.mount_proc "/#{token}.close.html" do |req, res|
        puts "[#{Time.now}] Closing VNC..."
        res.body = "Closing VNC..."
        server.shutdown
      end
      server.mount("/core",
                   WEBrick::HTTPServlet::FileHandler,
                   File.join(novnc_path, "core"))
      server.mount("/vendor",
                   WEBrick::HTTPServlet::FileHandler,
                   File.join(novnc_path, "vendor"))

      puts "[#{Time.now}] VNC screen: #{url}"

      server.start
    end
  end

  class Disk
    DEFAULT_IMG = "debian-12.7.0-amd64-netinst.iso"

    def self.download_debian_netinstall
      # Check if ~/.susi directory exists, if not create it
      susi_dir = File.expand_path("~/.susi")
      Dir.mkdir(susi_dir) unless Dir.exist?(susi_dir)

      # Check if ~/.susi/iso directory exists, if not create it
      iso_dir = File.join(susi_dir, "iso")
      Dir.mkdir(iso_dir) unless Dir.exist?(iso_dir)

      # Set the output path to be in the iso directory
      output_path = File.join(iso_dir, DEFAULT_IMG)

      url = "https://mirrors.tuna.tsinghua.edu.cn/debian-cd/current/amd64/iso-cd/#{DEFAULT_IMG}"
      
      puts "Downloading Debian netinstall ISO..."
      
      begin
        URI.open(url) do |remote_file|
          File.open(output_path, "wb") do |local_file|
            local_file.write(remote_file.read)
          end
        end
        puts "Download completed successfully."
      rescue OpenURI::HTTPError => e
        puts "Error downloading the ISO: #{e.message}"
      rescue SocketError => e
        puts "Network error: #{e.message}"
      rescue => e
        puts "An unexpected error occurred: #{e.message}"
      end
    end

    def self.create(name, size)
      system("qemu-img create -f qcow2 #{name}.qcow2 #{size}G > /dev/null 2>&1")
    end

    def self.clone(name, clone)
      system("qemu-img create -f qcow2 -F qcow2 -b #{name}.qcow2 #{clone}.qcow2 > /dev/null 2>&1")
    end
  end

  class QMP
    def initialize(port)
      @port = port
      @server = TCPSocket.new('localhost', @port)

      resp = JSON.parse(@server.gets)
      if resp["QMP"]["version"]["qemu"]["major"] == 9
        #puts "QEMU version 9 detected"
      else
        puts "QEMU version not supported"
        exit 1
      end

      @server.puts('{"execute":"qmp_capabilities"}')
      resp = JSON.parse(@server.gets)
      if resp["return"] == {}
        #puts "Connected to QMP socket"
      else
        puts "Failed to connect to QMP socket"
        exit 1
      end

      if block_given?
        yield(self)
        self.close
      end
    end

    def execute(cmd)
      @server.puts(JSON.dump({"execute" => cmd}))
      resp = JSON.parse(@server.gets)
      resp["return"]
    end

    def execute_with_args(cmd, args)
      @server.puts(JSON.dump({"execute" => cmd, "arguments" => args}))
      resp = JSON.parse(@server.gets)
      resp["return"]
    end

    def name
      @server.puts('{"execute":"query-name"}')
      resp = JSON.parse(@server.gets)
      resp["return"]["name"]
    end

    def quit
      @server.puts('{"execute":"quit"}')
    end

    def close
      @server.close
    end
  end

  class VM
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

      cmd << "~/susi/docs/qemu/build/qemu-system-x86_64"

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

      QMP.new(qmp_port)
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

# perform a test when the script is run
if __FILE__ == $0
  class SusiTest < Test::Unit::TestCase
    def run_command(cmd)
      system("#{cmd} > /dev/null 2>&1")
    end

    def test_cli_empty
      assert_equal(false, run_command("ruby ./susi.rb"))
    end

    def test_create_img
      Susi::Disk.create("test", "1")

      # check created file
      assert(File.exist?("test.qcow2"))
      info = `qemu-img info test.qcow2`
      assert(info.include?("virtual size: 1 GiB"))
      assert(info.include?("format: qcow2"))

      run_command("rm test.qcow2")
    end

    def test_cli_create_img
      assert_equal(true, run_command("ruby ./susi.rb disk create test 1"))
      assert(File.exist?("test.qcow2"))
      run_command("rm test.qcow2")
    end

    def test_cli_create_img_fail
      assert_equal(false, run_command("ruby ./susi.rb disk create test"))
      assert_equal(false, run_command("ruby ./susi.rb disk create test pest"))
      assert_equal(false, run_command("ruby ./susi.rb disk create 1"))
    end

    def test_clone_img
      Susi::Disk.create("test", "1")
      Susi::Disk.clone("test", "clone")

      assert(File.exist?("clone.qcow2"))
      info = `qemu-img info clone.qcow2`
      assert(info.include?("virtual size: 1 GiB"))
      assert(info.include?("format: qcow2"))
      assert(info.include?("backing file: test.qcow2"))
      assert(info.include?("backing file format: qcow2"))

      run_command("rm clone.qcow2")
      run_command("rm test.qcow2")
    end

    def test_cli_clone_img
      assert_equal(true, run_command("ruby ./susi.rb disk create test 1"))
      assert_equal(true, run_command("ruby ./susi.rb disk clone test clone"))
      assert(File.exist?("clone.qcow2"))
      run_command("rm clone.qcow2")
      run_command("rm test.qcow2")
    end

    def test_cli_clone_img_fail
      assert_equal(false, run_command("ruby ./susi.rb disk clone test clone"))
      assert_equal(true, run_command("ruby ./susi.rb disk create test 1"))
      assert_equal(false, run_command("ruby ./susi.rb disk clone test"))
      assert_equal(true, run_command("ruby ./susi.rb disk clone test clone"))
      assert_equal(false, run_command("ruby ./susi.rb disk clone test clone"))

      run_command("rm clone.qcow2")
      run_command("rm test.qcow2")
    end
  end
end







































































