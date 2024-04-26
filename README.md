# Experiments with running Twirp API requests through an HTTP proxy.

The idea is to allow Twirp clients to make requests through a Varnish cache while making
it possible for the clients to control caching policies per request. Specific policies we want to support:

* `max-age` - The maximum time a response can be cached.
* `stale-while-revalidate` - The maximum time a stale response can be served while a new one is being fetched.
* `no-cache` - Forced revalidation of the response.
* `no-store` - Do not cache the response.

## Running the example

1. Prepare the environment:
```
dev clone shopify/twirp-proxy-experiment
dev up
```

1. Start the server (in a separate terminal):

```
dev cd shopify/twirp-proxy-experiment
dev server
```

3. Start the proxy (in a separate terminal):

```
dev cd shopify/twirp-proxy-experiment
dev proxy
```

4. Run the simple client with direct connection to the server:

```
dev cd shopify/twirp-proxy-experiment
dev client
```

5. Run the simple client with connection through the proxy:

```
def cd shopify/twirp-proxy-experiment
dev proxy-client
```

## Dev Setup

```
bundle install
brew install grpc
go install github.com/arthurnn/twirp-ruby/protoc-gen-twirp_ruby@latest
```

Generate the ruby files:

```
export PATH=$PATH:~/go/bin
protoc --proto_path=. proto/service.proto --ruby_out=. --twirp_ruby_out=.
```
