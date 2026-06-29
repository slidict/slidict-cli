# frozen_string_literal: true

module Slidict
  module Lint
    # Orchestrates a lint run: splits the raw deck source into slides and
    # asks the LLM client to diagnose the presentation's structure.
    class Linter
      class Error < StandardError; end

      def initialize(client:)
        @client = client
      end

      def lint(content, format: "markdown", translate: nil)
        slides = SlideParser.parse(content, format: format)
        raise Error, "no slides found in the given file" if slides.empty?

        @client.lint_slides(slides, translate: translate)
      end
    end
  end
end
