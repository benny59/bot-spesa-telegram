# spec helper for tests
require 'bundler/setup'
require 'webmock/rspec'

# load app code (adjust as necessary)
require_relative '../app/services/openfoodfacts_client'
require_relative '../app/models/product' if File.exist?(File.join(__dir__, '../app/models/product.rb'))

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.before(:each) do
    WebMock.disable_net_connect!(allow_localhost: true)
  end
end