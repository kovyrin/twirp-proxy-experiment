#!/usr/bin/env ruby
# frozen_string_literal: true

require 'bundler/setup'
require_relative '../proto/service_twirp.rb'

# Assume hello_world_server is running locally
c = Example::HelloWorld::HelloWorldClient.new("http://localhost:3001/twirp")

resp = c.hello({name: "World"})
if resp.error
  puts resp.error
else
  puts resp.data.message
end
