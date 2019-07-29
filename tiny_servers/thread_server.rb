#!/usr/bin/env ruby

# Code from: https://www.codeotaku.com/journal/2018-11/fibers-are-the-right-solution/index

require 'socket'

RESPONSE_TEXT = <<RESP.freeze
HTTP/1.1 200 OK
Content-Type: text/html

Yes, we are OK
RESP

server = TCPServer.new('localhost', 9090)

loop do
    client = server.accept

    Thread.new do
        while buffer = client.gets
            client.puts(RESPONSE_TEXT)
        end

        client.close
    end
end
