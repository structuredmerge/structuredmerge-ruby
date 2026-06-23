# frozen_string_literal: true

class MyClass
  VERSION = '1.0.0'

  def initialize(name)
    @name = name
  end

  attr_reader :name

  def custom_method(options = {})
    options.fetch(:default, @name)
  end
end
