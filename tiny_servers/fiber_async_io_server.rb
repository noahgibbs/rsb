#!/usr/bin/env ruby

require 'async'
require 'async/io/tcp_socket'

RESPONSE_TEXT = <<RESP.freeze
HTTP/1.1 200 OK
Content-Type: text/html

Yes, we are OK
RESP

Async do |task|
    server = Async::IO::TCPServer.new('localhost', 9090)

    loop do
        client, address = server.accept
        task.async do
            while buffer = client.gets
                client.puts(RESPONSE_TEXT)
            end

            client.close
        end
    end
end
