require "rails_helper"

RSpec.describe Api::V1::SaltEventsController, type: :controller do
  let(:api_key) { create(:api_key) }

  before do
    request.headers["Authorization"] = "Bearer #{api_key.token}"
    request.headers["Content-Type"] = "application/json"
  end

  describe "POST #create" do
    it "dispatches events via EventListenerService" do
      listener = instance_double(Salt::EventListenerService)
      allow(Salt::EventListenerService).to receive(:new).and_return(listener)
      allow(listener).to receive(:dispatch_event)

      post :create, body: {
        tag: "salt/job/ret/123",
        id: "node-01",
        retcode: 0,
        return: {}
      }.to_json

      expect(response).to have_http_status(:ok)
      expect(listener).to have_received(:dispatch_event).with("salt/job/ret/123", hash_including("tag"))
    end

    it "returns bad request for invalid JSON" do
      post :create, body: "not json"

      expect(response).to have_http_status(:bad_request)
    end
  end
end
