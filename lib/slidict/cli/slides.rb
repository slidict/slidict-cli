# frozen_string_literal: true

module Slidict
  module Cli
    # Implements the `slidict slides <list|show|create|edit>` subcommands.
    class Slides
      def initialize(output:, credentials: nil, client: nil, reauthenticate: nil)
        @output = output
        @credentials = credentials || External::Credentials.new
        @client = client
        @reauthenticate = reauthenticate
      end

      def run(argv)
        options = parse(argv)
        return print_help if options[:help] || options[:subcommand].nil?

        send(options[:subcommand], options)
      rescue ArgumentError => e
        @output.puts "Error: #{e.message}"
        @output.puts
        print_help
        1
      end

      # Creates or edits a draft directly, bypassing argv parsing (and its
      # "looks like a flag" checks, which would reject body text such as
      # YAML frontmatter that happens to start with "-").
      def publish(body:, id: nil, title: nil, body_format: nil, visibility: nil)
        options = { id: id, title: title, body: body, body_format: body_format, visibility: visibility }
        id ? edit(options) : create(options)
      end

      private

      def parse(argv)
        args = argv.dup
        subcommand = args.shift
        return { help: true } if subcommand.nil? || %w[-h --help].include?(subcommand)

        case subcommand
        when "list" then parse_list(args)
        when "show" then parse_show(args)
        when "create" then parse_create(args)
        when "edit" then parse_edit(args)
        else raise ArgumentError, "unknown slides command #{subcommand}"
        end
      end

      def parse_list(args)
        options = { subcommand: :list }
        until args.empty?
          case (arg = args.shift)
          when "--page" then options[:page] = Integer(fetch_value!(args, arg))
          when "-h", "--help" then options[:help] = true
          else raise ArgumentError, "unknown option #{arg}"
          end
        end
        options
      end

      def parse_show(args)
        id = args.shift
        raise ArgumentError, "show requires a slide id" if id.nil?
        raise ArgumentError, "unknown option #{args.first}" unless args.empty?

        { subcommand: :show, id: id }
      end

      def parse_create(args)
        options = { subcommand: :create }
        parse_body_options!(args, options)
        options
      end

      def parse_edit(args)
        id = args.shift
        raise ArgumentError, "edit requires a slide id" if id.nil?

        options = { subcommand: :edit, id: id }
        parse_body_options!(args, options)
        options
      end

      def parse_body_options!(args, options)
        until args.empty?
          case (arg = args.shift)
          when "--title" then options[:title] = fetch_value!(args, arg)
          when "--body" then options[:body] = fetch_value!(args, arg)
          when "--file" then options[:file] = fetch_value!(args, arg)
          when "--body-format" then options[:body_format] = fetch_value!(args, arg)
          when "--visibility" then options[:visibility] = fetch_value!(args, arg)
          when "-h", "--help" then options[:help] = true
          else raise ArgumentError, "unknown option #{arg}"
          end
        end
        raise ArgumentError, "specify only one of --body or --file" if options[:body] && options[:file]
      end

      def fetch_value!(args, option)
        value = args.shift
        raise ArgumentError, "#{option} requires a value" if value.nil? || value.start_with?("-")

        value
      end

      def list(options)
        print_slide_list(client.list(page: options[:page]))
        0
      rescue External::SlidesClient::Error => e
        print_client_error(e)
      end

      def show(options)
        print_slide_detail(client.show(options[:id]))
        0
      rescue External::SlidesClient::NotFound
        @output.puts "Error: slide not found"
        1
      rescue External::SlidesClient::Error => e
        print_client_error(e)
      end

      def create(options)
        body = read_body(options)
        raise ArgumentError, "create requires --body or --file" if body.to_s.strip.empty?

        submit("Created") do
          client.create(title: options[:title], body: body, body_format: options[:body_format],
                        visibility: options[:visibility])
        end
      end

      def edit(options)
        submit("Updated") do
          client.update(options[:id], title: options[:title], body: read_body(options),
                                      body_format: options[:body_format], visibility: options[:visibility])
        end
      end

      def submit(verb)
        reauthenticated = false
        begin
          slide = yield
          @output.puts "#{verb} slide ##{slide["id"]} (draft)"
          print_slide_detail(slide)
          0
        rescue External::SlidesClient::NotFound
          @output.puts "Error: slide not found"
          1
        rescue External::SlidesClient::NotEditable
          @output.puts "Error: this slide is already published. Edit it from the Web UI instead."
          1
        rescue External::SlidesClient::RateLimited
          print_rate_limited
        rescue External::SlidesClient::Unprocessable => e
          print_unprocessable(e)
        rescue External::SlidesClient::Unauthorized => e
          if !reauthenticated && reauthenticate!
            reauthenticated = true
            retry
          end
          print_client_error(e)
        rescue External::SlidesClient::Error => e
          print_client_error(e)
        end
      end

      def read_body(options)
        return File.read(options[:file]) if options[:file]

        options[:body]
      end

      def client
        @client ||= begin
          token = @credentials.read_cli_token
          token = @credentials.read_cli_token if token.nil? && reauthenticate!
          raise ArgumentError, "not authenticated. Run `slidict auth` first." unless token

          External::SlidesClient.new(access_token: token[:access_token], token_type: token[:token_type])
        end
      end

      # Triggers the injected login flow (see Slidict::Cli::App#auth) and clears the
      # memoized client so the next call to `client` picks up the fresh token.
      def reauthenticate!
        return false unless @reauthenticate

        @client = nil
        @reauthenticate.call.zero?
      end

      def print_slide_list(result)
        slides = result["slides"] || []
        if slides.empty?
          @output.puts "No slides found."
          return
        end

        slides.each do |slide|
          @output.puts "##{slide["id"]} [#{slide["status"]}/#{slide["visibility"]}] " \
                       "#{slide["title"]} (updated_at: #{slide["updated_at"]})"
        end
        @output.puts "(more slides available, use --page to see the next page)" if result["has_more"]
      end

      def print_slide_detail(slide)
        @output.puts "##{slide["id"]} #{slide["title"]}"
        @output.puts "status: #{slide["status"]}  visibility: #{slide["visibility"]}  " \
                     "updated_at: #{slide["updated_at"]}"
        @output.puts
        @output.puts slide["body"]
      end

      def print_rate_limited
        @output.puts "Error: rate limited. Create/edit is limited to once per minute. Wait and try again."
        1
      end

      def print_unprocessable(error)
        @output.puts "Error: #{error.message}"
        error.errors.each { |message| @output.puts "  - #{message}" }
        1
      end

      def print_client_error(error)
        @output.puts "Error: #{error.message}"
        1
      end

      def print_help
        @output.puts <<~HELP
          Usage: slidict slides <command> [options]

          Commands:
            list [--page N]      List your slides (20 per page)
            show <id>             Show a slide's details and body
            create [options]      Create a new draft slide
            edit <id> [options]   Edit an existing draft slide

          Create/edit options:
              --title TEXT         Slide title
              --body TEXT          Slide body text
              --file PATH          Read the slide body from a file (instead of --body)
              --body-format FORMAT asciidoc or markdown (default: auto-detected from body)
              --visibility VIS     public, unlisted, or group_only (default: public)
          -h, --help                Show this help

          Note: slides are always created/edited as drafts. Publish from the Web UI.
        HELP
        0
      end
    end
  end
end
