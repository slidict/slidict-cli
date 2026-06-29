# frozen_string_literal: true

module Slidict
  module Output
    class Renderer
      def render(deck)
        return render_asciidoctor_revealjs(deck) if Format.fetch(deck.framework).body_format == "asciidoc"

        [frontmatter(deck.framework), deck.slides.map { |slide| render_slide(slide) }.join("\n---\n\n")].join("\n")
      end

      private

      def frontmatter(framework)
        body = Format.fetch(framework).frontmatter
        "---\n#{body}\ngenerated: #{Time.now.utc.iso8601}\n---\n"
      end

      def render_slide(slide)
        lines = ["# #{slide.title}", ""]
        lines.concat(slide.bullets.map { |bullet| "- #{bullet}" })
        lines.join("\n")
      end

      def render_asciidoctor_revealjs(deck)
        lines = ["= #{deck.topic}", ":revealjs_theme: white", ":slidict_generated: #{Time.now.utc.iso8601}", ""]
        lines.concat(deck.slides.flat_map { |slide| render_asciidoctor_slide(slide) })
        lines.join("\n")
      end

      def render_asciidoctor_slide(slide)
        ["== #{slide.title}", "", *slide.bullets.map { |bullet| "* #{bullet}" }, ""]
      end
    end
  end
end
