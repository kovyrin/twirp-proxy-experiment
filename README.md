Experiments with running Twirp API requests through an HTTP proxy.

# Setup

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
