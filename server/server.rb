#!/usr/bin/env ruby
# frozen_string_literal: true

require 'bundler/setup'
require 'rack'
require 'webrick'

require_relative '../proto/service_twirp.rb'

# Service implementation
class HelloWorldHandler
  def hello(req, env)
    @error_requests ||= {}

    # For requests with "error" in the name, serve the first response correctly, then return an error
    # on all subsequent requests (to test error handling in the client)
    if req.name.include?("error")
      if @error_requests[req.name]
        puts ">> Erroring on request #{req.name}"
        return Twirp::Error.new(:unavailable, "Error on request #{req.name}")
      end

      @error_requests[req.name] = true
    end

    puts ">> Hello #{req.name}"
    {
      message: "Hello #{req.name} on #{Time.now.to_f}"
    }
  end
end

# Instantiate Service
handler = HelloWorldHandler.new()
service = Example::HelloWorld::HelloWorldService.new(handler)

# Start the web server and mount the service
path_prefix = "/twirp/" + service.full_name
puts "Mounting service at #{path_prefix}"
server = WEBrick::HTTPServer.new(Port: 3001)
server.mount(path_prefix, Rack::Handler::WEBrick, service)
server.start
