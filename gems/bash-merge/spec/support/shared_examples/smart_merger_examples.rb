# frozen_string_literal: true

require 'ast/merge/rspec/shared_examples'

# Shared examples for SmartMerger across different backends
#
# These examples test SmartMerger behavior that should be consistent
# regardless of which tree-sitter backend is used (MRI, FFI, Rust, Java).

RSpec.shared_examples 'basic initialization' do
  let(:template_content) do
    <<~BASH
      #!/bin/bash
      MY_VAR="template_value"
      echo "template"
    BASH
  end

  let(:dest_content) do
    <<~BASH
      #!/bin/bash
      MY_VAR="dest_value"
      echo "dest"
    BASH
  end

  describe '#initialize' do
    it 'creates a merger with content' do
      merger = described_class.new(template_content, dest_content)
      expect(merger).to be_a(described_class)
    end

    it 'has template_analysis' do
      merger = described_class.new(template_content, dest_content)
      expect(merger.template_analysis).to be_a(Bash::Merge::FileAnalysis)
    end

    it 'has dest_analysis' do
      merger = described_class.new(template_content, dest_content)
      expect(merger.dest_analysis).to be_a(Bash::Merge::FileAnalysis)
    end
  end
end

RSpec.shared_examples 'configuration options' do
  it 'accepts preference' do
    expect(described_class.instance_method(:initialize).parameters.flatten).to include(:preference)
  end

  it 'accepts add_template_only_nodes' do
    expect(described_class.instance_method(:initialize).parameters.flatten).to include(:add_template_only_nodes)
  end

  it 'accepts remove_template_missing_nodes' do
    expect(described_class.instance_method(:initialize).parameters.flatten).to include(:remove_template_missing_nodes)
  end

  it 'accepts freeze_token' do
    expect(described_class.instance_method(:initialize).parameters.flatten).to include(:freeze_token)
  end

  it 'accepts signature_generator' do
    expect(described_class.instance_method(:initialize).parameters.flatten).to include(:signature_generator)
  end

  it 'accepts match_refiner' do
    expect(described_class.instance_method(:initialize).parameters.flatten).to include(:match_refiner)
  end

  it 'accepts regions' do
    expect(described_class.instance_method(:initialize).parameters.flatten).to include(:regions)
  end

  it 'accepts node_typing' do
    expect(described_class.instance_method(:initialize).parameters.flatten).to include(:node_typing)
  end
end

RSpec.shared_examples 'instance methods' do
  it 'defines #merge' do
    expect(described_class.instance_methods).to include(:merge)
  end

  it 'defines #merge_with_debug' do
    expect(described_class.instance_methods).to include(:merge_with_debug)
  end

  it 'defines #valid?' do
    expect(described_class.instance_methods).to include(:valid?)
  end

  it 'defines #errors' do
    expect(described_class.instance_methods).to include(:errors)
  end
end

RSpec.shared_examples 'accessors' do
  it 'exposes template_analysis' do
    expect(described_class.instance_methods).to include(:template_analysis)
  end

  it 'exposes dest_analysis' do
    expect(described_class.instance_methods).to include(:dest_analysis)
  end

  it 'exposes resolver' do
    expect(described_class.instance_methods).to include(:resolver)
  end

  it 'exposes result' do
    expect(described_class.instance_methods).to include(:result)
  end

  it 'exposes preference' do
    expect(described_class.instance_methods).to include(:preference)
  end

  it 'exposes add_template_only_nodes' do
    expect(described_class.instance_methods).to include(:add_template_only_nodes)
  end

  it 'exposes remove_template_missing_nodes' do
    expect(described_class.instance_methods).to include(:remove_template_missing_nodes)
  end

  it 'exposes freeze_token' do
    expect(described_class.instance_methods).to include(:freeze_token)
  end
end

RSpec.shared_examples 'basic merge operation' do
  let(:template_content) do
    <<~BASH
      #!/bin/bash
      MY_VAR="template_value"
      echo "template"
    BASH
  end

  let(:dest_content) do
    <<~BASH
      #!/bin/bash
      MY_VAR="dest_value"
      echo "dest"
    BASH
  end

  describe '#merge' do
    it 'returns merged content as a string' do
      merger = described_class.new(template_content, dest_content)
      result = merger.merge

      expect(result).to be_a(String)
      expect(result).not_to be_empty
    end

    it 'preserves destination values by default' do
      merger = described_class.new(template_content, dest_content)
      result = merger.merge

      expect(result).to include('dest_value')
    end
  end
