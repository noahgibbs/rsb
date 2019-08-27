#!/usr/bin/env ruby
# From: https://blog.appsignal.com/2016/11/23/ruby-magic-building-a-30-line-http-server-in-ruby.html

require 'socket'
server = TCPServer.new 9090

MESSAGE=<<MSG.freeze
HTTP/1.1 200 OK
Content-Type: text/html
Content-Length: 3

OK
MSG

while session = server.accept
  session.puts MESSAGE
  session.close
end
