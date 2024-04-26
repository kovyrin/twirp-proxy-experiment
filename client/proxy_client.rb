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
  raise resp.error if resp.error

  resp.data.message
end

def assert_equal(res1, res2)
  if res1 == res2
    puts "+ Results match! (#{res1.inspect})"
  else
    puts "ERROR! Results do not match! (#{res1.inspect} != #{res2.inspect})"
    exit(1)
  end
end

def refute_equal(res1, res2)
  if res1 != res2
    puts "+ Results do not match! (#{res1.inspect} != #{res2.inspect})"
  else
    puts "ERROR! Results match! (#{res1.inspect})"
    exit(1)
  end
end

puts "--------------------------------------------------------------------------"
puts "Simple Twirp Client call testing:"
puts "* Making the first call to the server"
result1 = hello("Simple World")

puts "* Making the second call to the server (results should be the same since it is served from the cache)"
result2 = hello("Simple World")
assert_equal(result1, result2)

puts "--------------------------------------------------------------------------"
puts "Twirp Client call with forced refresh:"
headers = { "Cache-Control" => "no-cache" }
puts "* Making the first call to the server"
result1 = hello("Refresh World", headers:)

puts "* Making the second call to the server (results should be different since it is not served from the cache)"
result2 = hello("Refresh World", headers:)
refute_equal(result1, result2)

puts "--------------------------------------------------------------------------"
puts "Twirp Client call with a custom TTL:"
puts "* Making the first call to the server"
headers = { "Cache-Control" => "max-age=2" }
result1 = hello("TTL World", headers:)

puts "* Making the second call to the server (results should be the same since it is served from the cache)"
result2 = hello("TTL World", headers:)
assert_equal(result1, result2)

puts "* Sleeping for 3 seconds to allow the cache to expire..."
3.times do
  sleep(1)
  print "."
end
puts "Done!"

puts "* Making the third call to the server (results should be different since the cache has expired)"
result3 = hello("TTL World", headers:)
refute_equal(result1, result3)
