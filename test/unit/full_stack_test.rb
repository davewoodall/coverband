# frozen_string_literal: true

require File.expand_path('../test_helper', File.dirname(__FILE__))
require 'rack'

class FullStackTest < Minitest::Test
  BASE_KEY = Coverband::Adapters::RedisStore::BASE_KEY
  TEST_RACK_APP = '../fake_app/basic_rack.rb'

  def setup
    super
    Coverband::Collectors::Coverage.instance.reset_instance
    Coverband.configure do |config|
      config.reporting_frequency = 100.0
      config.store = Coverband::Adapters::RedisStore.new(Redis.new)
      config.s3_bucket = nil
      config.background_reporting_enabled = false
    end
    Coverband.configuration.store.clear!
    Coverband.start
    @rack_file = File.expand_path(TEST_RACK_APP, File.dirname(__FILE__))
    load @rack_file
  end

  test 'call app' do
    request = Rack::MockRequest.env_for('/anything.json')
    middleware = Coverband::Middleware.new(fake_app_with_lines)
    results = middleware.call(request)
    assert_equal 'Hello Rack!', results.last
    sleep(0.1)
    expected = [nil, nil, 1, nil, 1, 1, 1, nil, nil]
    assert_equal expected, Coverband.configuration.store.coverage[@rack_file]['data']

    # additional calls increase count by 1
    middleware.call(request)
    sleep(0.1)
    expected = [nil, nil, 1, nil, 1, 1, 2, nil, nil]
    assert_equal expected, Coverband.configuration.store.coverage[@rack_file]['data']
  end

  private

  def fake_app_with_lines
    @fake_app_with_lines ||= ::HelloWorld.new
  end
end
