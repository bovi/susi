require 'socket'
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
end