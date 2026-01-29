require "net/http"
require "json"
require "uri"

class SaltApiClient
  class AuthenticationError < StandardError; end
  class TargetUnreachable < StandardError; end
  class TimeoutError < StandardError; end
  class ApiError < StandardError; end

  TOKEN_RENEWAL_BUFFER = 60.seconds

  def initialize(base_url: nil, username: nil, password: nil)
    @base_url = base_url || salt_config[:base_url]
    @username = username || salt_config[:username]
    @password = password || salt_config[:password]
    @token = nil
    @token_expires_at = nil
  end

  def authenticate
    response = post("/login", {
      username: @username,
      password: @password,
      eauth: "pam"
    }, authenticated: false)

    data = parse_response(response)
    result = data.dig("return", 0)
    raise AuthenticationError, "Invalid credentials" unless result&.key?("token")

    @token = result["token"]
    @token_expires_at = Time.at(result["expire"])
    @token
  end

  def run(target, function, **kwargs)
    ensure_authenticated
    body = { client: "local", tgt: target, fun: function }.merge(kwargs)
    response = post("/", body)
    data = parse_response(response)
    result = data.dig("return", 0)

    unless result.is_a?(Hash) && result.key?(target)
      raise TargetUnreachable, "Minion '#{target}' did not return a result"
    end

    minion_result = result[target]

    if minion_result == false && function == "test.ping"
      raise TargetUnreachable, "Minion '#{target}' is not responding"
    end

    minion_result
  end

  def run_async(target, function, **kwargs)
    ensure_authenticated
    body = { client: "local_async", tgt: target, fun: function }.merge(kwargs)
    response = post("/", body)
    data = parse_response(response)
    jid = data.dig("return", 0, "jid")
    raise ApiError, "No job ID returned" unless jid

    jid
  end

  def job_result(jid)
    ensure_authenticated
    response = get("/jobs/#{jid}")
    data = parse_response(response)
    data.dig("return", 0)
  end

  def run_runner(function, **kwargs)
    ensure_authenticated
    body = { client: "runner", fun: function }.merge(kwargs)
    response = post("/", body)
    data = parse_response(response)
    data.dig("return", 0)
  end

  def events(&block)
    ensure_authenticated
    uri = URI.parse("#{@base_url}/events")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    if http.use_ssl?
      http.verify_mode = OpenSSL::SSL::VERIFY_PEER
      ca_cert = salt_config[:ca_cert]
      http.ca_file = ca_cert if ca_cert.present?
    end
    http.read_timeout = 0

    request = Net::HTTP::Get.new(uri)
    request["X-Auth-Token"] = @token

    http.request(request) do |response|
      raise AuthenticationError, "SSE auth failed" unless response.is_a?(Net::HTTPSuccess)

      parse_sse_stream(response, &block)
    end
  rescue ::Net::OpenTimeout => e
    raise TimeoutError, e.message
  end

  private

  def ensure_authenticated
    if @token.nil? || token_near_expiry?
      authenticate
    end
  end

  def token_near_expiry?
    @token_expires_at.nil? || Time.current >= (@token_expires_at - TOKEN_RENEWAL_BUFFER)
  end

  def post(path, body, authenticated: true)
    uri = URI.parse("#{@base_url}#{path}")
    request = Net::HTTP::Post.new(uri)
    request["Content-Type"] = "application/json"
    request["X-Auth-Token"] = @token if authenticated && @token
    request.body = body.to_json

    execute_request(uri, request)
  end

  def get(path)
    uri = URI.parse("#{@base_url}#{path}")
    request = Net::HTTP::Get.new(uri)
    request["Content-Type"] = "application/json"
    request["X-Auth-Token"] = @token

    execute_request(uri, request)
  end

  def execute_request(uri, request)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    if http.use_ssl?
      http.verify_mode = OpenSSL::SSL::VERIFY_PEER
      ca_cert = salt_config[:ca_cert]
      http.ca_file = ca_cert if ca_cert.present?
    end
    http.open_timeout = 10
    http.read_timeout = 300

    response = http.request(request)

    case response
    when Net::HTTPUnauthorized
      raise AuthenticationError, "Authentication failed: #{response.body}"
    when Net::HTTPSuccess
      response
    else
      raise ApiError, "HTTP #{response.code}: #{response.body}"
    end
  rescue ::Net::OpenTimeout, ::Net::ReadTimeout => e
    raise TimeoutError, e.message
  end

  def parse_response(response)
    JSON.parse(response.body)
  rescue JSON::ParserError => e
    raise ApiError, "Invalid JSON response: #{e.message}"
  end

  def parse_sse_stream(response, &block)
    tag = nil
    data_lines = []
    response.read_body do |chunk|
      chunk.each_line do |line|
        line = line.rstrip
        if line.start_with?("tag: ")
          tag = line.sub("tag: ", "")
          data_lines = []
        elsif line.start_with?("data: ")
          data_lines << line.sub("data: ", "")
        elsif line.empty? && tag && data_lines.any?
          data = JSON.parse(data_lines.join("\n"))
          block.call(tag, data)
          tag = nil
          data_lines = []
        end
      end
    end
  end

  def salt_config
    @salt_config ||= {
      base_url: Rails.application.credentials.dig(:salt_api, :base_url) || ENV["SALT_API_URL"],
      username: Rails.application.credentials.dig(:salt_api, :username) || ENV["SALT_API_USERNAME"],
      password: Rails.application.credentials.dig(:salt_api, :password) || ENV["SALT_API_PASSWORD"],
      ca_cert: Rails.application.credentials.dig(:salt_api, :ca_cert) || ENV["SALT_API_CA_CERT"]
    }
  end
end