end

RSpec.shared_examples 'template preference' do
  let(:template_content) do
    <<~BASH
      #!/bin/bash
      MY_VAR="template_value"
      echo "template"
    BASH
  end

  let(:dest_content) do
    <<~BASH
      #!/bin/bash
      MY_VAR="dest_value"
      echo "dest"
    BASH
  end

  describe 'with template preference' do
    it 'uses template values when preference is :template' do
      merger = described_class.new(
        template_content,
        dest_content,
        preference: :template
      )
      result = merger.merge

      expect(result).to include('template_value')
    end
  end
end

RSpec.shared_examples 'merge_with_debug' do
  let(:template_content) do
    <<~BASH
      #!/bin/bash
      MY_VAR="template_value"
      echo "template"
    BASH
  end

  let(:dest_content) do
    <<~BASH
      #!/bin/bash
      MY_VAR="dest_value"
      echo "dest"
    BASH
  end

  describe '#merge_with_debug' do
    let(:runtime_debug_merger) { described_class.new(template_content, dest_content) }

    it_behaves_like 'Ast::Merge::RuntimeDebugContract'
  end
end

RSpec.shared_examples 'validation' do
  let(:template_content) do
    <<~BASH
      #!/bin/bash
      echo "template"
    BASH
  end

  let(:dest_content) do
    <<~BASH
      #!/bin/bash
      echo "dest"
    BASH
  end

  describe '#valid?' do
    it 'returns true when both files parse successfully' do
      merger = described_class.new(template_content, dest_content)
      expect(merger.valid?).to be true
    end
  end

  describe '#errors' do
    it 'returns empty array when no errors' do
      merger = described_class.new(template_content, dest_content)
      expect(merger.errors).to be_an(Array)
      expect(merger.errors).to be_empty
    end
  end
end

RSpec.shared_examples 'add template-only nodes' do
  let(:template_with_extra) do
    <<~BASH
      #!/bin/bash
      TEMPLATE_ONLY="only_in_template"
      SHARED="shared_value"
    BASH
  end

  let(:simple_dest) do
    <<~BASH
      #!/bin/bash
      SHARED="shared_value"
    BASH
  end

  describe 'with add_template_only_nodes' do
    it 'adds template-only nodes when enabled' do
      merger = described_class.new(
        template_with_extra,
        simple_dest,
        add_template_only_nodes: true
      )
      result = merger.merge

      expect(result).to include('TEMPLATE_ONLY')
    end

    it 'does not add template-only nodes when disabled' do
      merger = described_class.new(
        template_with_extra,
        simple_dest,
        add_template_only_nodes: false
      )
      result = merger.merge

      expect(result).not_to include('TEMPLATE_ONLY')
    end
  end
end

RSpec.shared_examples 'freeze blocks' do
  let(:template_content) do
    <<~BASH
      #!/bin/bash
      MY_VAR="template_value"
      echo "template"
    BASH
  end

  let(:dest_with_freeze) do
    <<~BASH
      #!/bin/bash
      # bash-merge:freeze
      SECRET="frozen_secret"
      # bash-merge:unfreeze
      PUBLIC="public_value"
    BASH
  end

  describe 'with freeze blocks' do
    it 'preserves freeze blocks even with template preference' do
      merger = described_class.new(
        template_content,
        dest_with_freeze,
        preference: :template
      )
      result = merger.merge

      expect(result).to include('bash-merge:freeze')
      expect(result).to include('SECRET')
    end
  end
end

RSpec.shared_examples 'custom freeze token' do
  let(:template_content) do
    <<~BASH
      #!/bin/bash
      MY_VAR="template_value"
      echo "template"
    BASH
  end

  let(:dest_with_custom_freeze) do
    <<~BASH
      #!/bin/bash
      # custom-token:freeze
      SECRET="custom_frozen"
      # custom-token:unfreeze
      PUBLIC="public"
    BASH
  end

  describe 'with custom freeze token' do
    it 'respects custom freeze token' do
      merger = described_class.new(
        template_content,
        dest_with_custom_freeze,
        freeze_token: 'custom-token'
      )
      result = merger.merge

      expect(result).to include('custom-token:freeze')
      expect(result).to include('SECRET')
    end
  end
