#!/usr/bin/env ruby

# Code initially based on: https://www.codeotaku.com/journal/2018-11/fibers-are-the-right-solution/index

require 'socket'

RESPONSE_TEXT = <<RESP.freeze
HTTP/1.1 200 OK
Content-Type: text/html
Content-Length: 3

OK
RESP

server = TCPServer.new('localhost', 9090)

loop do
    client = server.accept

    Thread.new do
        client.puts RESPONSE_TEXT
        client.close
    end
end
