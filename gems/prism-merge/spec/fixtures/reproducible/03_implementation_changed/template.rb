# frozen_string_literal: true

class MyClass
  VERSION = '1.0.0'

  def initialize(name)
    @name = name
  end

  def process(count)
    count.times.map { @name }
  end
end
