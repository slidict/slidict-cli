# frozen_string_literal: true

module Slidict
  module Cli
    # Implements `slidict lint <file>`: diagnoses whether a Markdown/Asciidoc
    # slide deck has a structure that an audience can actually follow (not
    # whether it looks nice). Diagnosis only -- it does not rewrite the file.
    class Lint
      ASCIIDOC_EXTENSIONS = %w[.adoc .asciidoc].freeze

      def initialize(output:, linter_factory: nil, renderer: Slidict::Lint::Renderer.new)
        @output = output
        @linter_factory = linter_factory || method(:default_linter)
        @renderer = renderer
      end

      def run(argv)
        options = parse(argv)
        return print_help if options[:help] || options[:path].nil?
        return file_not_found(options[:path]) unless File.exist?(options[:path])

        run_lint(options)
      rescue ArgumentError => e
        print_usage_error(e)
      rescue Slidict::Lint::Linter::Error, Llm::Client::Error => e
        print_error(e)
      end

      private

      def run_lint(options)
        config = build_config(options)
        return llm_required unless config.llm_enabled?

        print_findings(lint(options, config))
      end

      def lint(options, config)
        @linter_factory.call(config).lint(File.read(options[:path]), format: format_for(options), translate: options[:translate])
      end

      def print_usage_error(error)
        print_error(error)
        @output.puts
        print_help
        1
      end

      def print_error(error)
        @output.puts "Error: #{error.message}"
        1
      end

      def parse(argv)
        args = argv.dup
        options = { path: extract_path!(args) }
        parse_options!(args, options)
        options
      end

      def extract_path!(args)
        args.shift unless args.first.to_s.start_with?("-")
      end

      def parse_options!(args, options)
        until args.empty?
          case (arg = args.shift)
          when "-h", "--help" then options[:help] = true
          when "--format" then options[:format] = fetch_value!(args, arg)
          when "--llm-base-url" then options[:llm_base_url] = fetch_value!(args, arg)
          when "--llm-api-key" then options[:llm_api_key] = fetch_value!(args, arg)
          when "--llm-model" then options[:llm_model] = fetch_value!(args, arg)
          when "--translate" then options[:translate] = fetch_value!(args, arg)
          else raise ArgumentError, "unknown option #{arg}"
          end
        end
      end

      def fetch_value!(args, option)
        value = args.shift
        raise ArgumentError, "#{option} requires a value" if value.nil? || value.start_with?("-")

        value
      end

      def build_config(options)
        Config.from_env.merge(
          base_url: options[:llm_base_url],
          api_key: options[:llm_api_key],
          model: options[:llm_model]
        )
      end

      def default_linter(config)
        client = Llm::Client.new(base_url: config.base_url, api_key: config.api_key, model: config.model)
        Slidict::Lint::Linter.new(client: client)
      end

      def format_for(options)
        return options[:format] if options[:format]

        ASCIIDOC_EXTENSIONS.include?(File.extname(options[:path]).downcase) ? "asciidoc" : "markdown"
      end

      def print_findings(findings)
        @output.puts(findings.empty? ? "No issues found." : @renderer.render(findings))
        0
      end

      def file_not_found(path)
        @output.puts "Error: file not found: #{path}"
        1
      end

      def llm_required
        @output.puts "Error: lint requires an LLM endpoint (--llm-base-url or SLIDICT_LLM_BASE_URL)"
        1
      end

      def print_help
        @output.puts <<~HELP
          Usage: slidict lint <file> [options]
          Diagnoses whether a slide deck's structure will land with its audience.
              --format FORMAT     markdown or asciidoc (default: auto-detected from extension)
              --llm-base-url URL  OpenAI Compatible API base URL (env: SLIDICT_LLM_BASE_URL)
              --llm-api-key KEY   API key for the LLM endpoint (env: SLIDICT_LLM_API_KEY)
              --llm-model NAME    Model name to request (env: SLIDICT_LLM_MODEL, default: gpt-4o-mini)
              --translate LANG    Translate findings into the given language (e.g. Japanese)
          -h, --help               Show this help
        HELP
        0
      end
    end
  end
end
