require 'socket'
require 'json'

module Susi
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
end