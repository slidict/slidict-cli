# frozen_string_literal: true

begin
  require "rack/mock"
rescue LoadError
  Rack = nil
end
require "tmpdir"

RSpec.describe Slidict::Cli::Serve do
  before do
    skip "rack/sinatra dependencies are not installed" unless defined?(Rack::MockRequest)
  end
  describe "the Sinatra app" do
    it "lists slide files in public" do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "demo"))
        File.write(File.join(dir, "demo", "slides.md"), "# Demo")
        File.write(File.join(dir, "notes.txt"), "not a slide")

        app = described_class.new(public_dir: dir).send(:build_app)
        response = Rack::MockRequest.new(app).get("/")

        expect(response.status).to eq(200)
        expect(response.body).to include("demo")
        expect(response.body).to include("demo/slides.md")
        expect(response.body).not_to include("notes.txt")
      end
    end

    it "links to a percent-encoded href that resolves back to a filename with spaces" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "my slide.md"), "# Demo")

        app = described_class.new(public_dir: dir).send(:build_app)
        mock = Rack::MockRequest.new(app)
        index = mock.get("/")

        expect(index.body).to include('href="/my%20slide.md"')

        slide = mock.get("/my%20slide.md")
        expect(slide.status).to eq(200)
      end
    end
  end
end
