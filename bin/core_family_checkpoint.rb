# frozen_string_literal: true

require 'digest'
require 'fileutils'
require 'json'

# A checkpoint is tied to the exact committed family, core package and Ruby.
# Each member is recorded only after its test result and installed-core proof pass.
class CoreFamilyCheckpoint
  attr_reader :path, :completed

  def initialize(directory:, identity:, members:)
    @identity = identity.merge('members' => members)
    key = Digest::SHA256.hexdigest(JSON.generate(@identity))
    FileUtils.mkdir_p(directory)
    @path = File.join(directory, "#{key}.json")
    @completed = []
    return unless File.file?(@path)

    data = JSON.parse(File.read(@path))
    raise "invalid family gate checkpoint: #{@path}" unless data['identity'] == @identity &&
      data['completed'].is_a?(Array) && (data['completed'] - members).empty? &&
      data['completed'].all? { |name| name.is_a?(String) }

    @completed = data['completed'].uniq
  end

  def record(member)
    raise "unknown family member: #{member}" unless @identity.fetch('members').include?(member)
    return if @completed.include?(member)

    updated = @completed + [member]
    temporary = "#{@path}.#{Process.pid}.tmp"
    File.write(temporary, JSON.pretty_generate('identity' => @identity, 'completed' => updated) + "\n")
    File.rename(temporary, @path)
    @completed = updated
  ensure
    File.unlink(temporary) if temporary && File.exist?(temporary)
  end
end
