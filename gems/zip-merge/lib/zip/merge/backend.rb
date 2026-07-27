# frozen_string_literal: true

module Zip
  # StructuredMerge ZIP archive merge planning and rendering helpers.
  module Merge
    BACKEND_REFERENCE = TreeHaver::KAITAI_STRUCT_BACKEND

    module Backend
      # TreeHaver language wrapper for ZIP archives parsed through Kaitai-style
      # binary AST inventory.
      class Language < TreeHaver::Base::Language
        def initialize(name = :zip)
          super(name, backend: :kaitai, options: {})
        end

        def self.zip
          new(:zip)
        end
      end

      # Parser adapter that exposes the ZIP inventory as the TreeHaver
      # `parser_for(:zip)` Kaitai backend surface.
      class Parser < TreeHaver::Base::Parser
        def parse(source)
          raise 'Language not set' unless language

          Zip::Merge.parse_zip_inventory(source)
        end

        def parse_string(_old_tree, source)
          parse(source)
        end
      end
    end

    def self.register_backend!
      TreeHaver::BackendRegistry.register(BACKEND_REFERENCE)
      TreeHaver.register_language(
        :zip,
        backend_module: Backend,
        backend_type: :kaitai,
        gem_name: 'zip-merge',
        contract: :kaitai
      )
      nil
    end
  end
end
