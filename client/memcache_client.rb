#!/usr/bin/env ruby
# frozen_string_literal: true

require 'bundler/setup'
require 'securerandom'
require 'dalli'
require 'concurrent-ruby'

require_relative '../proto/service_twirp'
require_relative 'twirp_caching_support'
require_relative 'test_helpers'

#--------------------------------------------------------------------------------------------------
TEST_ID = SecureRandom.uuid

Example::HelloWorld::HelloWorldClient.extend(TwirpCachingSupport)
Example::HelloWorld::HelloWorldClient.cache = Dalli::Client.new(
  ENV['MEMCACHE_SERVERS'],
  namespace: 'twirp-experiment',
  compress: true
)

Example::HelloWorld::HelloWorldClient.thread_pool = Concurrent::ThreadPoolExecutor.new(
  min_threads: 1,
  max_threads: 10,
  max_queue: 100,
  fallback_policy: :discard # discard revalidation tasks if the queue is full
)

CLIENT = Example::HelloWorld::HelloWorldClient.new('http://localhost:3001/twirp')

def hello(name, headers: {})
  headers['x-request-id'] = SecureRandom.uuid

  puts "  - RPC (#{name}) with headers: #{headers.inspect}"
  resp = CLIENT.hello({ name: "#{name} (#{TEST_ID})" }, { headers: })
  raise StandardError, resp.error if resp.error

  puts "  - Response: #{resp.data.message.inspect} (cache: #{resp.headers['X-Cache']}, age: #{resp.headers['age']})"
  resp.data.message
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

print '* Sleeping for 1 second to allow the cache to be updated...'
sleep_with_progress(1)

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
begin
  hello('error world', headers:)
rescue StandardError => e
  puts "+ OK: Received expected error: #{e.inspect}"
end

puts '--------------------------------------------------------------------------'
puts 'All tests passed!'
