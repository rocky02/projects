require_relative 'rate_limiter'

puts "=== Rate Limiter Blocking Demonstration ==="

# Create a rate limiter with 3 requests per second
limiter = RateLimiter.new(rate_limit: 3, granularity: :second)

puts "\n--- Global Rate Limiter (3 per second) ---"
6.times do |i|
  result = limiter.allowed?
  puts "Request #{i+1}: #{result ? 'ALLOWED' : 'BLOCKED'} at #{Time.now.strftime('%T.%L')}"
  sleep 0.1 # Small delay between requests
end

puts "\nWaiting for rate limit window to reset..."
sleep 1.1 # Wait for slightly more than 1 second

puts "\n--- After Reset ---"
3.times do |i|
  result = limiter.allowed?
  puts "Request #{i+1}: #{result ? 'ALLOWED' : 'BLOCKED'} at #{Time.now.strftime('%T.%L')}"
  sleep 0.1
end

puts "\n--- Per-User Rate Limiter (2 per second) ---"
user_limiter = RateLimiter.new(rate_limit: 2, granularity: :second)

puts "\nUser 1:"
4.times do |i|
  result = user_limiter.allowed?(entity_id: 'user_1')
  puts "User 1 Request #{i+1}: #{result ? 'ALLOWED' : 'BLOCKED'} at #{Time.now.strftime('%T.%L')}"
  sleep 0.1
end

puts "\nUser 2 (separate limit):"
4.times do |i|
  result = user_limiter.allowed?(entity_id: 'user_2')
  puts "User 2 Request #{i+1}: #{result ? 'ALLOWED' : 'BLOCKED'} at #{Time.now.strftime('%T.%L')}"
  sleep 0.1
end

puts "\n--- Minute Rate Limiter (5 per minute) ---"
minute_limiter = RateLimiter.new(rate_limit: 5, granularity: :minute)

puts "\nSending 7 requests in quick succession:"
7.times do |i|
  result = minute_limiter.allowed?
  puts "Request #{i+1}: #{result ? 'ALLOWED' : 'BLOCKED'} at #{Time.now.strftime('%T.%L')}"
  sleep 0.1
end