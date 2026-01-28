module Mlc
  class UploadService
    Result = Struct.new(:success?, :stored_path, :computed_checksum, :error, keyword_init: true)

    UPLOAD_DIR = Rails.root.join("storage", "mlc_uploads")

    attr_reader :result

    def initialize(uploaded_file)
      @uploaded_file = uploaded_file
      @result = nil
    end

    def call
      FileUtils.mkdir_p(UPLOAD_DIR)

      filename = "#{SecureRandom.uuid}_#{sanitize_filename(@uploaded_file.original_filename)}"
      stored_path = UPLOAD_DIR.join(filename)

      File.open(stored_path, "wb") do |file|
        file.write(@uploaded_file.read)
      end

      checksum = Digest::SHA256.file(stored_path).hexdigest

      @result = Result.new(
        success?: true,
        stored_path: stored_path.to_s,
        computed_checksum: checksum
      )
    rescue StandardError => e
      @result = Result.new(success?: false, error: e.message)
    end

    def verify_checksum(algorithm, expected)
      return false unless @result&.stored_path

      actual = case algorithm.downcase
               when "sha256" then Digest::SHA256.file(@result.stored_path).hexdigest
               when "sha1" then Digest::SHA1.file(@result.stored_path).hexdigest
               when "md5" then Digest::MD5.file(@result.stored_path).hexdigest
               else return false
               end

      ActiveSupport::SecurityUtils.secure_compare(actual, expected.downcase)
    end

    private

    def sanitize_filename(filename)
      filename.gsub(/[^a-zA-Z0-9._-]/, "_")
    end
  end
end
