source 'https://rubygems.org'
gem 'activesupport'
gem 'bigdecimal'
gem 'json-schema'
gem 'multi_json'
gem 'oj'
gem 'parseconfig'
gem 'rack'
gem 'rake'
gem 'rexml' # Investigate why unicorn fails to start under ruby 3 without adding rexml gem to the Gemfile
gem 'sinatra'
gem 'rackup'

github 'sinatra/sinatra' do
  gem 'sinatra-contrib'
end

gem 'request_store'
gem 'parallel'
gem 'google-protobuf', '~> 4.30.0'
gem 'net-ftp'
gem 'json-ld', '~> 3.2.0'
gem 'rdf-raptor', github:'ruby-rdf/rdf-raptor', ref: '6392ceabf71c3233b0f7f0172f662bd4a22cd534' # use version 3.3.0 when available

# Rack middleware
gem 'ffi', '~> 1.15.0'
gem 'rack-accept'
gem 'rack-attack', require: 'rack/attack'
gem 'rack-cache'
gem 'rack-cors', require: 'rack/cors'
# GitHub dependency can be removed when https://github.com/niko/rack-post-body-to-params/pull/6 is merged and released
gem 'rack-post-body-to-params', github: 'palexander/rack-post-body-to-params', branch: 'multipart_support'
gem 'rack-timeout'
gem 'redis-rack-cache'

# Data access (caching)
gem 'redis'
gem 'redis-store'

# Monitoring
gem "sentry-ruby", "~> 5.24"

# HTTP server
gem 'unicorn'
gem 'unicorn-worker-killer'

# Templating
gem 'haml', '~> 5.2.2'
gem 'rack-contrib'
gem 'pandoc-ruby'

# NCBO gems (can be from a local dev path or from rubygems/git)
gem 'ncbo_annotator', git: 'https://github.com/ontoportal-lirmm/ncbo_annotator.git', branch: 'development'
gem 'ncbo_cron', git: 'https://github.com/ontoportal-lirmm/ncbo_cron.git', branch: 'master'
gem 'ncbo_ontology_recommender', git: 'https://github.com/ontoportal-lirmm/ncbo_ontology_recommender.git', branch: 'development'
gem 'ontologies_linked_data', github: 'earthportal/ontologies_linked_data', branch: 'development'
gem 'goo', github: 'ontoportal-lirmm/goo', branch: 'development'
gem 'sparql-client', github: 'ontoportal-lirmm/sparql-client', branch: 'development'

group :development do
  # bcrypt_pbkdf and ed35519 is required for capistrano deployments when using ed25519 keys; see https://github.com/miloserdow/capistrano-deploy/issues/42
  gem 'shotgun', github: 'syphax-bouazzouni/shotgun', branch: 'master'
  gem 'rubocop'
end

group :deployment do
  # bcrypt_pbkdf and ed35519 is required for capistrano deployments when using ed25519 keys; see https://github.com/miloserdow/capistrano-deploy/issues/42
  gem 'bcrypt_pbkdf', '>= 1.0', '< 2.0', require: false
  gem 'capistrano', '~> 3', require: false
  gem 'capistrano-bundler', require: false
  gem 'capistrano-locally', require: false
  gem 'capistrano-rbenv', require: false
  gem 'ed25519', '>= 1.2', '< 2.0', require: false
end


group :profiling do
  gem 'rack-mini-profiler'
end

group :test do
  gem 'crack', '0.4.5'
  gem 'minitest'
  gem 'minitest-hooks'
  gem 'minitest-stub_any_instance'
  gem 'minitest-reporters'
  gem 'minitest-fail-fast'
  gem 'rack-test'
  gem 'simplecov', require: false
  gem 'simplecov-cobertura' # for codecov.io
  gem 'webmock'
  gem 'webrick'
end