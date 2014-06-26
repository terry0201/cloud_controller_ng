require 'spec_helper'
require 'rspec_api_documentation/dsl'

resource "Service Brokers", :type => :api do
  let(:admin_auth_header) { admin_headers["HTTP_AUTHORIZATION"] }
  let!(:service_brokers) { 3.times { VCAP::CloudController::ServiceBroker.make } }
  let(:service_broker) { VCAP::CloudController::ServiceBroker.first }
  let(:guid) { service_broker.guid }
  let(:broker_catalog) do
    {
      'services' => [
        {
          'id'          => 'custom-service-1',
          'name'        => 'custom-service',
          'description' => 'A description of My Custom Service',
          'bindable'    => true,
          'plans'       => [
            {
              'id'          => 'custom-plan',
              'name'        => 'free',
              'description' => 'Free plan!'
            }
          ]
        }
      ]
    }.to_json
  end

  authenticated_request

  field :name, "The name of the service broker.", required: true, example_values: %w(service-broker-name)
  field :broker_url, "The URL of the service broker.", required: true, example_values: %w(https://broker.example.com)
  field :auth_username, "The username with which to authenticate against the service broker.", required: true, example_values: %w(admin)
  field :auth_password, "The password with which to authenticate against the service broker.", required: true, example_values: %w(secretpassw0rd)

  get "/v2/service_brokers" do
    request_parameter :q, "Parameters used to filter the result set. Valid filters: 'name'"

    example "List all Service Brokers" do
      client.get "/v2/service_brokers", {}, headers
      service_brokers = parsed_response["resources"]

      expect(status).to eq(200)
      validate_response VCAP::RestAPI::PaginatedResponse, parsed_response
      expect(service_brokers.size).to eq(3)
      service_brokers.each do |broker|
        validate_response VCAP::RestAPI::MetadataMessage, broker["metadata"]
        expect(broker["entity"].keys).to include("name", "broker_url", "auth_username")
      end
    end
  end

  post "/v2/service_brokers" do
    before do
      stub_request(:get, "https://admin:secretpassw0rd@broker.example.com:443/v2/catalog").
        with(:headers => {"Accept" => "application/json"}).
        to_return(status: 200, body: broker_catalog, headers: {})
    end

    example "Create a Service Broker" do
      client.post "/v2/service_brokers", fields_json, headers

      expect(status).to eq 201
      validate_response VCAP::RestAPI::MetadataMessage, parsed_response["metadata"]
      expect(parsed_response["entity"]["name"]).to eq("service-broker-name")
      expect(parsed_response["entity"]["broker_url"]).to eq("https://broker.example.com")
      expect(parsed_response["entity"]["auth_username"]).to eq("admin")

      document_warning_header(response_headers)
    end
  end

  delete "/v2/service_brokers/:guid" do
    request_parameter :guid, "The guid of the service broker being deleted."

    example "Delete a Service Broker" do
      client.delete "/v2/service_brokers/#{guid}", {}, headers
      expect(status).to eq 204
    end
  end

  put "/v2/service_brokers/:guid" do
    before do
      stub_request(:get, "https://admin:secretpassw0rd@broker.example.com:443/v2/catalog").
        with(:headers => {'Accept' => 'application/json'}).
        to_return(status: 200, body: broker_catalog, headers: {})
    end

    request_parameter :guid, "The guid of the service broker being updated."

    example "Update a Service Broker" do
      client.put "/v2/service_brokers/#{guid}", fields_json, headers

      expect(status).to eq 200
      validate_response VCAP::RestAPI::MetadataMessage, parsed_response["metadata"]
      expect(parsed_response["entity"]["broker_url"]).to eq("https://broker.example.com")
      expect(parsed_response["entity"]["name"]).to eq("service-broker-name")
      expect(parsed_response["entity"]["auth_username"]).to eq("admin")

      document_warning_header(response_headers)
    end
  end

  def document_warning_header(response_headers)
    response_headers['X-Cf-Warnings']= 'Warning%3A+Warning+message+may+go+here.'
  end
end
