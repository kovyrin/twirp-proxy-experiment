#!/usr/bin/env ruby
# frozen_string_literal: true

require 'bundler/setup'
require_relative '../proto/service_twirp'
require 'securerandom'

# Call the API via a local proxy
CLIENT = Example::HelloWorld::HelloWorldClient.new('http://localhost:3002/twirp')
TEST_ID = SecureRandom.uuid

def hello(name, headers: {})
  headers['x-request-id'] = SecureRandom.uuid

  puts "  - RPC (#{name}) with headers: #{headers.inspect}"
  resp = CLIENT.hello({ name: "#{name} (#{TEST_ID})" }, { headers: })
  raise StandardError, resp.error if resp.error

  puts "  - Response: #{resp.data.message.inspect} (cache: #{resp.headers['X-Cache']}, age: #{resp.headers['age']})"
  resp.data.message
end

def assert_equal(res1, res2)
  if res1 == res2
    puts "+ OK: Results match (#{res1.inspect})"
  else
    puts "ERROR! Results do not match! (#{res1.inspect} != #{res2.inspect})"
    exit(1)
  end
  puts
end

def refute_equal(res1, res2)
  if res1 != res2
    puts "+ OK: Results do not match (#{res1.inspect} != #{res2.inspect})"
  else
    puts "ERROR! Results match! (#{res1.inspect})"
    exit(1)
  end
  puts
end

def sleep_with_progress(seconds)
  seconds.times do
    print '.'
    sleep(1)
  end
  puts
end

puts '--------------------------------------------------------------------------'
puts 'Simple Twirp Client call testing:'
puts '* Making the first call to the server'
result1 = hello('Simple World')

puts '* Making the second call to the server (results should be the same since it is served from the cache)'
result2 = hello('Simple World')
assert_equal(result1, result2)

puts '--------------------------------------------------------------------------'
puts 'Twirp Client call with forced refresh:'
headers = { 'Cache-Control' => 'no-cache' }
puts '* Making the first call to the server'
result1 = hello('Refresh World', headers:)

puts '* Making the second call to the server (results should be different since it is not served from the cache)'
result2 = hello('Refresh World', headers:)
refute_equal(result1, result2)

puts '--------------------------------------------------------------------------'
puts 'Twirp Client call with a custom TTL:'
puts '* Making the first call to the server'
headers = { 'Cache-Control' => 'max-age=2' }
result1 = hello('TTL World', headers:)

puts '* Making the second call to the server (results should be the same since it is served from the cache)'
result2 = hello('TTL World', headers:)
assert_equal(result1, result2)

print '* Sleeping for 3 seconds to allow the cache to expire...'
sleep_with_progress(3)

puts '* Making the third call to the server (results should be different since the cache has expired)'
result3 = hello('TTL World', headers:)
refute_equal(result1, result3)

puts '--------------------------------------------------------------------------'
puts 'Twirp Client call with a custom TTL and forced refresh:'
puts '* Making the first call to the server'
result1 = hello('TTL Refresh World', headers: { 'Cache-Control' => 'max-age=2' })

puts '* Making the second call to the server (results should be the same since it is served from the cache)'
result2 = hello('TTL Refresh World', headers: { 'Cache-Control' => 'max-age=2' })
assert_equal(result1, result2)

puts '* Making the third call to the server (results should be different since we are forcing a refresh)'
result3 = hello('TTL Refresh World', headers: { 'Cache-Control' => 'no-cache' })
refute_equal(result1, result3)

puts '* Making the fourth call to the server (results should be the same as the third call since it is served from the cache)'
result4 = hello('TTL Refresh World')
assert_equal(result3, result4)

puts '--------------------------------------------------------------------------'
puts 'Twirp Client call with a custom TTL and stale-while-revalidate:'
puts '* Making the first call to the server'
headers = { 'Cache-Control' => 'max-age=2, stale-while-revalidate=2' }
result1 = hello('SWR World', headers:)

puts '* Making the second call to the server (results should be the same since it is served from the cache)'
result2 = hello('SWR World', headers:)
assert_equal(result1, result2)

print '* Sleeping for 3 seconds to allow the cache to expire...'
sleep_with_progress(3)

puts '* Making the third call to the server (results should be the same since it is served from the cache)'
result3 = hello('SWR World', headers:)
assert_equal(result1, result3)

puts '* Making the fourth call to the server (results should be different since the cache has been updated in the background)'
result4 = hello('SWR World', headers:)
refute_equal(result1, result4)

puts '--------------------------------------------------------------------------'
puts 'Twirp Client call with stale-if-error:'
puts '* Making the first call to the server (it will succeed)'
headers = { 'Cache-Control' => 'max-age=2, stale-if-error=2' }
result1 = hello('error world', headers:)

puts '* Making the second call to the server (results should be the same since it is served from the cache)'
result2 = hello('error world', headers:)
assert_equal(result1, result2)

print '* Sleeping for 3 seconds to allow the cache to expire...'
sleep_with_progress(3)

puts '* Making the third call to the server (it will fail on the backend, but still work from the cache)'
result3 = hello('error world', headers:)
assert_equal(result1, result3)

print '* Sleeping for 3 seconds to allow the error grace period to pass...'
sleep_with_progress(3)

puts '* Making the fourth call to the server (it will fail on the backend and return an error since the grace period has passed)'
hello('error world', headers:)

puts '--------------------------------------------------------------------------'
puts 'All tests passed!'
