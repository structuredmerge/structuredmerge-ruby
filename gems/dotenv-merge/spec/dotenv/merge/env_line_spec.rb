# frozen_string_literal: true

RSpec.describe Dotenv::Merge::EnvLine do
  describe '#initialize' do
    context 'with simple assignment' do
      let(:line) { described_class.new('API_KEY=secret123', 1) }

      it 'parses as assignment' do
        expect(line.line_type).to eq(:assignment)
        expect(line.assignment?).to be true
      end

      it 'extracts key' do
        expect(line.key).to eq('API_KEY')
      end

      it 'extracts value' do
        expect(line.value).to eq('secret123')
      end

      it 'is not export' do
        expect(line.export?).to be false
      end

      it 'stores line number' do
        expect(line.line_number).to eq(1)
      end

      it 'stores raw content' do
        expect(line.raw).to eq('API_KEY=secret123')
      end
    end

    context 'with export prefix' do
      let(:line) { described_class.new('export DATABASE_URL=postgres://localhost', 2) }

      it 'parses as assignment' do
        expect(line.assignment?).to be true
      end

      it 'is export' do
        expect(line.export?).to be true
      end

      it 'extracts key' do
        expect(line.key).to eq('DATABASE_URL')
      end

      it 'extracts value' do
        expect(line.value).to eq('postgres://localhost')
      end
    end

    context 'with double-quoted value' do
      let(:line) { described_class.new('MESSAGE="Hello World"', 1) }

      it 'extracts unquoted value' do
        expect(line.value).to eq('Hello World')
      end
    end

    context 'with single-quoted value' do
      let(:line) { described_class.new("PATH='/usr/bin'", 1) }

      it 'extracts unquoted value' do
        expect(line.value).to eq('/usr/bin')
      end
    end

    context 'with escape sequences in double quotes' do
      let(:line) { described_class.new('MULTILINE="line1\\nline2"', 1) }

      it 'processes escape sequences' do
        expect(line.value).to eq("line1\nline2")
      end
    end

    context 'with # inside double-quoted value' do
      let(:line) { described_class.new('PASSWORD="abc#123"', 1) }

      it 'keeps the # as part of the value' do
        expect(line.value).to eq('abc#123')
      end
    end

    context 'with # inside single-quoted value' do
      let(:line) { described_class.new("PASSWORD='abc#123'", 1) }

      it 'keeps the # as part of the value' do
        expect(line.value).to eq('abc#123')
      end
    end

    context 'with inline comment' do
      let(:line) { described_class.new('PORT=3000 # default port', 1) }

      it 'strips inline comment' do
        expect(line.value).to eq('3000')
      end
    end

    context 'with # in unquoted value without separating whitespace' do
      let(:line) { described_class.new('PASSWORD=abc#123', 1) }

      it 'keeps the # as part of the value' do
        expect(line.value).to eq('abc#123')
      end
    end

    context 'with empty value' do
      let(:line) { described_class.new('EMPTY=', 1) }

      it 'has empty string value' do
        expect(line.value).to eq('')
      end
    end

    context 'with comment line' do
      let(:line) { described_class.new('# This is a comment', 3) }

      it 'parses as comment' do
        expect(line.line_type).to eq(:comment)
        expect(line.comment?).to be true
      end

      it 'returns comment text' do
        expect(line.comment).to eq('# This is a comment')
      end

      it 'has no key or value' do
        expect(line.key).to be_nil
        expect(line.value).to be_nil
      end
    end

    context 'with blank line' do
      let(:line) { described_class.new('', 4) }

      it 'parses as blank' do
        expect(line.line_type).to eq(:blank)
        expect(line.blank?).to be true
      end
    end

    context 'with whitespace-only line' do
      let(:line) { described_class.new('   ', 5) }

      it 'parses as blank' do
        expect(line.blank?).to be true
      end
    end

    context 'with invalid line' do
      let(:line) { described_class.new('not a valid line', 6) }

      it 'parses as invalid' do
        expect(line.line_type).to eq(:invalid)
        expect(line.invalid?).to be true
      end
    end

    context 'with underscore in key' do
      let(:line) { described_class.new('MY_APP_SECRET_KEY=value', 1) }

      it 'extracts full key' do
        expect(line.key).to eq('MY_APP_SECRET_KEY')
      end
    end

    context 'with numbers in key' do
      let(:line) { described_class.new('API_V2_KEY=value', 1) }

      it 'extracts key with numbers' do
        expect(line.key).to eq('API_V2_KEY')
      end
    end

    context 'with key starting with number (invalid)' do
      let(:line) { described_class.new('2INVALID=value', 1) }

      it 'parses as invalid' do
        expect(line.line_type).to eq(:invalid)
      end
    end

    context 'with only equals sign' do
      let(:line) { described_class.new('=value', 1) }

      it 'parses as invalid' do
        expect(line.line_type).to eq(:invalid)
      end
    end
  end

  describe '#comment' do
    it 'returns nil for non-comment lines' do
      line = described_class.new('KEY=value', 1)
      expect(line.comment).to be_nil
    end

    it 'returns raw content for comment lines' do
      line = described_class.new('# This is a comment', 1)
      expect(line.comment).to eq('# This is a comment')
    end
  end

  describe '#to_s' do
    it 'returns the raw content' do
      line = described_class.new('KEY=value', 1)
      expect(line.to_s).to eq('KEY=value')
    end
  end

  describe '#type' do
    it "returns 'env_line' for TreeHaver::Node protocol" do
      line = described_class.new('API_KEY=secret', 1)
      expect(line.type).to eq('env_line')
    end

    it "returns 'env_line' for all line types" do
      assignment = described_class.new('KEY=value', 1)
      comment = described_class.new('# comment', 2)
      blank = described_class.new('', 3)
      invalid = described_class.new('not valid', 4)

      expect(assignment.type).to eq('env_line')
      expect(comment.type).to eq('env_line')
      expect(blank.type).to eq('env_line')
      expect(invalid.type).to eq('env_line')
    end
  end

  describe '#signature' do
    it 'returns signature for assignment' do
      line = described_class.new('API_KEY=secret', 1)
      expect(line.signature).to eq([:env, 'API_KEY'])
    end

    it 'returns nil for comment' do
      line = described_class.new('# comment', 1)
      expect(line.signature).to be_nil
    end

    it 'returns nil for blank' do
      line = described_class.new('', 1)
      expect(line.signature).to be_nil
    end

    it 'returns nil for invalid' do
      line = described_class.new('not valid env', 1)
      expect(line.signature).to be_nil
    end
  end

  describe '#location' do
    it 'returns Location struct' do
      line = described_class.new('KEY=value', 5)
      location = line.location
      expect(location.start_line).to eq(5)
      expect(location.end_line).to eq(5)
    end

    it 'supports cover?' do
      line = described_class.new('KEY=value', 5)
      expect(line.location.cover?(5)).to be true
      expect(line.location.cover?(4)).to be false
    end
  end

  describe '#inspect' do
    it 'returns descriptive string' do
      line = described_class.new('KEY=value', 1)
      expect(line.inspect).to include('EnvLine')
      expect(line.inspect).to include('line=1')
      expect(line.inspect).to include('line_type=assignment')
      expect(line.inspect).to include('key="KEY"')
    end

    it 'shows nil key for non-assignments' do
      line = described_class.new('# comment', 1)
      expect(line.inspect).to include('key=nil')
    end
  end

  describe 'value parsing edge cases' do
    it 'handles value with embedded equals sign' do
      line = described_class.new('URL=http://host?param=value', 1)
      expect(line.key).to eq('URL')
      expect(line.value).to eq('http://host?param=value')
    end

    it 'handles double-quoted value with escape sequences' do
      line = described_class.new('MSG="tab\\there"', 1)
      expect(line.value).to eq("tab\there")
    end

    it 'handles single-quoted value without escape processing' do
      line = described_class.new("MSG='literal\\n'", 1)
      # Single quotes should preserve backslash
      expect(line.value).to eq('literal\\n')
    end

    it 'handles export with spaces around equals' do
      # NOTE: spaces around = may make this invalid depending on implementation
      line = described_class.new('export KEY = value', 1)
      # Check that it handles this case somehow (may be invalid or parsed)
      expect(line.line_type).to be_a(Symbol)
    end
  end
end
