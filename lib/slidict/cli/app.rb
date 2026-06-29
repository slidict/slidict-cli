# frozen_string_literal: true

require "fileutils"
require "pathname"

module Slidict
  module Cli
    class App
      def initialize(input: $stdin, output: $stdout, renderer: Output::Renderer.new, auth_client: nil,
                     credentials: nil, sleeper: Kernel, slides_command: nil, server: nil)
        @input = input
        @output = output
        @renderer = renderer
        @auth_client = auth_client
        @credentials = credentials
        @sleeper = sleeper
        @slides_command = slides_command
        @server = server
      end

      def run(argv = [])
        options = parse(argv)
        return print_help if options[:help]
        return auth if options[:command] == "auth"
        return slides(options[:args]) if options[:command] == "slides"
        return serve(options[:args]) if options[:command] == "serve"

        config = build_config(options)
        client = llm_client_for(config)
        return 1 if client && !verify_connection(client)

        deck = Deck.new(
          topic: ask("What would you like to talk about?", options[:topic]),
          duration: ask("How long is the presentation?", options[:duration]),
          audience: ask("Who is the audience?", options[:audience]),
          goal: ask("What should the audience remember or do?", options[:goal]),
          framework: options[:framework]
        )

        if client
          begin
            slides = client.generate_slides(deck)
          rescue Llm::Client::Error => e
            @output.puts "Error: LLM request failed (#{e.message})"
            return 1
          end
          deck = Deck.new(
            topic: deck.topic, duration: deck.duration, audience: deck.audience, goal: deck.goal,
            framework: deck.framework, slides: slides
          )
        end

        path = options[:output]
        content = @renderer.render(deck)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, content)
        @output.puts "Created #{path}"

        return publish_to_slidict(deck, content, options) if options[:publish] || options[:slide_id]

        0
      rescue ArgumentError => e
        @output.puts "Error: #{e.message}"
        @output.puts
        print_help
        1
      end

      private

      def parse(argv)
        options = { framework: "slidev" }
        args = argv.dup

        if args.first == "auth"
          args.shift
          raise ArgumentError, "auth does not accept options" unless args.empty?

          options[:command] = "auth"
          return options
        end

        if args.first == "slides"
          args.shift
          options[:command] = "slides"
          options[:args] = args
          return options
        end

        if args.first == "serve"
          args.shift
          options[:command] = "serve"
          options[:args] = args
          return options
        end

        until args.empty?
          case (arg = args.shift)
          when "-h", "--help"
            options[:help] = true
          when "-o", "--output"
            options[:output] = fetch_value!(args, arg)
          when "--filename"
            options[:filename] = fetch_value!(args, arg)
          when "--topic"
            options[:topic] = fetch_value!(args, arg)
          when "--duration"
            options[:duration] = fetch_value!(args, arg)
          when "--audience"
            options[:audience] = fetch_value!(args, arg)
          when "--goal"
            options[:goal] = fetch_value!(args, arg)
          when "--framework"
            options[:framework] = fetch_value!(args, arg)
          when "--llm-base-url"
            options[:llm_base_url] = fetch_value!(args, arg)
          when "--llm-api-key"
            options[:llm_api_key] = fetch_value!(args, arg)
          when "--llm-model"
            options[:llm_model] = fetch_value!(args, arg)
          when "--no-llm"
            options[:no_llm] = true
          when "--publish"
            options[:publish] = true
          when "--slide-id"
            options[:slide_id] = fetch_value!(args, arg)
          when "--slide-title"
            options[:slide_title] = fetch_value!(args, arg)
          when "--visibility"
            options[:visibility] = fetch_value!(args, arg)
          else
            raise ArgumentError, "unknown option #{arg}"
          end
        end

        options[:output] ||= output_path_for(options[:framework], options[:filename])
        options
      end

      def build_config(options)
        Config.from_env.merge(
          base_url: options[:llm_base_url],
          api_key: options[:llm_api_key],
          model: options[:llm_model],
          enabled: options[:no_llm] ? false : nil
        )
      end

      def llm_client_for(config)
        return nil unless config.llm_enabled?

        Llm::Client.new(base_url: config.base_url, api_key: config.api_key, model: config.model)
      end

      def verify_connection(client)
        client.verify_connection!
        true
      rescue Llm::Client::Error => e
        @output.puts "Error: LLM request failed (#{e.message})"
        false
      end

      def auth
        client = @auth_client || External::SlidictIo::Auth.new
        credentials = @credentials || External::SlidictIo::Credentials.new

        device = client.request_device_code
        @output.puts "1. Open #{device[:verification_uri]} in your browser"
        @output.puts "2. Enter code: #{device[:user_code]}"
        @output.puts "3. Log in with GitHub"
        @output.puts "Waiting for GitHub authentication..."

        deadline = Time.now + device[:expires_in]
        loop do
          token = client.poll_token(device_code: device[:device_code])
          path = credentials.write_cli_token!(
            access_token: token.fetch("access_token"),
            token_type: token.fetch("token_type", "Bearer"),
            provider: token.fetch("provider", "github")
          )
          @output.puts "4. Saved CLI access token to #{path}"
          return 0
        rescue External::SlidictIo::Auth::Pending
          return login_expired if Time.now >= deadline

          @sleeper.sleep(device[:interval])
        end
      rescue External::SlidictIo::Auth::Error, KeyError => e
        @output.puts "Error: GitHub auth failed (#{e.message})"
        1
      end

      def slides(args)
        slides_command.run(args)
      end

      def serve(args)
        server.run(args)
      end

      def publish_to_slidict(deck, content, options)
        slides_command.publish(
          id: options[:slide_id],
          title: options[:slide_title] || deck.topic,
          body: content,
          body_format: body_format_for(deck.framework),
          visibility: options[:visibility]
        )
      end

      def slides_command
        @slides_command ||= Slides.new(output: @output, credentials: @credentials, reauthenticate: method(:auth))
      end

      def server
        @server ||= Serve.new(output: @output)
      end

      def body_format_for(framework)
        Output::Format.fetch(framework).body_format
      end

      def login_expired
        @output.puts "Error: GitHub auth timed out. Run `slidict auth` and try again."
        1
      end

      def fetch_value!(args, option)
        value = args.shift
        raise ArgumentError, "#{option} requires a value" if value.nil? || value.start_with?("-")

        value
      end

      def ask(question, provided)
        return provided unless provided.nil? || provided.strip.empty?

        @output.puts question
        @output.print "> "
        @input.gets&.chomp.to_s
      end

      def print_help
        @output.puts <<~HELP
          Usage: slidict [options]
          Usage: slidict auth
          Usage: slidict slides <list|show|create|edit> [options]
          Usage: slidict serve [sinatra options]

          Generate presentation source files from a short conversation.

          Commands:
            auth             Authenticate the CLI with GitHub and save a CLI access token
            slides           Manage your slides on slidict.io (run `slidict slides -h` for details)
            serve            Serve slide files from ./public with Sinatra

          Options:
              --topic TEXT       Presentation topic
              --duration TEXT    Presentation length, for example "5 minutes"
              --audience TEXT    Target audience
              --goal TEXT        Desired audience takeaway or action
              --framework NAME   #{Output::Format.names.join(", ")} (default: slidev)
              --filename NAME    File name under public/ (default: next sequential file)
              --llm-base-url URL OpenAI Compatible API base URL (env: SLIDICT_LLM_BASE_URL).
                                 When omitted, the built-in slide template is used instead.
              --llm-api-key KEY  API key for the LLM endpoint (env: SLIDICT_LLM_API_KEY)
              --llm-model NAME   Model name to request (env: SLIDICT_LLM_MODEL, default: gpt-4o-mini)
              --no-llm           Skip the LLM call and use the built-in slide template
              --publish          Publish the generated slides to slidict.io as a draft
                                 (requires `slidict auth`; creates a new slide, or edits
                                 an existing one when --slide-id is given)
              --slide-id ID      Edit this existing draft instead of creating a new one
                                 (implies --publish)
              --slide-title TEXT Title for the published slide (default: --topic)
              --visibility VIS   public, unlisted, or group_only (default: public)
          -o, --output PATH      Output file (overrides --filename and the public/ default)
          -h, --help             Show this help
        HELP
        0
      end

      def output_path_for(framework, filename)
        return File.join("public", normalize_filename(filename, framework)) if filename

        next_sequential_output_for(framework)
      end

      def normalize_filename(filename, framework)
        path = filename.to_s.strip
        raise ArgumentError, "--filename requires a relative path under public" if path.empty?
        raise ArgumentError, "--filename must be relative" if Pathname.new(path).absolute?
        raise ArgumentError, "--filename cannot include .." if Pathname.new(path).each_filename.any?("..")

        # --filename is already relative to public/, so drop a redundant leading
        # "public/" instead of nesting it twice (public/public/...).
        path = path.delete_prefix("public/")
        File.extname(path).empty? ? "#{path}#{default_extension_for(framework)}" : path
      end

      def next_sequential_output_for(framework)
        extension = default_extension_for(framework)
        number = 1
        loop do
          path = File.join("public", format("%03d%s", number, extension))
          return path unless File.exist?(path)

          number += 1
        end
      end

      def default_extension_for(framework)
        Output::Format.fetch(framework).extension
      end
    end
  end
end
