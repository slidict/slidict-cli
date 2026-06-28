# frozen_string_literal: true

begin
  require "rack/mock"
rescue LoadError
  Rack = nil
end
require "tmpdir"

RSpec.describe Slidict::Server do
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
  end
end
