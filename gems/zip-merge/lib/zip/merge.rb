# frozen_string_literal: true

require 'version_gem'

require 'stringio'
require 'zlib'
require 'tree_haver'
require_relative 'merge/version'

module Zip
  module Merge
    LOCAL = 0x04034b50
    CENTRAL = 0x02014b50
    EOCD = 0x06054b50
    DOS_EPOCH = [0, 0, 0x21, 0].pack('C*')

    RenderError = Class.new(StandardError) do
      attr_reader :diagnostic

      def initialize(diagnostic)
        @diagnostic = diagnostic
        super(diagnostic.message)
      end
    end

    module_function

    def parse_zip_inventory(source)
      bytes = source.b
      central = scan_central_directory(bytes)
      locals = scan_local_headers(bytes, central[:records])
      entries = central[:records].map do |name, record|
        local = locals.fetch(name)
        TreeHaver::ZipArchiveEntry.new(
          path: name,
          normalized_path: normalize_zip_path(name),
          directory: name.end_with?('/'),
          compression: compression_name(record[:method]),
          compressed_size: record[:compressed_size],
          uncompressed_size: record[:uncompressed_size],
          crc32: '%08x' % record[:crc32],
          local_header_range: TreeHaver::ByteRange.new(start_byte: record[:local_offset], end_byte: local[:data_start]),
          data_range: TreeHaver::ByteRange.new(start_byte: local[:data_start],
                                               end_byte: local[:data_start] + record[:compressed_size]),
          central_directory_range: record[:range]
        )
      end.sort_by { |entry| entry.local_header_range.start_byte }

      TreeHaver::ZipFamilyReport.new(
        archive: TreeHaver::ZipArchiveInfo.new(format: 'zip', schema: 'zip.ksy', entry_count: entries.length,
                                               central_directory_range: central[:range]),
        entries: entries,
        member_decisions: [],
        unsafe_entries: unsafe_entries(entries, central[:records]),
        merge_report: empty_report
      )
    end

    def plan_zip_merge(ancestor, current, incoming)
      report = TreeHaver::ZipFamilyReport.new(
        archive: incoming.archive,
        entries: incoming.entries,
        member_decisions: [],
        unsafe_entries: incoming.unsafe_entries || [],
        merge_report: empty_report
      )
      ancestor_entries = entries_by_path(ancestor.entries)
      current_entries = entries_by_path(current.entries)
      incoming_entries = entries_by_path(incoming.entries)
      unsafe_by_path = report.unsafe_entries.to_h { |entry| [entry.normalized_path, entry] }

      (ancestor_entries.keys | current_entries.keys | incoming_entries.keys).sort.each do |path|
        ancestor_entry = ancestor_entries[path]
        current_entry = current_entries[path]
        incoming_entry = incoming_entries[path]
        if unsafe_by_path[path]
          unsafe = unsafe_by_path[path]
          report.member_decisions << TreeHaver::ZipMemberDecision.new(normalized_path: path, operation: 'reject',
                                                                      disposition: 'unsafe', reason: unsafe.reason)
          report.merge_report.diagnostics << diagnostic(unsafe.category, schema_path(path), unsafe.reason)
        elsif current_entry.nil? && incoming_entry
          decision(report, path, 'add', 'requires_renderer', 'member exists only in incoming archive')
        elsif current_entry && incoming_entry.nil?
          decision(report, path, 'delete', 'requires_renderer', 'member was removed from incoming archive')
        elsif ancestor_entry && same_entry?(current_entry,
                                            ancestor_entry) && same_entry?(incoming_entry, ancestor_entry)
          report.member_decisions << TreeHaver::ZipMemberDecision.new(normalized_path: path, operation: 'preserve',
                                                                      disposition: 'safe', reason: 'member is unchanged from ancestor')
          report.merge_report.preserved_ranges.concat([current_entry.local_header_range, current_entry.data_range])
        elsif (family = nested_family(path))
          report.member_decisions << TreeHaver::ZipMemberDecision.new(normalized_path: path, operation: 'delegate',
                                                                      disposition: 'requires_renderer', nested_family: family, reason: 'structured member can be merged by a nested family before ZIP rendering')
          report.merge_report.nested_dispatches << TreeHaver::BinaryNestedDispatch.new(
            schema_path: "#{schema_path(path)}/data", family: family, status: 'planned'
          )
          report.merge_report.rewritten_nodes << schema_path(path)
          report.merge_report.checksum_updates << "#{schema_path(path)}/crc32"
        else
          decision(report, path, 'rewrite', 'requires_renderer', 'member bytes or metadata changed')
          report.merge_report.checksum_updates << "#{schema_path(path)}/crc32"
        end
        report.merge_report.matched_schema_paths << schema_path(path)
      end
      unless report.merge_report.rewritten_nodes.empty? && report.merge_report.checksum_updates.empty?
        report.merge_report.rewritten_nodes << '/central_directory'
        report.merge_report.checksum_updates.concat(['/central_directory/size', '/central_directory/offset'])
      end
      report
    end

    def render_with_raw_preservation(source:, plan:, member_bytes: {}, compression: 0)
      unless [
        0, 8
      ].include?(compression)
        raise render_error('unsupported_compression', '/render/options/compression',
                           'unsupported raw-preserving compression method')
      end

      source = source.b
      source_inventory = parse_zip_inventory(source)
      central = scan_central_directory(source)
      source_entries = entries_by_path(source_inventory.entries)
      raw_ranges = raw_local_record_ranges(source, source_entries)
      output = +''.b
      central_records = []
      entries = entries_by_path(plan.entries)
      plan.member_decisions.each do |member|
        entry = entries[member.normalized_path]
        case member.operation
        when 'reject'
          raise render_error('rejected_member', schema_path(member.normalized_path), member.reason)
        when 'delete'
          next
        when 'preserve'
          source_entry = source_entries.fetch(member.normalized_path)
          validate_raw_preserve_entry!(source, central, source_entry)
          range = raw_ranges.fetch(member.normalized_path)
          offset = output.bytesize
          output << source.byteslice(range.start_byte...range.end_byte)
          central_records << central_record_from_entry(source_entry, offset)
        when 'add', 'rewrite', 'delegate'
          content = member_bytes.fetch(member.normalized_path)
          rendered, record = rendered_local_record(entry, content.b, compression, output.bytesize)
          output << rendered
          central_records << record
        else
          raise "unsupported ZIP render operation #{member.operation.inspect}"
        end
      end
      central_start = output.bytesize
      central_records.each { |record| output << central_directory_record(record) }
      central_size = output.bytesize - central_start
      output << eocd_record(central_records.length, central_size, central_start)
      report = parse_zip_inventory(output)
      merge_report = plan.merge_report
      merge_report.preserved_ranges = plan.member_decisions.filter_map do |member|
        raw_ranges[member.normalized_path] if member.operation == 'preserve'
      end
      [output, report, merge_report]
    end

    def new_stored_zip(entries)
      output = +''.b
      central = []
      entries.keys.sort.each do |name|
        rendered, record = rendered_local_record(path_entry(name, entries[name]), entries[name].b, 0, output.bytesize)
        output << rendered
        central << record
      end
      start = output.bytesize
      central.each { |record| output << central_directory_record(record) }
      output << eocd_record(central.length, output.bytesize - start, start)
      output
    end

    def empty_report
      TreeHaver::BinaryMergeReport.new(format: 'zip', schema: 'zip.ksy', matched_schema_paths: [],
                                       preserved_ranges: [], rewritten_nodes: [], checksum_updates: [], nested_dispatches: [], diagnostics: [])
    end

    def scan_central_directory(source)
      eocd = source.bytesize - 22
      eocd -= 1 while eocd >= 0 && source.byteslice(eocd, 4).unpack1('V') != EOCD
      raise 'missing ZIP end of central directory' if eocd.negative?

      size = source.byteslice(eocd + 12, 4).unpack1('V')
      offset = source.byteslice(eocd + 16, 4).unpack1('V')
      comment_length = source.byteslice(eocd + 20, 2).unpack1('v')
      records = {}
      cursor = offset
      while cursor < offset + size
        raise 'unexpected central directory record' unless source.byteslice(cursor, 4).unpack1('V') == CENTRAL

        name_len = source.byteslice(cursor + 28, 2).unpack1('v')
        extra_len = source.byteslice(cursor + 30, 2).unpack1('v')
        comment_len = source.byteslice(cursor + 32, 2).unpack1('v')
        name = source.byteslice(cursor + 46, name_len)
        records[name] = {
          range: TreeHaver::ByteRange.new(start_byte: cursor,
                                          end_byte: cursor + 46 + name_len + extra_len + comment_len),
          flags: source.byteslice(cursor + 8, 2).unpack1('v'),
          method: source.byteslice(cursor + 10, 2).unpack1('v'),
          crc32: source.byteslice(cursor + 16, 4).unpack1('V'),
          compressed_size: source.byteslice(cursor + 20, 4).unpack1('V'),
          uncompressed_size: source.byteslice(cursor + 24, 4).unpack1('V'),
          extra_length: extra_len,
          comment_length: comment_len,
          local_offset: source.byteslice(cursor + 42, 4).unpack1('V')
        }
        cursor = records[name][:range].end_byte
      end
      { range: TreeHaver::ByteRange.new(start_byte: offset, end_byte: offset + size), records: records, archive_comment: comment_length.positive? }
    end

    def scan_local_headers(source, records)
      records.transform_values do |record|
        cursor = record[:local_offset]
        raise 'unexpected ZIP local header' unless source.byteslice(cursor, 4).unpack1('V') == LOCAL

        name_len = source.byteslice(cursor + 26, 2).unpack1('v')
        extra_len = source.byteslice(cursor + 28, 2).unpack1('v')
        { data_start: cursor + 30 + name_len + extra_len, extra_length: extra_len }
      end
    end

    def validate_raw_preserve_entry!(source, central, entry)
      if central[:archive_comment]
        raise render_error('archive_comment', '/archive/comment',
                           'raw-preserving ZIP renderer does not yet preserve archive comments')
      end

      record = central[:records].fetch(entry.path)
      unless (record[:flags] & 0x1).zero?
        raise render_error('encrypted_member', schema_path(entry.normalized_path),
                           "raw-preserving ZIP renderer rejects encrypted member #{entry.normalized_path}")
      end
      unless [
        0, 8
      ].include?(record[:method])
        raise render_error('unsupported_compression', schema_path(entry.normalized_path),
                           "raw-preserving ZIP renderer rejects unsupported compression #{entry.compression.inspect}")
      end
      unless record[:extra_length].zero?
        raise render_error('central_directory_extra_field', schema_path(entry.normalized_path),
                           "raw-preserving ZIP renderer does not yet preserve central-directory extra fields for #{entry.normalized_path}")
      end
      unless record[:comment_length].zero?
        raise render_error('member_comment', schema_path(entry.normalized_path),
                           "raw-preserving ZIP renderer does not yet preserve member comments for #{entry.normalized_path}")
      end

      local_extra = source.byteslice(entry.local_header_range.start_byte + 28, 2).unpack1('v')
      return if local_extra.zero?

      raise render_error('local_header_extra_field', schema_path(entry.normalized_path),
                         "raw-preserving ZIP renderer does not yet preserve local extra fields for #{entry.normalized_path}")
    end

    def unsafe_entries(entries, records)
      seen = {}
      entries.flat_map do |entry|
        list = []
        if escapes_root?(entry.path)
          list << TreeHaver::ZipUnsafeEntry.new(path: entry.path, normalized_path: entry.normalized_path,
                                                category: 'path_traversal', reason: 'entry escapes the archive root')
        end
        if seen[entry.normalized_path] && seen[entry.normalized_path] != entry.path
          list << TreeHaver::ZipUnsafeEntry.new(path: entry.path, normalized_path: entry.normalized_path,
                                                category: 'duplicate_normalized_path', reason: 'normalized path collides with an existing entry')
        end
        unless (records[entry.path][:flags] & 0x1).zero?
          list << TreeHaver::ZipUnsafeEntry.new(path: entry.path, normalized_path: entry.normalized_path,
                                                category: 'encrypted_member', reason: 'encrypted member cannot be rendered by the default provider')
        end
        if signing_sensitive?(entry.normalized_path)
          list << TreeHaver::ZipUnsafeEntry.new(path: entry.path, normalized_path: entry.normalized_path,
                                                category: 'signing_sensitive_member', reason: 'signature-bearing member mutation is not enabled')
        end
        seen[entry.normalized_path] = entry.path
        list
      end
    end

    def rendered_local_record(entry, content, method, offset)
      payload = method == 8 ? Zlib::Deflate.deflate(content) : content
      crc = Zlib.crc32(content)
      header = [LOCAL, 20, 0,
                method].pack('Vvvv') + DOS_EPOCH + [crc, payload.bytesize, content.bytesize, entry.path.bytesize,
                                                    0].pack('VVVvv') + entry.path
      [header + payload,
       { name: entry.path, method: method, crc32: crc, compressed_size: payload.bytesize, uncompressed_size: content.bytesize,
         offset: offset, flags: 0 }]
    end

    def central_directory_record(record)
      [CENTRAL, 20, 20, record[:flags],
       record[:method]].pack('Vvvvv') + DOS_EPOCH + [record[:crc32], record[:compressed_size], record[:uncompressed_size],
                                                     record[:name].bytesize, 0, 0, 0, 0, 0, record[:offset]].pack('VVVvvvvvVV') + record[:name]
    end

    def eocd_record(entries, size, offset)
      [EOCD, 0, 0, entries, entries, size, offset, 0].pack('VvvvvVVv')
    end

    def raw_local_record_ranges(_source, entries)
      ordered = entries.values.sort_by { |entry| entry.local_header_range.start_byte }
      ordered.each_with_index.to_h do |entry, index|
        end_byte = ordered[index + 1]&.local_header_range&.start_byte || entry.central_directory_range.start_byte
        [entry.normalized_path,
         TreeHaver::ByteRange.new(start_byte: entry.local_header_range.start_byte, end_byte: end_byte)]
      end
    end

    def central_record_from_entry(entry, offset)
      { name: entry.path, method: entry.compression == 'deflate' ? 8 : 0, crc32: entry.crc32.to_i(16),
        compressed_size: entry.compressed_size, uncompressed_size: entry.uncompressed_size, offset: offset, flags: 0 }
    end

    def path_entry(name, content)
      TreeHaver::ZipArchiveEntry.new(path: name, normalized_path: normalize_zip_path(name),
                                     directory: name.end_with?('/'), compression: 'stored', compressed_size: content.bytesize, uncompressed_size: content.bytesize, crc32: '%08x' % Zlib.crc32(content), local_header_range: TreeHaver::ByteRange.new(start_byte: 0, end_byte: 0), data_range: TreeHaver::ByteRange.new(start_byte: 0, end_byte: 0), central_directory_range: TreeHaver::ByteRange.new(start_byte: 0, end_byte: 0))
    end

    def decision(report, path, operation, disposition, reason)
      report.member_decisions << TreeHaver::ZipMemberDecision.new(normalized_path: path, operation: operation,
                                                                  disposition: disposition, reason: reason)
      report.merge_report.rewritten_nodes << schema_path(path)
    end

    def normalize_zip_path(path)
      path.tr('\\', '/').split('/').each_with_object([]) do |part, stack|
        unless part == '.'
          part == '..' ? stack.pop : stack << part
        end
      end.join('/')
    end

    def compression_name(method)
      case method
      when 0 then 'stored'
      when 8 then 'deflate'
      else "method-#{method}"
      end
    end

    def escapes_root?(path)
      path.start_with?('/') || path.tr('\\', '/').split('/').then do |parts|
        depth = 0
        parts.any? do |part|
          part == '..' ? (depth -= 1) : (depth += 1 unless part == '.')
          depth.negative?
        end
      end
    end

    def signing_sensitive?(path)
      path.upcase.start_with?('META-INF/') && ['.RSA', '.DSA', '.EC', '.SF'].any? do |suffix|
        path.upcase.end_with?(suffix)
      end
    end

    def same_entry?(left, right)
      left && right && left.path == right.path && left.compression == right.compression && left.compressed_size == right.compressed_size && left.uncompressed_size == right.uncompressed_size && left.crc32 == right.crc32
    end

    def entries_by_path(entries)
      entries.to_h { |entry| [entry.normalized_path, entry] }
    end

    def nested_family(path)
      return 'markdown' if path.match?(/\.m(?:d|arkdown)\z/i)
      return 'json' if path.end_with?('.json')
      return 'yaml' if path.match?(/\.ya?ml\z/i)

      'xml' if path.end_with?('.xml')
    end

    def schema_path(path)
      "/entries/by_path/#{path}"
    end

    def diagnostic(category, schema_path, message)
      TreeHaver::BinaryDiagnostic.new(severity: 'error', category: category, message: message, schema_path: schema_path)
    end

    def render_error(category, schema_path, message)
      RenderError.new(diagnostic(category, schema_path, message))
    end
  end
end

Zip::Merge::Version.class_eval do
  extend VersionGem::Basic
end

require_relative 'merge/backend'

Zip::Merge.register_backend!
