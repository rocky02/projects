require 'minitest/autorun'
require_relative 'rate_limiter'

class RateLimiterTest < Minitest::Test
  def setup
    # Use a different Redis database for testing to avoid conflicts
    @redis_url = 'redis://localhost:6379/1'
    
    # Clear Redis database before each test
    redis = Redis.new(url: @redis_url)
    redis.flushdb
  end
  
  def test_global_rate_limit_blocking
    # Create a rate limiter with 3 requests per second
    limiter = RateLimiter.new(rate_limit: 3, granularity: :second, redis_url: @redis_url)
    
    # First 3 requests should be allowed
    assert limiter.allowed?, "First request should be allowed"
    assert limiter.allowed?, "Second request should be allowed"
    assert limiter.allowed?, "Third request should be allowed"
    
    # Fourth request should be blocked
    refute limiter.allowed?, "Fourth request should be blocked"
    
    # Wait for the rate limit window to pass
    sleep 1.1
    
    # After window passes, requests should be allowed again
    assert limiter.allowed?, "Request after window reset should be allowed"
  end
  
  def test_per_user_rate_limit_blocking
    # Create a rate limiter with 2 requests per second per user
    limiter = RateLimiter.new(rate_limit: 2, granularity: :second, redis_url: @redis_url)
    
    # User 1's first 2 requests should be allowed
    assert limiter.allowed?(entity_id: 'user_1'), "User 1's first request should be allowed"
    assert limiter.allowed?(entity_id: 'user_1'), "User 1's second request should be allowed"
    
    # User 1's third request should be blocked
    refute limiter.allowed?(entity_id: 'user_1'), "User 1's third request should be blocked"
    
    # User 2's requests should be allowed (separate limit)
    assert limiter.allowed?(entity_id: 'user_2'), "User 2's first request should be allowed"
    assert limiter.allowed?(entity_id: 'user_2'), "User 2's second request should be allowed"
    refute limiter.allowed?(entity_id: 'user_2'), "User 2's third request should be blocked"
  end
  
  def test_minute_granularity_blocking
    # Create a rate limiter with 3 requests per minute
    limiter = RateLimiter.new(rate_limit: 3, granularity: :minute, redis_url: @redis_url)
    
    # First 3 requests should be allowed
    assert limiter.allowed?, "First request should be allowed"
    assert limiter.allowed?, "Second request should be allowed"
    assert limiter.allowed?, "Third request should be allowed"
    
    # Fourth request should be blocked
    refute limiter.allowed?, "Fourth request should be blocked"
    
    # Requests should still be blocked after a short time
    sleep 2
    refute limiter.allowed?, "Request should still be blocked after 2 seconds"
  end
  
  def test_batch_allowed_blocking
    # Only run this test if the optimized version with batch_allowed? is implemented
    limiter = RateLimiter.new(rate_limit: 2, granularity: :second, redis_url: @redis_url)
    
    # Skip test if batch_allowed? method doesn't exist
    skip unless limiter.respond_to?(:batch_allowed?)
    
    # Test batch processing with multiple users
    users = ['user_1', 'user_2', 'user_3']
    
    # First batch should all be allowed
    results = limiter.batch_allowed?(users)
    assert_equal [true, true, true], results, "All first requests should be allowed"
    
    # Second batch should all be allowed
    results = limiter.batch_allowed?(users)
    assert_equal [true, true, true], results, "All second requests should be allowed"
    
    # Third batch should all be blocked
    results = limiter.batch_allowed?(users)
    assert_equal [false, false, false], results, "All third requests should be blocked"
  end
  
  def test_high_concurrency_blocking
    # Create a rate limiter with 5 requests per second
    limiter = RateLimiter.new(rate_limit: 5, granularity: :second, redis_url: @redis_url)
    
    # Simulate high concurrency with threads
    threads = []
    results = []
    mutex = Mutex.new
    
    10.times do |i|
      threads << Thread.new do
        result = limiter.allowed?
        mutex.synchronize { results << result }
      end
    end
    
    threads.each(&:join)
    
    # Should have exactly 5 allowed and 5 blocked requests
    assert_equal 5, results.count(true), "Should allow exactly 5 requests"
    assert_equal 5, results.count(false), "Should block exactly 5 requests"
  end
  
  def test_expiration_of_rate_limit_window
    # Create a rate limiter with 3 requests per second
    limiter = RateLimiter.new(rate_limit: 3, granularity: :second, redis_url: @redis_url)
    
    # Use up the rate limit
    3.times { limiter.allowed? }
    refute limiter.allowed?, "Fourth request should be blocked"
    
    # Wait for slightly more than the window
    sleep 1.1
    
    # Should be allowed again
    assert limiter.allowed?, "Request after window reset should be allowed"
    
    # Use up the new window
    2.times { limiter.allowed? }
    refute limiter.allowed?, "Fourth request in new window should be blocked"
  end
end