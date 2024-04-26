#!/usr/bin/env ruby
# frozen_string_literal: true

require 'bundler/setup'
require_relative '../proto/service_twirp.rb'

# Call the API via a local proxy
CLIENT = Example::HelloWorld::HelloWorldClient.new("http://localhost:3002/twirp")

def hello(name, headers: nil)
  request_options = nil
  request_options = { headers: } if headers

  resp = CLIENT.hello({ name: name }, request_options)
  if resp.error
    puts resp.error
  else
    puts resp.data.message
  end
end

# puts "Simple Twirp Client call:"
# hello("Simple World")
# puts "--------------------------"

puts "Twirp Client call with a custom TTL:"
hello("TTL World", headers: { "Cache-Control" => "max-age=60" })
puts "--------------------------"

# puts "Twirp Client call with forced refresh:"
# hello("Refresh World", headers: { "Cache-Control" => "no-cache" })
# puts "--------------------------"