end

RSpec.shared_examples 'function merging' do
  let(:template_with_func) do
    <<~BASH
      #!/bin/bash
      setup() {
        echo "template setup"
      }

      main() {
        echo "template main"
      }
    BASH
  end

  let(:dest_with_func) do
    <<~BASH
      #!/bin/bash
      setup() {
        echo "dest setup"
      }

      cleanup() {
        echo "dest cleanup"
      }
    BASH
  end

  describe 'with functions' do
    it 'merges matching functions' do
      merger = described_class.new(
        template_with_func,
        dest_with_func,
        preference: :destination,
        add_template_only_nodes: true
      )
      result = merger.merge

      expect(result).to include('setup')
      expect(result).to include('dest setup')
      expect(result).to include('cleanup')
      expect(result).to include('main')
    end
  end
end

RSpec.shared_examples 'duplicate command signatures' do
  describe 'commands with same name but different arguments' do
    let(:template_with_duplicate_commands) do
      <<~BASH
        #!/bin/bash
        # Run any command in this project's bin/ without the bin/ prefix
        PATH_add exe
        PATH_add bin
      BASH
    end

    let(:dest_with_export) do
      <<~BASH
        #!/bin/bash
        export FOO=bar
      BASH
    end

    it 'preserves all template-only commands with add_template_only_nodes: true' do
      merger = described_class.new(
        template_with_duplicate_commands,
        dest_with_export,
        preference: :destination,
        add_template_only_nodes: true
      )
      result = merger.merge

      expect(result).to include('PATH_add exe')
      expect(result).to include('PATH_add bin')
      expect(result).to include('export FOO=bar')
    end

    it 'does not collapse two distinct commands into one' do
      merger = described_class.new(
        template_with_duplicate_commands,
        dest_with_export,
        preference: :destination,
        add_template_only_nodes: true
      )
      result = merger.merge

      # Both PATH_add lines must appear as separate lines
      path_add_lines = result.lines.select { |l| l.strip.start_with?('PATH_add') }
      expect(path_add_lines.length).to eq(2)
    end

    it 'preserves duplicate commands in a self-merge' do
      merger = described_class.new(
        template_with_duplicate_commands,
        template_with_duplicate_commands,
        preference: :destination
      )
      result = merger.merge

      expect(result).to include('PATH_add exe')
      expect(result).to include('PATH_add bin')
    end

    context 'with echo commands' do
      let(:template_with_echos) do
        <<~BASH
          #!/bin/bash
          echo "hello"
          echo "world"
        BASH
      end

      let(:empty_dest) do
        <<~BASH
          #!/bin/bash
        BASH
      end

      it 'preserves all echo commands with different arguments' do
        merger = described_class.new(
          template_with_echos,
          empty_dest,
          preference: :destination,
          add_template_only_nodes: true
        )
        result = merger.merge

        expect(result).to include('echo "hello"')
        expect(result).to include('echo "world"')
      end
    end
  end

  describe 'identical commands (same name, same arguments)' do
    it 'preserves both identical lines from template as template-only additions' do
      template = "sleep 1\nsleep 1\n"
      dest = "echo \"Foo\"\n"

      result = described_class.new(
        template,
        dest,
        preference: :destination,
        add_template_only_nodes: true
      ).merge

      sleep_count = result.lines.count { |l| l.strip == 'sleep 1' }
      expect(sleep_count).to eq(2), "Expected 2 'sleep 1' lines, got #{sleep_count}. Result:\n#{result}"
      expect(result).to include('echo "Foo"')
    end

    it 'preserves dest duplicates when template is a subset' do
      template = "echo \"Foo\"\necho \"Foo\"\n"
      dest = "echo \"Foo\"\necho \"Foo\"\necho \"Bar\"\necho \"Bar\"\n"

      result = described_class.new(
        template,
        dest,
        preference: :destination
      ).merge

      foo_count = result.lines.count { |l| l.strip == 'echo "Foo"' }
      bar_count = result.lines.count { |l| l.strip == 'echo "Bar"' }
      expect(foo_count).to eq(2), "Expected 2 'echo Foo' lines, got #{foo_count}. Result:\n#{result}"
      expect(bar_count).to eq(2), "Expected 2 'echo Bar' lines, got #{bar_count}. Result:\n#{result}"
    end

    it 'adds new template lines beyond shared duplicates' do
      template = "echo \"Foo\"\necho \"Foo\"\necho \"Bar\"\necho \"Bar\"\necho \"Fizz\"\necho \"Buzz\"\n"
      dest = "echo \"Foo\"\necho \"Foo\"\necho \"Bar\"\necho \"Bar\"\n"

      result = described_class.new(
        template,
        dest,
        preference: :destination,
        add_template_only_nodes: true
      ).merge

      foo_count = result.lines.count { |l| l.strip == 'echo "Foo"' }
      bar_count = result.lines.count { |l| l.strip == 'echo "Bar"' }
      expect(foo_count).to eq(2)
      expect(bar_count).to eq(2)
      expect(result).to include('echo "Fizz"')
      expect(result).to include('echo "Buzz"')
    end

    it 'self-merge is identity for files with duplicates' do
      content = "echo \"Foo\"\necho \"Foo\"\necho \"Bar\"\n"

      result = described_class.new(
        content,
        content,
        preference: :destination
      ).merge

      foo_count = result.lines.count { |l| l.strip == 'echo "Foo"' }
      bar_count = result.lines.count { |l| l.strip == 'echo "Bar"' }
      expect(foo_count).to eq(2), "Self-merge lost a duplicate 'echo Foo'. Result:\n#{result}"
      expect(bar_count).to eq(1)
    end
  end
