# frozen_string_literal: true

class MyClass
  VERSION = '1.0.0'

  def initialize(name)
    @name = name
  end

  attr_reader :name

  def process(count)
    Array.new(count) { @name }
  end
end
