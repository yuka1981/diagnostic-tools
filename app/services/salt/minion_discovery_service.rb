# frozen_string_literal: true

module Salt
  class MinionDiscoveryService
    Result = Struct.new(:success, :discovered, :existing, :error, keyword_init: true) do
      def success? = success
    end

    def initialize(salt_client: nil)
      @salt_client = salt_client || SaltApiClient.new
    end

    def call
      minions = @salt_client.get_minions
      existing_hostnames = Node.pluck(:hostname).to_set

      discovered = []
      existing = []

      minions.each do |minion_id, grains|
        if existing_hostnames.include?(minion_id)
          existing << minion_id
        else
          discovered << build_discovery_record(minion_id, grains)
        end
      end

      Result.new(success: true, discovered: discovered, existing: existing)
    rescue SaltApiClient::ApiError, SaltApiClient::AuthenticationError, SaltApiClient::TimeoutError => e
      Result.new(success: false, error: e.message, discovered: [], existing: [])
    end

    private

    def build_discovery_record(minion_id, grains)
      {
        hostname: minion_id,
        ip: grains.dig("ipv4")&.reject { |ip| ip == "127.0.0.1" }&.first,
        arch: grains["cpuarch"],
        os: grains["os"],
        os_release: grains["osrelease"],
        kernel: grains["kernelrelease"],
        cpu_model: grains["cpu_model"],
        mem_total: grains["mem_total"],
        num_cpus: grains["num_cpus"]
      }
    end
  end
end
