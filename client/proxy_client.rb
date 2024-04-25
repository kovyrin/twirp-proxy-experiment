#!/usr/bin/env ruby
# frozen_string_literal: true

require 'bundler/setup'
require_relative '../proto/service_twirp.rb'

# Call the API via a local proxy
c = Example::HelloWorld::HelloWorldClient.new("http://localhost:3002/twirp")

resp = c.hello({name: "World"})
if resp.error
  puts resp.error
else
  puts resp.data.message
end
