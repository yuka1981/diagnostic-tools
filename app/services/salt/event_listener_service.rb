module Salt
  class EventListenerService
    BENCHMARK_JOB_PATTERN = /\Asalt\/job\/ret\//.freeze
    PRESENCE_CHANGE_TAG = "salt/presence/change"

    def initialize(salt_client: nil)
      @salt_client = salt_client || SaltApiClient.new
    end

    def listen
      @salt_client.events do |tag, data|
        dispatch_event(tag, data)
      rescue StandardError => e
        Rails.logger.error("Salt event dispatch error for tag=#{tag}: #{e.message}")
      end
    end

    def dispatch_event(tag, data)
      case tag
      when BENCHMARK_JOB_PATTERN
        handle_benchmark_return(data) if benchmark_event?(data)
      when PRESENCE_CHANGE_TAG
        handle_presence_change(data)
      end
    end

    def update_presence(new_minions: [], lost_minions: [])
      lost_minions.each do |hostname|
        node = Node.find_by(hostname: hostname)
        node&.update(last_heartbeat_at: nil)
      end

      new_minions.each do |hostname|
        node = Node.find_by(hostname: hostname)
        node&.update(last_heartbeat_at: Time.current)
      end
    end

    private

    def benchmark_event?(data)
      fun = data["fun"]
      fun == "state.apply" && data.dig("fun_args")&.any? { |arg|
        arg.is_a?(Hash) && arg["mods"]&.start_with?("benchmark.")
      }
    end

    def handle_benchmark_return(data)
      run_id = extract_run_id(data)
      return unless run_id

      benchmark_run = BenchmarkRun.find_by(uuid: run_id)
      return unless benchmark_run

      minion_id = data["id"]
      job_return = { minion_id => { "retcode" => data["retcode"], "return" => data["return"] } }

      Salt::BenchmarkResultService.new(
        benchmark_run: benchmark_run,
        job_return: job_return,
        salt_client: @salt_client
      ).call
    end

    def handle_presence_change(data)
      update_presence(
        new_minions: data["new"] || [],
        lost_minions: data["lost"] || []
      )
    end

    def extract_run_id(data)
      data.dig("fun_args")&.each do |arg|
        next unless arg.is_a?(Hash)
        run_id = arg.dig("pillar", "run_id") || arg.dig(:pillar, :run_id)
        return run_id if run_id
      end
      nil
    end
  end
end
