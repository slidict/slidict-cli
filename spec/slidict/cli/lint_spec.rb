# frozen_string_literal: true

require "stringio"
require "tmpdir"

RSpec.describe Slidict::Cli::Lint do
  let(:output) { StringIO.new }
  let(:linter) { instance_double(Slidict::Lint::Linter) }
  let(:cli) { described_class.new(output: output, linter_factory: ->(_config) { linter }) }

  around do |example|
    Dir.mktmpdir do |dir|
      @dir = dir
      example.run
    end
  end

  def write_deck(name = "talk.md", content = "# Title\n\n- bullet")
    path = File.join(@dir, name)
    File.write(path, content)
    path
  end

  describe "#run" do
    it "prints findings returned by the linter" do
      path = write_deck
      findings = [Slidict::Lint::Finding.new(slide: 3, severity: "warning", message: "the point is unclear")]
      allow(linter).to receive(:lint).with(File.read(path), format: "markdown", translate: nil).and_return(findings)

      status = cli.run([path, "--llm-base-url", "http://localhost:11434/v1"])

      expect(status).to eq(0)
      expect(output.string).to include("[warning] Slide 3: the point is unclear")
    end

    it "prints a message when no issues are found" do
      path = write_deck
      allow(linter).to receive(:lint).and_return([])

      status = cli.run([path, "--llm-base-url", "http://localhost:11434/v1"])

      expect(status).to eq(0)
      expect(output.string).to include("No issues found.")
    end

    it "auto-detects asciidoc from the file extension" do
      path = write_deck("talk.adoc", "= Title\n\n== First\n\n* one")
      expect(linter).to receive(:lint).with(anything, format: "asciidoc", translate: nil).and_return([])

      cli.run([path, "--llm-base-url", "http://localhost:11434/v1"])
    end

    it "passes the translate language to the linter" do
      path = write_deck
      expect(linter).to receive(:lint).with(anything, format: "markdown", translate: "Japanese").and_return([])

      cli.run([path, "--llm-base-url", "http://localhost:11434/v1", "--translate", "Japanese"])
    end

    it "requires an LLM endpoint to be configured" do
      path = write_deck

      status = cli.run([path])

      expect(status).to eq(1)
      expect(output.string).to include("requires an LLM endpoint")
    end

    it "errors when the file does not exist" do
      status = cli.run(["missing.md", "--llm-base-url", "http://localhost:11434/v1"])

      expect(status).to eq(1)
      expect(output.string).to include("file not found")
    end

    it "errors when no path is given" do
      status = cli.run([])

      expect(status).to eq(0)
      expect(output.string).to include("Usage: slidict lint")
    end

    it "surfaces linter errors" do
      path = write_deck
      allow(linter).to receive(:lint).and_raise(Slidict::Lint::Linter::Error, "no slides found in the given file")

      status = cli.run([path, "--llm-base-url", "http://localhost:11434/v1"])

      expect(status).to eq(1)
      expect(output.string).to include("Error: no slides found in the given file")
    end
  end
end
