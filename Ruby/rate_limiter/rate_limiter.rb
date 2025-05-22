require 'redis'
require 'json'

class RateLimiter
  RATE_LIMIT_SCRIPT = <<~LUA
    local key = KEYS[1]
    local now = tonumber(ARGV[1])
    local window = tonumber(ARGV[2])
    local limit = tonumber(ARGV[3])
    
    -- Clean up outdated timestamps
    redis.call('ZREMRANGEBYSCORE', key, '-inf', now - window)
    
    -- Get the number of requests in the current interval
    local count = redis.call('ZCARD', key)
    
    -- Set expiration on the key
    redis.call('EXPIRE', key, window)
    
    if count < limit then
      redis.call('ZADD', key, now, now .. ':' .. math.random())
      return 1
    else
      return 0
    end
  LUA

  def initialize(rate_limit:, granularity:, redis_url: 'redis://localhost:6379')
    @rate_limit = rate_limit.to_i
    @granularity = granularity.to_sym
    @redis = Redis.new(url: redis_url)
    validate_granularity!
    
    # Load the Lua script once during initialization
    @script_sha = @redis.script(:load, RATE_LIMIT_SCRIPT)
  end

  def allowed?(entity_id: 'global')
    key = redis_key(entity_id)
    now = Time.now.to_i
    
    # Execute the rate limiting logic atomically on Redis
    result = @redis.evalsha(
      @script_sha,
      keys: [key],
      argv: [now, interval_seconds, @rate_limit]
    )
    
    result == 1
  end

  # Allow checking multiple entities in a single Redis round trip
  def batch_allowed?(entity_ids)
    now = Time.now.to_i
    
    # Use pipelining to execute multiple commands in a single round trip
    results = @redis.pipelined do
      entity_ids.each do |entity_id|
        key = redis_key(entity_id)
        @redis.evalsha(
          @script_sha,
          keys: [key],
          argv: [now, interval_seconds, @rate_limit]
        )
      end
    end
    
    # Convert Redis response (1 or 0) to boolean
    results.map { |r| r == 1 }
  end

  private

  def redis_key(entity_id)
    "rate_limit:#{@granularity}:#{entity_id}"
  end

  def interval_seconds
    case @granularity
    when :second
      1
    when :minute
      60
    when :hour
      3600
    when :day
      86400
    else
      raise "Unsupported granularity: #{@granularity}"
    end
  end

  def validate_granularity!
    unless [:second, :minute, :hour, :day].include?(@granularity)
      raise ArgumentError, "Granularity must be one of: :second, :minute, :hour, :day"
    end
  end
end

global_limiter = RateLimiter.new(rate_limit: 5, granularity: :second)

10.times do
  if global_limiter.allowed?
    puts "Global request allowed at #{Time.now.strftime('%T.%L')}"
  else
    puts "Global request blocked at #{Time.now.strftime('%T.%L')}"
  end
  sleep 0.1 # Simulate rapid requests
end

puts "\n--- Per User Rate Limiter ---"

# Per-user rate limiter allowing 2 requests per second per user
user_limiter = RateLimiter.new(rate_limit: 2, granularity: :second)

user1_requests = 5.times.map { user_limiter.allowed?(entity_id: 'user_1') }
puts "User 1 requests allowed: #{user1_requests}"

sleep 1.5 # Wait for the interval to reset

user1_requests_again = 3.times.map { user_limiter.allowed?(entity_id: 'user_1') }
puts "User 1 requests allowed again: #{user1_requests_again}"

user2_requests = 3.times.map { user_limiter.allowed?(entity_id: 'user_2') }
puts "User 2 requests allowed: #{user2_requests}"

puts "\n--- Per Minute Rate Limiter ---"

# Global rate limiter allowing 10 requests per minute
minute_limiter = RateLimiter.new(rate_limit: 10, granularity: :minute)

15.times do |i|
  if minute_limiter.allowed?
    puts "Minute request #{i+1} allowed at #{Time.now.strftime('%T.%L')}"
  else
    puts "Minute request #{i+1} blocked at #{Time.now.strftime('%T.%L')}"
  end
  sleep 0.1 # Simulate requests within a minute
end