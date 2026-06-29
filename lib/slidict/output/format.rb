# frozen_string_literal: true

module Slidict
  module Output
    # Single source of truth for everything that varies per output framework:
    # the output file extension, the body_format sent to the slidict.io API,
    # and (for markdown-based frameworks) the frontmatter block to render.
    # Add a new framework by adding one entry to REGISTRY.
    class Format
      Definition = Struct.new(:name, :extension, :body_format, :frontmatter, keyword_init: true)

      DEFAULT_NAME = "slidev"

      REGISTRY = {
        "slidev" => Definition.new(
          name: "slidev",
          extension: ".md",
          body_format: "markdown",
          frontmatter: "theme: default\nclass: text-center"
        ),
        "marp" => Definition.new(
          name: "marp",
          extension: ".md",
          body_format: "markdown",
          frontmatter: "marp: true\ntheme: default"
        ),
        "asciidoctor-revealjs" => Definition.new(
          name: "asciidoctor-revealjs",
          extension: ".adoc",
          body_format: "asciidoc",
          frontmatter: nil
        )
      }.freeze

      def self.fetch(name)
        REGISTRY.fetch(name.to_s.downcase, REGISTRY.fetch(DEFAULT_NAME))
      end

      def self.names
        REGISTRY.keys
      end
    end
  end
end
