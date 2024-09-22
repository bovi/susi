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
      puts port
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
        puts "Connected to QMP socket"
      else
        puts "Failed to connect to QMP socket"
        exit 1
      end
    end

    def name
      @server.puts('{"execute":"query-name"}')
      resp = JSON.parse(@server.gets)
      resp["return"]["name"]
    end

    def quit
      @server.puts('{"execute":"quit"}')
    end
  end

  class VM
    def initialize(name)
      @name = name
      @qmp_port = nil

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
      QMP.new(@qmp_port).quit
    end

    def vnc_port
      5900
    end

    def vnc_www_port
      5800
    end

    def vnc_websocket_port
      5700
    end

    def ssh_port
      @ssh_port
    end

    def self.quit(name)
      q = QMP.new(4444)
      q.quit
    end

    def self.install(name, disk, iso)
      self.start(name, disk, cdrom: iso)
    end

    def self.start(name, disk, cdrom: nil)
      cmd = []

      cmd << "~/susi/docs/qemu/build/qemu-system-x86_64"

      # general setup
      cmd << "-name #{name}"
      cmd << "-m 2048"
      cmd << "-hda #{disk}.qcow2"
      cmd << "-daemonize"
      cmd << "-enable-kvm"

      # control interfaces
      cmd << "-qmp tcp:localhost:4444,server,nowait"
      cmd << "-vnc :0,websocket=on"

      # Network capabilities
      cmd << "-nic user,model=virtio-net-pci,hostfwd=tcp::2222-:22"

      # cdrom for installation
      if cdrom
        cmd << "-cdrom #{cdrom}"
      end

      puts cmd.join(" ")
      system(cmd.join(" "))

      QMP.new(4444)
    end

    def self.ls
      ps = `ps aux | grep qemu-system-x86_64`
      ps.split("\n").each do |line|
        next unless line.match /\-name/
        m = line.match(/-name (\w+)/)
        n = m[1]
        m = line.match(/-hda (.*?)\s/)
        d = m[1]
        m = line.match(/-qmp tcp:localhost:(\d+)/)
        q = m[1]
        m = line.match(/-vnc :(\d+)/)
        v = m[1].to_i

        # get local device name or IP
        ip = Socket.ip_address_list.find { |ai| ai.ipv4? && !ai.ipv4_loopback? }
        puts ip.inspect

        # get mapped ports
        port_mappings = []
        line.scan(/-nic user,model=virtio-net-pci,hostfwd=tcp::(\d+)-:(\d+)/) do |host_port, guest_port|
          if guest_port == '22'
            port_mappings << "  - SSH: ssh -p #{host_port} dabo@#{ip.ip_address}"
          else
            port_mappings << "  - TCP: tcp://#{ip.ip_address}:#{host_port}"
          end
        end

        puts <<-EOF
#{n}
  - Disk: #{d}
  - QMP: :#{q}
  - VNC: :#{5900 + v} 
  - Screen: http://#{ip.ip_address}:#{5800 + v}/
#{port_mappings.join("\n")}
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







































































