#!/usr/bin/env ruby

# Code based on: https://www.codeotaku.com/journal/2018-11/fibers-are-the-right-solution/index

require 'socket'
require 'fiber'

RESPONSE_TEXT = <<RESP.freeze
HTTP/1.1 200 OK
Content-Type: text/html
Content-Length: 3

OK
RESP

# The full implementation is given here, in order to show all the parts. A simpler implementation is given below.
class Reactor
    def initialize
        @readable = {}
        @writable = {}
    end

    def run
        while @readable.any? or @writable.any?
            readable, writable = IO.select(@readable.keys, @writable.keys, [])

            readable.each do |io|
                @readable[io].resume
            end

            writable.each do |io|
                @writable[io].resume
            end
        end
    end

    def wait_readable(io)
        @readable[io] = Fiber.current
        Fiber.yield
        @readable.delete(io)

        return yield if block_given?
    end

    def wait_writable(io)
        @writable[io] = Fiber.current

        Fiber.yield

        @writable.delete(io)

        return yield if block_given?
    end
end

server = TCPServer.new('localhost', 9090)
reactor = Reactor.new

Fiber.new do
    loop do
        client = reactor.wait_readable(server) {server.accept}
        responded = false

        Fiber.new do
            buffer = reactor.wait_readable(client) {client.gets}

            reactor.wait_writable(client) { client.puts RESPONSE_TEXT }
        end

        client.close
    end
end.resume

reactor.run
