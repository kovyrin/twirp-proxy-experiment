#!/usr/bin/env ruby
# frozen_string_literal: true

require 'bundler/setup'
require 'securerandom'
require 'dalli'
require 'pry'
require 'concurrent-ruby'

require_relative '../proto/service_twirp'

# A class that behaves like the HelloWorldClient, but with support for caching responses in Memcache
class CachedHelloWorldClient < ::Twirp::Client
  client_for Example::HelloWorld::HelloWorldService
  class << self
    attr_accessor :cache, :thread_pool

    DEFAULT_TTL = 60 # seconds

    def make_http_request(conn, service_full_name, rpc_method, content_type, req_opts, body) # rubocop:disable Metrics/ParameterLists
      cache_key = cache_key_for(service_full_name, rpc_method, body)

      cache_control = CacheControl.parse_headers(req_opts[:headers])
      cache_ttl = cache_control.max_cache_ttl

      now = Time.now.to_i

      cache_hit = nil
      cas_token = nil
      unless cache_control.no_cache
        cache_hit, cas_token = cache.get_cas(cache_key)

        # The cache is still fresh, return the cached response
        if cache_control.serve_cached_response?(cache_hit, now)
          return cached_response(cache_hit, now)
        end
      end

      # The cache is stale, but we can return a stale response while revalidating in a background
      # thread if the cache control allows it.
      if cache_hit && cache_control.stale_while_revalidate.positive?
        # Revalidate the cache in the background
        thread_pool.post do
          response = super
          if response.success?
            cache_response(response, cache_key, cache_ttl, cas_token)
          end
        end

        # Return the stale cached response if we are still within the stale-while-revalidate grace period
        if cache_control.serve_stale_while_revalidate?(cache_hit, now)
          return cached_response(cache_hit, now)
        end
      end

      # The cache is either empty or expired, make the request to the upstream service
      response = super

      if response.success?
        # The request was successful, cache the response unless specifically asked not to
        unless cache_control.no_store
          cache_response(response, cache_key, cache_ttl, cas_token)
        end
      else
        # The request failed, check if we can return a stale response
        if cache_control.serve_stale_on_error?(cache_hit, now)
          # Return the stale cached response if the backend request failed and
          # we are still within the stale-if-error grace period
          return cached_response(cache_hit, now)
        end
      end

      uncached_response(response)
    end

    CacheControl = Data.define(:max_age, :stale_while_revalidate, :stale_if_error, :no_cache, :no_store) do
      def self.parse_headers(headers)
        cache_control = headers&.[]('Cache-Control') || ''

        max_age = cache_control.match(/max-age=(\d+)/) { |m| m[1].to_i } || DEFAULT_TTL
        stale_while_revalidate = cache_control.match(/stale-while-revalidate=(\d+)/) do |m|
          m[1].to_i
        end || 0
        stale_if_error = cache_control.match(/stale-if-error=(\d+)/) { |m| m[1].to_i } || 0
        no_cache = cache_control.include?('no-cache')
        no_store = cache_control.include?('no-store')

        new(
          max_age:,
          stale_while_revalidate:,
          stale_if_error:,
          no_cache:,
          no_store:
        )
      end

      # Cache the response with a TTL of max_age + a grace period to allow
      # for stale responses to be served while the cache is being revalidated.
      def max_cache_ttl
        grace_period = if stale_while_revalidate > stale_if_error
                         stale_while_revalidate
                       else
                         stale_if_error
                       end
        max_age + grace_period
      end

      def serve_cached_response?(cache_hit, now)
        cache_hit && cache_hit[:cached_at] + max_age >= now
      end

      def serve_stale_while_revalidate?(cache_hit, now)
        return false unless cache_hit && stale_while_revalidate.positive?

        cache_hit[:cached_at] + max_age + stale_while_revalidate >= now
      end

      def serve_stale_on_error?(cache_hit, now)
        return false unless cache_hit && stale_if_error.positive?

        cache_hit[:cached_at] + max_age + stale_if_error >= now
      end
    end

    def cache_key_for(service_full_name, rpc_method, body)
      "#{service_full_name}/#{rpc_method}/#{Digest::SHA256.hexdigest(body)}"
    end

    def cached_response(cache_response, now)
      response = cache_response[:response]
      cached_at = cache_response[:cached_at]

      response.headers['X-Cache'] = 'HIT'
      response.headers['Age'] = now - cached_at

      response
    end

    def uncached_response(response)
      response.headers['X-Cache'] = 'MISS'
      response.headers['Age'] = 0
      response
    end

    def cache_response(response, cache_key, cache_ttl, cas_token)
      cas_token ||= 0 # default value for first time cache writes
      cache_value = {
        response:,
        cached_at: Time.now.to_i
      }
      # CAS ensures we do not overwrite a newer cache entry
      cache.set_cas(cache_key, cache_value, cas_token, cache_ttl)
    end
  end
end

#--------------------------------------------------------------------------------------------------
TEST_ID = SecureRandom.uuid

CachedHelloWorldClient.cache = Dalli::Client.new(
  ENV['MEMCACHE_SERVERS'],
  namespace: 'twirp-experiment',
  compress: true
)

CachedHelloWorldClient.thread_pool = Concurrent::ThreadPoolExecutor.new(
  min_threads: 1,
  max_threads: 10,
  max_queue: 100,
  fallback_policy: :discard # discard revalidation tasks if the queue is full
)

CLIENT = CachedHelloWorldClient.new('http://localhost:3001/twirp')

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
