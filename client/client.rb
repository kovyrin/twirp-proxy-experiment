#!/usr/bin/env ruby
# frozen_string_literal: true

require 'bundler/setup'
require_relative '../proto/service_twirp'

# Assume hello_world_server is running locally
c = Example::HelloWorld::HelloWorldClient.new('http://localhost:3001/twirp')

puts "Calling the server with name = 'World'..."
resp = c.hello({ name: 'World' })

if resp.error
  puts "ERROR: #{resp.error}"
  exit(1)
end

puts "Response: #{resp.data.message}"
