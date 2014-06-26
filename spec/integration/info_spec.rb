require "spec_helper"

describe "Cloud Controller", type: :integration, isolation: :truncation do
  before(:all) do
    start_nats
    start_cc
  end

  after(:all) do
    stop_cc
    stop_nats
  end

  it "responds to /info" do
    make_get_request("/info").tap do |r|
      expect(r.code).to eq("200")
      expect(r.json_body["version"]).to eq(2)
      expect(r.json_body["description"]).to eq("Cloud Foundry sponsored by Pivotal")
    end
  end

  it "authenticate and authorize with valid token" do
    unauthorized_token = {"Authorization" => "bearer unauthorized-token"}
    make_get_request("/v2/stacks", unauthorized_token).tap do |r|
      expect(r.code).to eq("401")
    end

    authorized_token = {"Authorization" => "bearer #{admin_token}"}
    make_get_request("/v2/stacks", authorized_token).tap do |r|
      expect(r.code).to eq("200")
      expect(r.json_body["resources"]).to be_a(Array)
    end
  end
end
