# frozen_string_literal: true

#
# A module for enabling caching behavior on Twirp clients.
# Extend your Twirp client with this module and set the cache and thread_pool to enable caching.
#
module TwirpCachingSupport
  attr_accessor :cache, :thread_pool

  DEFAULT_TTL = 60 # seconds

  def make_http_request(conn, service_full_name, rpc_method, content_type, req_opts, body) # rubocop:disable Metrics/ParameterLists,Metrics/CyclomaticComplexity,Metrics/PerceivedComplexity
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
      cache_control = headers ? headers.fetch('Cache-Control', '') : ''

      max_age = cache_control.match(/max-age=(\d+)/) { |m| m[1].to_i } || DEFAULT_TTL
      stale_while_revalidate = cache_control.match(/stale-while-revalidate=(\d+)/) { |m| m[1].to_i } || 0
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
