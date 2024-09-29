require 'socket'
require 'webrick'

require_relative 'output'

module Susi
  class VNC
    def self.open(name)
      VM.new(name) do |vm|
        port = vm.vnc_www_port
        token = (0...8).map { (65 + rand(26)).chr }.join
        url = "http://#{vm.ip}:#{port}/#{token}.html"
        Susi::info "VNC: #{url}"

        # prepare paths and files
        path = File.expand_path(File.dirname(__FILE__))
        novnc_path = File.join(path, "novnc")
        html = File.read(File.join(novnc_path, "screen.html"))
        html.gsub!("###TOKEN###", token)
        html.gsub!("###HOST###", vm.ip)
        html.gsub!("###PORT###", vm.vnc_websocket_port.to_s)

        server = WEBrick::HTTPServer.new(:Port => port,
                                       :Logger => WEBrick::Log.new("/dev/null"),
                                       :AccessLog => [])
        server.mount_proc "/#{token}.html" do |req, res|
          # print access by someone on command line
          Susi.info "[#{Time.now}] Access by: #{req.peeraddr[3]}"
          res.body = html
        end
        server.mount_proc "/#{token}.close.html" do |req, res|
          Susi.info "[#{Time.now}] Closing by #{req.peeraddr[3]}"
          res.body = "Closing VNC..."
          server.shutdown
        end
        server.mount("/core",
                     WEBrick::HTTPServlet::FileHandler,
                     File.join(novnc_path, "core"))
        server.mount("/vendor",
                     WEBrick::HTTPServlet::FileHandler,
                     File.join(novnc_path, "vendor"))

        Susi::debug "[#{Time.now}] VNC screen: #{url}"

        server.start
      end
    end
  end
end