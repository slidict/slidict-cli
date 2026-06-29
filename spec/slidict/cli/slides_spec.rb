# frozen_string_literal: true

require "stringio"
require "tmpdir"

RSpec.describe Slidict::Cli::Slides do
  let(:output) { StringIO.new }
  let(:client) { instance_double(Slidict::External::SlidictIo::Client) }
  let(:command) { described_class.new(output: output, client: client) }

  describe "#run" do
    it "prints help with no arguments" do
      status = command.run([])

      expect(status).to eq(0)
      expect(output.string).to include("Usage: slidict slides <command> [options]")
    end

    it "prints an error for an unknown subcommand" do
      status = command.run(["bogus"])

      expect(status).to eq(1)
      expect(output.string).to include("Error: unknown slides command bogus")
    end

    describe "list" do
      it "prints the slides" do
        allow(client).to receive(:list).with(page: nil).and_return(
          "slides" => [{ "id" => 1, "status" => "draft", "visibility" => "public", "title" => "A",
                         "updated_at" => "2026-06-27" }],
          "has_more" => false
        )

        status = command.run(["list"])

        expect(status).to eq(0)
        expect(output.string).to include("#1 [draft/public] A")
      end

      it "passes --page through to the client" do
        allow(client).to receive(:list).with(page: 2).and_return("slides" => [], "has_more" => false)

        command.run(["list", "--page", "2"])

        expect(client).to have_received(:list).with(page: 2)
      end

      it "prints a message when there are no slides" do
        allow(client).to receive(:list).and_return("slides" => [], "has_more" => false)

        command.run(["list"])

        expect(output.string).to include("No slides found.")
      end
    end

    describe "show" do
      it "prints the slide body" do
        allow(client).to receive(:show).with("1").and_return(
          "id" => 1, "title" => "A", "status" => "draft", "visibility" => "public",
          "updated_at" => "2026-06-27", "body" => "hello world"
        )

        status = command.run(%w[show 1])

        expect(status).to eq(0)
        expect(output.string).to include("hello world")
      end

      it "prints an error when the slide does not exist" do
        allow(client).to receive(:show).and_raise(Slidict::External::SlidictIo::Client::NotFound, "not_found")

        status = command.run(%w[show 999])

        expect(status).to eq(1)
        expect(output.string).to include("Error: slide not found")
      end

      it "requires a slide id" do
        status = command.run(["show"])

        expect(status).to eq(1)
        expect(output.string).to include("Error: show requires a slide id")
      end
    end

    describe "create" do
      it "creates a slide from --body" do
        allow(client).to receive(:create)
          .with(title: "Title", body: "hello", body_format: nil, visibility: nil)
          .and_return("id" => 1, "title" => "Title", "status" => "draft", "visibility" => "public",
                      "updated_at" => "2026-06-27", "body" => "hello")

        status = command.run(["create", "--title", "Title", "--body", "hello"])

        expect(status).to eq(0)
        expect(output.string).to include("Created slide #1 (draft)")
      end

      it "accepts a --body value that starts with a dash" do
        allow(client).to receive(:create)
          .with(title: nil, body: "---\nfoo: bar", body_format: nil, visibility: nil)
          .and_return("id" => 1, "title" => nil, "status" => "draft", "visibility" => "public",
                      "updated_at" => "2026-06-27", "body" => "---\nfoo: bar")

        status = command.run(["create", "--body", "---\nfoo: bar"])

        expect(status).to eq(0)
        expect(output.string).to include("Created slide #1 (draft)")
      end

      it "creates a slide from --file" do
        Dir.mktmpdir do |dir|
          path = File.join(dir, "body.md")
          File.write(path, "from file")
          allow(client).to receive(:create)
            .with(title: nil, body: "from file", body_format: nil, visibility: nil)
            .and_return("id" => 2, "title" => nil, "status" => "draft", "visibility" => "public",
                        "updated_at" => "2026-06-27", "body" => "from file")

          status = command.run(["create", "--file", path])

          expect(status).to eq(0)
        end
      end

      it "reports an error instead of crashing when --file does not exist" do
        Dir.mktmpdir do |dir|
          missing_path = File.join(dir, "missing.md")

          status = command.run(["create", "--file", missing_path])

          expect(status).to eq(1)
          expect(output.string).to include("Error: could not read #{missing_path}")
        end
      end

      it "requires a body" do
        status = command.run(["create", "--title", "Title"])

        expect(status).to eq(1)
        expect(output.string).to include("Error: create requires --body or --file")
      end

      it "rejects both --body and --file" do
        status = command.run(["create", "--body", "a", "--file", "b"])

        expect(status).to eq(1)
        expect(output.string).to include("Error: specify only one of --body or --file")
      end

      it "reports rate limiting" do
        allow(client).to receive(:create).and_raise(Slidict::External::SlidictIo::Client::RateLimited, "rate_limited")

        status = command.run(["create", "--body", "hello"])

        expect(status).to eq(1)
        expect(output.string).to include("rate limited")
      end

      it "reports validation errors" do
        error = Slidict::External::SlidictIo::Client::Unprocessable.new(
          "unprocessable", errors: ["body can't be blank"]
        )
        allow(client).to receive(:create).and_raise(error)

        status = command.run(["create", "--body", "hello"])

        expect(status).to eq(1)
        expect(output.string).to include("body can't be blank")
      end
    end

    describe "edit" do
      it "updates a slide" do
        allow(client).to receive(:update)
          .with("1", title: "New", body: nil, body_format: nil, visibility: nil)
          .and_return("id" => 1, "title" => "New", "status" => "draft", "visibility" => "public",
                      "updated_at" => "2026-06-27", "body" => "hello")

        status = command.run(["edit", "1", "--title", "New"])

        expect(status).to eq(0)
        expect(output.string).to include("Updated slide #1 (draft)")
      end

      it "requires a slide id" do
        status = command.run(["edit"])

        expect(status).to eq(1)
        expect(output.string).to include("Error: edit requires a slide id")
      end

      it "tells the user to use the Web UI when the slide is already published" do
        allow(client).to receive(:update).and_raise(Slidict::External::SlidictIo::Client::NotEditable, "not_editable")

        status = command.run(["edit", "1", "--title", "New"])

        expect(status).to eq(1)
        expect(output.string).to include("already published")
        expect(output.string).to include("Web UI")
      end
    end

    it "raises an authentication error when no CLI token is saved" do
      credentials = instance_double(Slidict::External::SlidictIo::Credentials, read_cli_token: nil)
      command = described_class.new(output: output, credentials: credentials)

      status = command.run(["list"])

      expect(status).to eq(1)
      expect(output.string).to include("not authenticated")
    end

    it "logs in automatically when no CLI token is saved and a login flow is injected" do
      credentials = instance_double(Slidict::External::SlidictIo::Credentials)
      allow(credentials).to receive(:read_cli_token).and_return(nil, { access_token: "tok", token_type: "Bearer" })
      allow(Slidict::External::SlidictIo::Client).to receive(:new).and_return(client)
      allow(client).to receive(:list).and_return("slides" => [], "has_more" => false)
      command = described_class.new(output: output, credentials: credentials, reauthenticate: -> { 0 })

      status = command.run(["list"])

      expect(status).to eq(0)
    end

    it "logs in and retries once when the API rejects the token as invalid" do
      credentials = instance_double(Slidict::External::SlidictIo::Credentials,
                                    read_cli_token: { access_token: "tok", token_type: "Bearer" })
      allow(Slidict::External::SlidictIo::Client).to receive(:new).and_return(client)
      attempt = 0
      allow(client).to receive(:create) do
        attempt += 1
        raise Slidict::External::SlidictIo::Client::Unauthorized, "invalid_token" if attempt == 1

        { "id" => 1, "title" => "Title", "status" => "draft", "visibility" => "public",
          "updated_at" => "2026-06-27", "body" => "hello" }
      end
      command = described_class.new(output: output, credentials: credentials, reauthenticate: -> { 0 })

      status = command.run(["create", "--title", "Title", "--body", "hello"])

      expect(status).to eq(0)
      expect(output.string).to include("Created slide #1 (draft)")
    end

    it "logs in and retries once for list when the API rejects the token as invalid" do
      credentials = instance_double(Slidict::External::SlidictIo::Credentials,
                                    read_cli_token: { access_token: "tok", token_type: "Bearer" })
      allow(Slidict::External::SlidictIo::Client).to receive(:new).and_return(client)
      attempt = 0
      allow(client).to receive(:list) do
        attempt += 1
        raise Slidict::External::SlidictIo::Client::Unauthorized, "invalid_token" if attempt == 1

        { "slides" => [], "has_more" => false }
      end
      command = described_class.new(output: output, credentials: credentials, reauthenticate: -> { 0 })

      status = command.run(["list"])

      expect(status).to eq(0)
      expect(output.string).to include("No slides found.")
    end

    it "reports the error when the login flow itself fails after an invalid token" do
      credentials = instance_double(Slidict::External::SlidictIo::Credentials,
                                    read_cli_token: { access_token: "tok", token_type: "Bearer" })
      allow(Slidict::External::SlidictIo::Client).to receive(:new).and_return(client)
      allow(client).to receive(:create).and_raise(Slidict::External::SlidictIo::Client::Unauthorized, "invalid_token")
      command = described_class.new(output: output, credentials: credentials, reauthenticate: -> { 1 })

      status = command.run(["create", "--title", "Title", "--body", "hello"])

      expect(status).to eq(1)
      expect(output.string).to include("Error: invalid_token")
    end
  end

  describe "#publish" do
    it "creates a new draft when no id is given, even for body text starting with a dash" do
      allow(client).to receive(:create)
        .with(title: "Observability", body: "---\nfoo: bar\n---\n# Observability", body_format: "markdown",
              visibility: nil)
        .and_return("id" => 1, "title" => "Observability", "status" => "draft", "visibility" => "public",
                    "updated_at" => "2026-06-27", "body" => "---\nfoo: bar\n---\n# Observability")

      status = command.publish(
        body: "---\nfoo: bar\n---\n# Observability", title: "Observability", body_format: "markdown"
      )

      expect(status).to eq(0)
      expect(output.string).to include("Created slide #1 (draft)")
    end

    it "edits the given draft when an id is given" do
      allow(client).to receive(:update)
        .with("1", title: "Observability", body: "hello", body_format: "markdown", visibility: "unlisted")
        .and_return("id" => 1, "title" => "Observability", "status" => "draft", "visibility" => "unlisted",
                    "updated_at" => "2026-06-27", "body" => "hello")

      status = command.publish(id: "1", body: "hello", title: "Observability", body_format: "markdown",
                               visibility: "unlisted")

      expect(status).to eq(0)
      expect(output.string).to include("Updated slide #1 (draft)")
    end
  end
end