end

RSpec.shared_examples 'complex scripts' do
  let(:complex_template) do
    <<~BASH
      #!/bin/bash
      set -e

      # Configuration
      APP_NAME="myapp"
      VERSION="1.0.0"

      # Functions
      log() {
        echo "[LOG] $1"
      }

      main() {
        log "Starting $APP_NAME v$VERSION"
      }

      main "$@"
    BASH
  end

  let(:complex_dest) do
    <<~BASH
      #!/bin/bash
      set -e

      # Configuration
      APP_NAME="myapp-custom"
      VERSION="1.0.0"
      DEBUG=true

      # Functions
      log() {
        echo "[CUSTOM LOG] $1"
      }

      # Custom function
      debug() {
        if [ "$DEBUG" = true ]; then
          echo "[DEBUG] $1"
        fi
      }

      main() {
        log "Starting $APP_NAME v$VERSION"
        debug "Debug mode enabled"
      }

      main "$@"
    BASH
  end

  describe 'with complex scripts' do
    it 'handles complex scripts with multiple constructs' do
      merger = described_class.new(
        complex_template,
        complex_dest,
        preference: :destination,
        add_template_only_nodes: false
      )
      result = merger.merge

      expect(result).to include('myapp-custom')
      expect(result).to include('debug')
      expect(result).to include('CUSTOM LOG')
    end
  end
end

RSpec.shared_examples 'document boundary comments' do
  describe 'document boundary comments' do
    it 'preserves destination shebang, header comments, and footer comments by default' do
      template_content = <<~BASH
        #!/usr/bin/env bash
        # Template header

        echo "template"
        # Template footer
      BASH

      dest_content = <<~BASH
        #!/usr/bin/env bash
        # Destination header

        echo "dest"
        # Destination footer
      BASH

      merger = described_class.new(template_content, dest_content)

      expect(merger.merge).to eq(dest_content)
    end

    it 'uses the preferred template document boundaries when template content wins' do
      template_content = <<~BASH
        #!/usr/bin/env bash
        # Template header

        MODE="template"
        # Template footer
      BASH

      dest_content = <<~BASH
        #!/bin/bash
        # Destination header

        MODE="dest"
        # Destination footer
      BASH

      merger = described_class.new(template_content, dest_content, preference: :template)

      expect(merger.merge).to eq(template_content)
    end

    it 'preserves comment-only destination files' do
      template_content = <<~BASH
        #!/usr/bin/env bash
        echo "template"
      BASH

      dest_content = <<~BASH
        #!/usr/bin/env bash
        # Destination docs
        # More destination docs
      BASH

      merger = described_class.new(template_content, dest_content)

      expect(merger.merge).to eq(dest_content)
    end
  end
