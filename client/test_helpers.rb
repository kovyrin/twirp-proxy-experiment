# frozen_string_literal: true

def assert_equal(res1, res2)
  if res1 == res2
    puts "+ OK: Results match (#{res1.inspect})"
  else
    puts "ERROR! Results do not match! (#{res1.inspect} != #{res2.inspect})"
    exit(1)
  end
  puts
end

def refute_equal(res1, res2)
  if res1 != res2
    puts "+ OK: Results do not match (#{res1.inspect} != #{res2.inspect})"
  else
    puts "ERROR! Results match! (#{res1.inspect})"
    exit(1)
  end
  puts
end

def sleep_with_progress(seconds)
  seconds.times do
    print '.'
    sleep(1)
  end
  puts
end
