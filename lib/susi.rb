#!/usr/bin/env ruby

require 'test/unit'
require 'socket'
require 'timeout'
require 'json'
require 'webrick'

module Susi
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
    def self.create(name, size)
      system("qemu-img create -f qcow2 #{name}.qcow2 #{size}G")
    end

    def self.clone(name, clone)
      system("qemu-img create -f qcow2 -F qcow2 -b #{name}.qcow2 #{clone}.qcow2")
    end
  end

  class QMP
    def initialize(port)
      @port = port
      @server = TCPSocket.new('localhost', @port)

      resp = JSON.parse(@server.gets)
      if resp["QMP"]["version"]["qemu"]["major"] == 9
        puts "QEMU version 9 detected"
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

      #@qmp = QMP.new(@qmp_port)
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

    def self.quit(name)
      q = QMP.new(4444)
      q.quit
    end

    def self.install(name, disk, iso)
      self.start(name, disk, cdrom: iso)
    end

    def self.start(name, disk, cdrom: nil)
      cmd = []

      cmd << "qemu-system-x86_64"
      cmd << "-name #{name}"
      cmd << "-hda #{disk}.qcow2"
      cmd << "-daemonize"
      cmd << "-qmp tcp:localhost:4444,server,nowait"
      cmd << "-vnc :0,websocket=on"

      if cdrom
        cmd << "-cdrom #{cdrom}"
      end

      puts cmd.join(" ")
      system(cmd.join(" "))

      QMP.new(4444)
    end

    def self.ls
      # grep from ps output
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

        puts <<-EOF
#{n}
  - Disk: #{d}
  - QMP: :#{q}
  - VNC: :#{5900 + v} (Websocket: #{5700 + v})
  - Screen: http://#{ip.ip_address}:#{5800 + v}/
EOF
      end
    end
  end
end

# perform a test when the script is run
if __FILE__ == $0
  class SusiTest < Test::Unit::TestCase
    def test_cli_empty
      assert_equal(false, system("ruby ./susi.rb"))
    end

    def test_create_img
      Susi::Disk.create("test", "1")

      # check created file
      assert(File.exist?("test.qcow2"))
      info = `qemu-img info test.qcow2`
      assert(info.include?("virtual size: 1 GiB"))
      assert(info.include?("format: qcow2"))

      system("rm test.qcow2")
    end

    def test_cli_create_img
      assert_equal(true, system("ruby ./susi.rb disk create test 1"))
      assert(File.exist?("test.qcow2"))
      system("rm test.qcow2")
    end

    def test_cli_create_img_fail
      assert_equal(false, system("ruby ./susi.rb disk create test"))
      assert_equal(false, system("ruby ./susi.rb disk create test pest"))
      assert_equal(false, system("ruby ./susi.rb disk create 1"))
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

      system("rm clone.qcow2")
      system("rm test.qcow2")
    end

    def test_cli_clone_img
      assert_equal(true, system("ruby ./susi.rb disk create test 1"))
      assert_equal(true, system("ruby ./susi.rb disk clone test clone"))
      assert(File.exist?("clone.qcow2"))
      system("rm clone.qcow2")
      system("rm test.qcow2")
    end

    def test_cli_clone_img_fail
      assert_equal(false, system("ruby ./susi.rb disk clone test clone"))
      assert_equal(true, system("ruby ./susi.rb disk create test 1"))
      assert_equal(false, system("ruby ./susi.rb disk clone test"))
      assert_equal(true, system("ruby ./susi.rb disk clone test clone"))
      assert_equal(false, system("ruby ./susi.rb disk clone test clone"))

      system("rm clone.qcow2")
      system("rm test.qcow2")
    end
  end
end







































































