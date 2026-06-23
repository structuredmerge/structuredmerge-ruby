# frozen_string_literal: true

class MyClass
  VERSION = '2.0.0'

  def initialize(name)
    @name = name.to_s.strip
  end

  def process(count)
    Array.new(count) { |i| "#{i}: #{@name}" }
  end
end
