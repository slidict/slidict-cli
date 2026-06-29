# frozen_string_literal: true

RSpec.describe Slidict::Lint::Linter do
  let(:client) { instance_double(Slidict::Llm::Client) }
  let(:linter) { described_class.new(client: client) }

  describe "#lint" do
    it "parses the deck into slides and delegates to the client" do
      content = "# Title\n\n---\n\n# Second"
      findings = [Slidict::Lint::Finding.new(slide: 1, severity: "warning", message: "x")]
      allow(client).to receive(:lint_slides).with(["# Title", "# Second"], translate: nil).and_return(findings)

      expect(linter.lint(content, format: "markdown")).to eq(findings)
    end

    it "raises an Error when the deck has no slides" do
      expect { linter.lint("", format: "markdown") }.to raise_error(described_class::Error, /no slides/)
    end
  end
end