end

RSpec.shared_examples 'matched leading comments' do
  describe 'matched leading comments' do
    it 'preserves destination leading comments for a matched function when template content wins' do
      template_content = <<~BASH
        deploy() {
          echo "template deploy"
        }
      BASH

      dest_content = <<~BASH
        # Destination deploy docs
        deploy() {
          echo "destination deploy"
        }
      BASH

      merger = described_class.new(template_content, dest_content, preference: :template)

      expect(merger.merge).to eq(<<~BASH)
        # Destination deploy docs
        deploy() {
          echo "template deploy"
        }
      BASH
    end

    it 'preserves destination leading comments for a matched assignment when template content wins' do
      template_content = <<~BASH
        APP_MODE="template"
      BASH

      dest_content = <<~BASH
        # Destination app mode docs
        APP_MODE="destination"
      BASH

      merger = described_class.new(template_content, dest_content, preference: :template)

      expect(merger.merge).to eq(<<~BASH)
        # Destination app mode docs
        APP_MODE="template"
      BASH
    end

    it 'keeps template leading comments when the template already documents the matched node' do
      template_content = <<~BASH
        # Template deploy docs
        deploy() {
          echo "template deploy"
        }
      BASH

      dest_content = <<~BASH
        # Destination deploy docs
        deploy() {
          echo "destination deploy"
        }
      BASH

      merger = described_class.new(template_content, dest_content, preference: :template)

      expect(merger.merge).to eq(template_content)
    end
  end
end

RSpec.shared_examples 'removed node leading comments' do
  describe 'removed node leading comments' do
    it 'preserves leading comments for a removed destination-only function when removal is enabled' do
      template_content = <<~BASH
        echo "template"
      BASH

      dest_content = <<~BASH
        echo "template"

        # Destination cleanup docs
        cleanup() {
          echo "destination cleanup"
        }
      BASH

      merger = described_class.new(
        template_content,
        dest_content,
        remove_template_missing_nodes: true
      )

      expect(merger.merge).to eq(<<~BASH)
        echo "template"

        # Destination cleanup docs
      BASH
    end

    it 'preserves leading comments for a removed destination-only assignment when removal is enabled' do
      template_content = <<~BASH
        echo "template"
      BASH

      dest_content = <<~BASH
        echo "template"

        # Destination env docs
        APP_MODE="destination"
      BASH

      merger = described_class.new(
        template_content,
        dest_content,
        remove_template_missing_nodes: true
      )

      expect(merger.merge).to eq(<<~BASH)
        echo "template"

        # Destination env docs
      BASH
    end

    it 'keeps destination-only nodes when removal is disabled' do
      template_content = <<~BASH
        echo "template"
      BASH

      dest_content = <<~BASH
        echo "template"

        # Destination cleanup docs
        cleanup() {
          echo "destination cleanup"
        }
      BASH

      merger = described_class.new(template_content, dest_content, remove_template_missing_nodes: false)

      expect(merger.merge).to eq(dest_content)
    end
  end
end

RSpec.shared_examples 'conservative inline comments' do
  describe 'conservative inline comments' do
    it 'preserves a destination inline comment on a simple command when destination content is kept' do
      template_content = <<~BASH
        echo "template"
      BASH

      dest_content = <<~BASH
        echo "destination" # destination echo docs
      BASH

      merger = described_class.new(template_content, dest_content)

      expect(merger.merge).to eq(dest_content)
    end

    it 'preserves a destination inline comment for a matched template-preferred assignment' do
      template_content = <<~BASH
        APP_MODE="template"
      BASH

      dest_content = <<~BASH
        APP_MODE="destination" # destination app mode docs
      BASH

      merger = described_class.new(template_content, dest_content, preference: :template)

      expect(merger.merge).to eq(<<~BASH)
        APP_MODE="template" # destination app mode docs
      BASH
    end

    it 'keeps the template inline comment when the template already documents the matched node' do
      template_content = <<~BASH
        APP_MODE="template" # template app mode docs
      BASH

      dest_content = <<~BASH
        APP_MODE="destination" # destination app mode docs
      BASH

      merger = described_class.new(template_content, dest_content, preference: :template)

      expect(merger.merge).to eq(template_content)
    end
  end
