# frozen_string_literal: true

require "cgi"
require "pathname"

module Slidict
  class Server
    DEFAULT_PUBLIC_DIR = "public"

    def self.run(args = [], public_dir: DEFAULT_PUBLIC_DIR, output: $stdout)
      new(public_dir: public_dir, output: output).run(args)
    end

    def initialize(public_dir: DEFAULT_PUBLIC_DIR, output: $stdout)
      @public_dir = File.expand_path(public_dir)
      @output = output
    end

    def run(args = [])
      require "sinatra/base"

      app = build_app
      original_argv = ARGV.dup
      ARGV.replace(args)
      @output.puts "Serving slides from #{@public_dir}"
      app.run!
      0
    ensure
      ARGV.replace(original_argv) if original_argv
    end

    private

    def build_app
      public_dir = @public_dir

      Class.new(Sinatra::Base) do
        set :public_folder, public_dir
        set :static, true
        set :show_exceptions, false

        get "/" do
          @public_dir = public_dir
          @entries = slide_entries(public_dir)
          erb INDEX_TEMPLATE
        end

        helpers do
          def slide_entries(public_dir)
            return [] unless Dir.exist?(public_dir)

            Dir.glob(File.join(public_dir, "**", "*")).filter_map do |path|
              next unless File.file?(path)

              relative = Pathname.new(path).relative_path_from(Pathname.new(public_dir)).to_s
              next unless slide_file?(relative)

              { title: title_for(relative), href: "/#{escape_path(relative)}", path: relative }
            end.sort_by { |entry| entry[:path] }
          end

          def slide_file?(path)
            File.extname(path).match?(/\A\.(?:adoc|md|markdown)\z/i)
          end

          def title_for(path)
            dirname = File.dirname(path)
            basename = File.basename(path, File.extname(path))
            dirname == "." ? basename : dirname
          end

          def escape_path(path)
            path.split("/").map { |segment| CGI.escape(segment) }.join("/")
          end

          def h(text)
            CGI.escapeHTML(text.to_s)
          end
        end
      end
    end

    INDEX_TEMPLATE = <<~ERB.freeze
      <!doctype html>
      <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>Slidict slides</title>
          <style>
            body { font-family: system-ui, sans-serif; margin: 2rem; }
            li { margin: 0.5rem 0; }
            code { color: #555; }
          </style>
        </head>
        <body>
          <h1>Slidict slides</h1>
          <% if @entries.empty? %>
            <p>No slides found in <code><%= h(@public_dir) %></code>.</p>
          <% else %>
            <ul>
              <% @entries.each do |entry| %>
                <li><a href="<%= entry[:href] %>"><%= h(entry[:title]) %></a> <code><%= h(entry[:path]) %></code></li>
              <% end %>
            </ul>
          <% end %>
        </body>
      </html>
    ERB
  end
end
