# Code generated by protoc-gen-twirp_ruby 1.11.0, DO NOT EDIT.
require 'twirp'
require_relative 'service_pb.rb'

module Example
  module HelloWorld
    class HelloWorldService < ::Twirp::Service
      package 'example.hello_world'
      service 'HelloWorld'
      rpc :Hello, HelloRequest, HelloResponse, :ruby_method => :hello
    end

    class HelloWorldClient < ::Twirp::Client
      client_for HelloWorldService
    end
  end
end
