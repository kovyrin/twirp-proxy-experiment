# frozen_string_literal: true

source 'https://rubygems.org'

# Rack 3 is not compatible with Twirp ruby
gem 'concurrent-ruby'
gem 'dalli'
gem 'pry'
gem 'rack', '~> 2.0'
gem 'twirp', git: 'https://github.com/kovyrin/twirp-ruby.git', branch: 'kovyrin/expose-response-headers'
gem 'webrick'

group :development do
  gem 'rubocop', require: false
end
