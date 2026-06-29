# frozen_string_literal: true

RSpec.describe Slidict::Llm::Client do
  let(:client) { described_class.new(base_url: "http://localhost:11434/v1", api_key: "ollama", model: "llama3") }
  let(:deck) { Slidict::Deck.new(topic: "Observability", duration: "5 minutes", audience: "SREs", goal: "adopt the checklist") }

  def stub_http_response(body, code: "200", message: "OK")
    response = Net::HTTPOK.new("1.1", code, message)
    allow(response).to receive(:body).and_return(body)
    http = instance_double(Net::HTTP, request: response)
    allow(Net::HTTP).to receive(:start).and_yield(http)
  end

  describe "#verify_connection!" do
    it "does not raise when the endpoint responds successfully" do
      stub_http_response({ "data" => [] }.to_json)

      expect { client.verify_connection! }.not_to raise_error
    end

    it "raises an Error when the endpoint responds with a failure" do
      response = Net::HTTPBadRequest.new("1.1", "400", "Bad Request")
      allow(response).to receive(:body).and_return("")
      http = instance_double(Net::HTTP, request: response)
      allow(Net::HTTP).to receive(:start).and_yield(http)

      expect { client.verify_connection! }.to raise_error(Slidict::Llm::Client::Error, /400/)
    end

    it "raises an Error when the connection is refused" do
      allow(Net::HTTP).to receive(:start).and_raise(Errno::ECONNREFUSED, "connection refused")

      expect { client.verify_connection! }.to raise_error(Slidict::Llm::Client::Error)
    end
  end

  describe "#generate_slides" do
    it "parses a successful chat completion into slides" do
      content = [{ "title" => "Observability", "bullets" => ["Why it matters", "What changes"] }].to_json
      stub_http_response({ "choices" => [{ "message" => { "content" => content } }] }.to_json)

      slides = client.generate_slides(deck)

      expect(slides.size).to eq(1)
      expect(slides.first.title).to eq("Observability")
      expect(slides.first.bullets).to eq(["Why it matters", "What changes"])
    end

    it "raises an Error when the HTTP response is not successful" do
      response = Net::HTTPBadRequest.new("1.1", "400", "Bad Request")
      allow(response).to receive(:body).and_return("")
      http = instance_double(Net::HTTP, request: response)
      allow(Net::HTTP).to receive(:start).and_yield(http)

      expect { client.generate_slides(deck) }.to raise_error(Slidict::Llm::Client::Error, /400/)
    end

    it "raises an Error when the model response is not valid JSON" do
      stub_http_response({ "choices" => [{ "message" => { "content" => "not json" } }] }.to_json)

      expect { client.generate_slides(deck) }.to raise_error(Slidict::Llm::Client::Error, /no JSON array found/)
    end

    it "extracts the JSON array even when the model wraps it in reasoning text" do
      json = [{ "title" => "Observability", "bullets" => ["a", "b"] }].to_json
      content = "<|channel|>thought<|message|>let me think...<|end|>#{json}\nDone."
      stub_http_response({ "choices" => [{ "message" => { "content" => content } }] }.to_json)

      slides = client.generate_slides(deck)

      expect(slides.first.title).to eq("Observability")
    end

    it "raises an Error when the network request fails" do
      allow(Net::HTTP).to receive(:start).and_raise(SocketError, "connection refused")

      expect { client.generate_slides(deck) }.to raise_error(Slidict::Llm::Client::Error, /connection refused/)
    end
  end

  describe "#lint_slides" do
    it "parses a successful chat completion into findings" do
      findings_json = [
        { "slide" => 3, "severity" => "warning", "message" => "this slide's main point is unclear" },
        { "slide" => 8, "severity" => "info", "message" => "consider adding a one-sentence takeaway" }
      ].to_json
      stub_http_response({ "choices" => [{ "message" => { "content" => findings_json } }] }.to_json)

      findings = client.lint_slides(["# Title", "# Second"])

      expect(findings.size).to eq(2)
      expect(findings.first.slide).to eq(3)
      expect(findings.first.severity).to eq("warning")
      expect(findings.first.message).to eq("this slide's main point is unclear")
      expect(findings.last.severity).to eq("info")
    end

    it "returns an empty array when the model finds no issues" do
      stub_http_response({ "choices" => [{ "message" => { "content" => "[]" } }] }.to_json)

      expect(client.lint_slides(["# Title"])).to eq([])
    end

    it "defaults an unrecognized severity to info" do
      findings_json = [{ "slide" => 1, "severity" => "critical", "message" => "x" }].to_json
      stub_http_response({ "choices" => [{ "message" => { "content" => findings_json } }] }.to_json)

      expect(client.lint_slides(["# Title"]).first.severity).to eq("info")
    end

    it "raises an Error when the model response is not valid JSON" do
      stub_http_response({ "choices" => [{ "message" => { "content" => "not json" } }] }.to_json)

      expect { client.lint_slides(["# Title"]) }.to raise_error(Slidict::Llm::Client::Error, /no JSON array found/)
    end

    it "raises an Error when a finding is missing a required field" do
      findings_json = [{ "slide" => 1, "severity" => "warning" }].to_json
      stub_http_response({ "choices" => [{ "message" => { "content" => findings_json } }] }.to_json)

      expect { client.lint_slides(["# Title"]) }.to raise_error(Slidict::Llm::Client::Error, /could not parse/)
    end

    it "includes the translate language in the prompt when translate: is given" do
      findings_json = [].to_json
      http = instance_double(Net::HTTP)
      response = Net::HTTPOK.new("1.1", "200", "OK")
      allow(response).to receive(:body).and_return({ "choices" => [{ "message" => { "content" => findings_json } }] }.to_json)
      request_body = nil
      allow(http).to receive(:request) { |req| request_body = req.body; response }
      allow(Net::HTTP).to receive(:start).and_yield(http)

      client.lint_slides(["# Title"], translate: "Japanese")

      expect(JSON.parse(request_body)["messages"].first["content"]).to include("Japanese")
    end

    it "does not add a translate instruction when translate: is nil" do
      findings_json = [].to_json
      http = instance_double(Net::HTTP)
      response = Net::HTTPOK.new("1.1", "200", "OK")
      allow(response).to receive(:body).and_return({ "choices" => [{ "message" => { "content" => findings_json } }] }.to_json)
      request_body = nil
      allow(http).to receive(:request) { |req| request_body = req.body; response }
      allow(Net::HTTP).to receive(:start).and_yield(http)

      client.lint_slides(["# Title"])

      expect(JSON.parse(request_body)["messages"].first["content"]).not_to include("Write each message field in")
    end
  end
end
