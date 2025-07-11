require 'socket'
require 'json'

require_relative 'output'

module Susi
  class QMP
    def initialize(port)
      Susi::debug "Connecting to QMP on port #{port}"

      @port = port
      @server = TCPSocket.new('localhost', @port)

      Susi::debug "QMP connected"

      resp = JSON.parse(@server.gets)
      unless resp["QMP"]["version"]["qemu"]["major"] >= 9
        @server.close
        raise "QEMU version not supported"
      end

      # handshake to initialize QMP
      @server.puts('{"execute":"qmp_capabilities"}')
      resp = JSON.parse(@server.gets)
      unless resp["return"] == {}
        @server.close
        raise "Failed to connect to QMP socket"
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
      close
    end

    def close
      Susi::debug "Closing QMP connection"
      @server.close
    end
  end
end
