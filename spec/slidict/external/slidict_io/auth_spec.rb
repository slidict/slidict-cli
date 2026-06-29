# frozen_string_literal: true

RSpec.describe Slidict::External::SlidictIo::Auth do
  let(:auth) { described_class.new(base_url: "https://slidict.io") }

  def stub_http_response(body, code: "200", message: "OK")
    response = Net::HTTPOK.new("1.1", code, message)
    allow(response).to receive(:body).and_return(body)
    http = instance_double(Net::HTTP, request: response)
    allow(Net::HTTP).to receive(:start).and_yield(http)
    response
  end

  describe "#request_device_code" do
    it "returns the device code details" do
      stub_http_response({ "device_code" => "d", "user_code" => "u", "interval" => 5, "expires_in" => 600 }.to_json)

      result = auth.request_device_code

      expect(result[:device_code]).to eq("d")
      expect(result[:user_code]).to eq("u")
    end

    it "sets connection and read timeouts so a hung API cannot block forever" do
      stub_http_response({ "device_code" => "d", "user_code" => "u" }.to_json)

      auth.request_device_code

      expect(Net::HTTP).to have_received(:start).with(
        anything, anything, use_ssl: anything, open_timeout: 5, read_timeout: 30
      )
    end
  end

  describe "#poll_token" do
    it "returns the token response when access_token is present" do
      stub_http_response({ "access_token" => "tok", "token_type" => "Bearer" }.to_json)

      result = auth.poll_token(device_code: "d")

      expect(result["access_token"]).to eq("tok")
    end

    it "raises Pending while authorization is still pending" do
      stub_http_response({ "error" => "authorization_pending" }.to_json)

      expect { auth.poll_token(device_code: "d") }.to raise_error(described_class::Pending)
    end
  end
end