end

RSpec.shared_examples 'removed node inline comments' do
  describe 'removed node inline comments' do
    it 'promotes a removed destination-only command inline comment when removal is enabled' do
      template_content = <<~BASH
        echo "template"
      BASH

      dest_content = <<~BASH
        echo "template"
        echo "destination" # destination cleanup docs
      BASH

      merger = described_class.new(
        template_content,
        dest_content,
        remove_template_missing_nodes: true
      )

      expect(merger.merge).to eq(<<~BASH)
        echo "template"
        # destination cleanup docs
      BASH
    end

    it 'promotes a removed destination-only assignment inline comment when removal is enabled' do
      template_content = <<~BASH
        echo "template"
      BASH

      dest_content = <<~BASH
        echo "template"
        APP_MODE="destination" # destination env docs
      BASH

      merger = described_class.new(
        template_content,
        dest_content,
        remove_template_missing_nodes: true
      )

      expect(merger.merge).to eq(<<~BASH)
        echo "template"
        # destination env docs
      BASH
    end
  end
end

RSpec.shared_examples 'multi-byte character (emoji) handling' do
  describe 'regression: multi-byte characters must not corrupt byte offsets' do
    it 'does not duplicate variable assignments when destination contains emoji' do
      template = <<~BASH
        export VAR="hello"
      BASH
      destination = <<~BASH
        export EMOJI="🪙"
        export VAR="hello"
      BASH

      merger = described_class.new(
        template,
        destination,
        preference: :destination,
        add_template_only_nodes: true
      )
      result = merger.merge

      expect(result.scan('VAR=').size).to eq(1), "Expected VAR= to appear exactly once, got:\n#{result}"
    end

    it 'preserves emoji in variable values' do
      template = <<~BASH
        MY_VAR="default"
      BASH
      destination = <<~BASH
        MY_VAR="🍲 cooking"
      BASH

      merger = described_class.new(
        template,
        destination,
        preference: :destination
      )
      result = merger.merge

      expect(result).to include('🍲 cooking')
    end

    it 'handles functions after emoji comments without duplication' do
      template = <<~BASH
        hello() {
          echo "hi"
        }
      BASH
      destination = <<~BASH
        # 🪙 Token config
        hello() {
          echo "hi"
        }
      BASH

      merger = described_class.new(
        template,
        destination,
        preference: :destination,
        add_template_only_nodes: true
      )
      result = merger.merge

      expect(result.scan('hello()').size).to eq(1), "Expected hello() to appear exactly once, got:\n#{result}"
    end

    it 'handles CJK characters in comments without duplication' do
      template = <<~BASH
        # Config
        export A="1"
      BASH
      destination = <<~BASH
        # 設定
        export A="1"
      BASH

      merger = described_class.new(
        template,
        destination,
        preference: :destination,
        add_template_only_nodes: true
      )
      result = merger.merge

      expect(result.scan('A=').size).to eq(1), "Expected A= to appear exactly once, got:\n#{result}"
    end
  end
end

RSpec.shared_examples 'floating comment gap transitions' do
  describe 'floating comment gap transitions' do
    it 'attaches a formerly floating comment when template preference removes the separating gap' do
      template = <<~BASH
        export BEFORE=1
        # floating note
        APP_MODE="template"
      BASH
      destination = <<~BASH
        export BEFORE=1

        # floating note
        APP_MODE="destination"
      BASH

      merger = described_class.new(
        template,
        destination,
        preference: :template
      )

      expect(merger.merge).to eq(<<~BASH)
        export BEFORE=1
        # floating note
        APP_MODE="template"
      BASH
    end

    it 'preserves the separating gap when the commented owner is removed but the comment should remain floating' do
      template = <<~BASH
        export BEFORE=1
        APP_MODE="template"
      BASH
      destination = <<~BASH
        export BEFORE=1

        # floating note
        REMOVE_ME=1

        APP_MODE="destination"
      BASH

      merger = described_class.new(
        template,
        destination,
        preference: :template,
        remove_template_missing_nodes: true
      )

      expect(merger.merge).to eq(<<~BASH)
        export BEFORE=1

        # floating note

        APP_MODE="template"
      BASH
    end
  end
end
