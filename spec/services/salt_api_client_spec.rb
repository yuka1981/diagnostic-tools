require "rails_helper"

RSpec.describe SaltApiClient do
  let(:base_url) { "https://salt-master.example.com:8000" }
  let(:username) { "rails_salt_user" }
  let(:password) { "secret" }
  let(:client) { described_class.new(base_url: base_url, username: username, password: password) }

  before do
    allow(SaltSetting).to receive(:current).and_return(
      instance_double(SaltSetting,
        base_url: nil, username: nil, password: nil,
        ca_cert_path: nil, verify_ssl: true)
    )
  end

  describe "#authenticate" do
    it "obtains a token from salt-api" do
      stub_request(:post, "#{base_url}/login")
        .with(body: { username: username, password: password, eauth: "pam" })
        .to_return(
          status: 200,
          body: { return: [ { token: "abc123", expire: (Time.current + 12.hours).to_f } ] }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      token = client.authenticate
      expect(token).to eq("abc123")
    end

    it "raises AuthenticationError on 401" do
      stub_request(:post, "#{base_url}/login")
        .to_return(status: 401, body: "Unauthorized")

      expect { client.authenticate }.to raise_error(SaltApiClient::AuthenticationError)
    end
  end

  describe "#run" do
    before do
      stub_request(:post, "#{base_url}/login")
        .to_return(
          status: 200,
          body: { return: [ { token: "abc123", expire: (Time.current + 12.hours).to_f } ] }.to_json,
          headers: { "Content-Type" => "application/json" }
        )
    end

    it "executes a synchronous command on a target minion" do
      stub_request(:post, "#{base_url}/")
        .with(
          body: { client: "local", tgt: "node-01", fun: "test.ping" }.to_json,
          headers: { "X-Auth-Token" => "abc123", "Content-Type" => "application/json" }
        )
        .to_return(
          status: 200,
          body: { return: [ { "node-01" => true } ] }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      result = client.run("node-01", "test.ping")
      expect(result).to eq(true)
    end

    it "passes keyword arguments to the Salt function" do
      stub_request(:post, "#{base_url}/")
        .with(
          body: { client: "local", tgt: "node-01", fun: "grains.item", arg: [ "os", "cpuarch" ] }.to_json,
          headers: { "X-Auth-Token" => "abc123" }
        )
        .to_return(
          status: 200,
          body: { return: [ { "node-01" => { "os" => "CentOS", "cpuarch" => "x86_64" } } ] }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      result = client.run("node-01", "grains.item", arg: [ "os", "cpuarch" ])
      expect(result).to eq({ "os" => "CentOS", "cpuarch" => "x86_64" })
    end

    it "raises TargetUnreachable when minion is not connected" do
      stub_request(:post, "#{base_url}/")
        .to_return(
          status: 200,
          body: { return: [ { "node-01" => false } ] }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      expect { client.run("node-01", "test.ping") }
        .to raise_error(SaltApiClient::TargetUnreachable)
    end

    it "raises TargetUnreachable when minion is not in the result" do
      stub_request(:post, "#{base_url}/")
        .to_return(
          status: 200,
          body: { return: [ {} ] }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      expect { client.run("node-01", "grains.items") }
        .to raise_error(SaltApiClient::TargetUnreachable)
    end
  end

  describe "token auto-renewal" do
    it "re-authenticates when token is near expiry" do
      # First auth returns token expiring soon
      stub_request(:post, "#{base_url}/login")
        .to_return(
          status: 200,
          body: { return: [ { token: "token1", expire: (Time.current + 30.seconds).to_f } ] }.to_json,
          headers: { "Content-Type" => "application/json" }
        ).then
        .to_return(
          status: 200,
          body: { return: [ { token: "token2", expire: (Time.current + 12.hours).to_f } ] }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      stub_request(:post, "#{base_url}/")
        .to_return(
          status: 200,
          body: { return: [ { "node-01" => true } ] }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      client.run("node-01", "test.ping")
      # Second call should re-authenticate
      client.run("node-01", "test.ping")

      expect(WebMock).to have_requested(:post, "#{base_url}/login").twice
    end
  end

  describe "#run_async" do
    before do
      stub_request(:post, "#{base_url}/login")
        .to_return(
          status: 200,
          body: { return: [ { token: "abc123", expire: (Time.current + 12.hours).to_f } ] }.to_json,
          headers: { "Content-Type" => "application/json" }
        )
    end

    it "returns a job ID for async execution" do
      stub_request(:post, "#{base_url}/")
        .with(body: hash_including(client: "local_async"))
        .to_return(
          status: 200,
          body: { return: [ { jid: "20260129120000123456" } ] }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      jid = client.run_async("node-01", "state.apply", mods: "benchmark.hpcg")
      expect(jid).to eq("20260129120000123456")
    end
  end

  describe "#job_result" do
    before do
      stub_request(:post, "#{base_url}/login")
        .to_return(
          status: 200,
          body: { return: [ { token: "abc123", expire: (Time.current + 12.hours).to_f } ] }.to_json,
          headers: { "Content-Type" => "application/json" }
        )
    end

    it "retrieves job results by JID" do
      stub_request(:get, "#{base_url}/jobs/20260129120000123456")
        .to_return(
          status: 200,
          body: { return: [ { "node-01" => { "retcode" => 0, "return" => "success" } } ] }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      result = client.job_result("20260129120000123456")
      expect(result).to eq({ "node-01" => { "retcode" => 0, "return" => "success" } })
    end
  end

  describe "#run_runner" do
    before do
      stub_request(:post, "#{base_url}/login")
        .to_return(
          status: 200,
          body: { return: [ { token: "abc123", expire: (Time.current + 12.hours).to_f } ] }.to_json,
          headers: { "Content-Type" => "application/json" }
        )
    end

    it "executes a runner module" do
      stub_request(:post, "#{base_url}/")
        .with(body: hash_including(client: "runner", fun: "manage.status"))
        .to_return(
          status: 200,
          body: { return: [ { "up" => [ "node-01", "node-02" ], "down" => [ "node-03" ] } ] }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      result = client.run_runner("manage.status")
      expect(result["up"]).to contain_exactly("node-01", "node-02")
      expect(result["down"]).to contain_exactly("node-03")
    end
  end

  describe "#get_minions" do
    before do
      stub_request(:post, "#{base_url}/login")
        .to_return(
          status: 200,
          body: { return: [ { token: "test-token", expire: (Time.current + 1.hour).to_f } ] }.to_json,
          headers: { "Content-Type" => "application/json" }
        )
    end

    it "returns all minions with grains" do
      minion_data = {
        "node-01" => { "os" => "Rocky", "cpuarch" => "x86_64" },
        "node-02" => { "os" => "Ubuntu", "cpuarch" => "aarch64" }
      }

      stub_request(:get, "#{base_url}/minions")
        .to_return(
          status: 200,
          body: { return: [ minion_data ] }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      result = client.get_minions
      expect(result).to eq(minion_data)
    end

    it "returns empty hash when no minions" do
      stub_request(:get, "#{base_url}/minions")
        .to_return(
          status: 200,
          body: { return: [ {} ] }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      result = client.get_minions
      expect(result).to eq({})
    end
  end

  describe "#events" do
    before do
      stub_request(:post, "#{base_url}/login")
        .to_return(
          status: 200,
          body: { return: [ { token: "abc123", expire: (Time.current + 12.hours).to_f } ] }.to_json,
          headers: { "Content-Type" => "application/json" }
        )
    end

    it "parses SSE event stream and yields tag/data pairs" do
      sse_body = "retry: 400\ntag: salt/job/ret/123\ndata: {\"fun\": \"test.ping\", \"id\": \"node-01\"}\n\n"

      stub_request(:get, "#{base_url}/events")
        .to_return(
          status: 200,
          body: sse_body,
          headers: { "Content-Type" => "text/event-stream" }
        )

      events = []
      client.events do |tag, data|
        events << [ tag, data ]
        break # Stop after first event for test
      end

      expect(events.length).to eq(1)
      expect(events[0][0]).to eq("salt/job/ret/123")
      expect(events[0][1]["fun"]).to eq("test.ping")
    end
  end

  describe "configuration precedence" do
    it "reads from SaltSetting when no explicit params given" do
      allow(SaltSetting).to receive(:current).and_return(
        instance_double(SaltSetting,
          base_url: "http://salt-from-db:8000",
          username: "db_user",
          password: "db_pass",
          ca_cert_path: "/etc/ssl/salt-ca.pem",
          verify_ssl: false)
      )

      stub_request(:post, "http://salt-from-db:8000/login")
        .to_return(
          status: 200,
          body: { return: [ { token: "db-token", expire: (Time.current + 12.hours).to_f } ] }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      client = described_class.new
      client.authenticate
      expect(WebMock).to have_requested(:post, "http://salt-from-db:8000/login")
    end
  end
end
