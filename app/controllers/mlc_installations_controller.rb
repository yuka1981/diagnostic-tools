class MlcInstallationsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_installation, only: [ :show, :destroy ]

  def new
    @installation = MlcInstallation.new
    @nodes = Node.online.order(:hostname)
  end

  def create
    @installation = MlcInstallation.new(installation_params)
    @installation.created_by = current_user

    # Use pre-uploaded stored path if available (from AJAX upload), otherwise upload now
    if @installation.source_type == "upload"
      stored_path = installation_params[:stored_path]
      if stored_path.present?
        validated = validate_stored_path(stored_path)
        if validated
          @installation.source_path = validated
        else
          flash.now[:alert] = "Invalid uploaded file"
          @nodes = Node.online.order(:hostname)
          return render :new, status: :unprocessable_entity
        end
      elsif params[:tarball].present?
        upload_result = handle_upload(params[:tarball])
        unless upload_result.success?
          flash.now[:alert] = upload_result.error
          @nodes = Node.online.order(:hostname)
          return render :new, status: :unprocessable_entity
        end

        @installation.source_path = upload_result.stored_path
      end
    end

    if @installation.save
      create_installation_nodes
      enqueue_installation_job

      redirect_to @installation, notice: "Installation started"
    else
      @nodes = Node.online.order(:hostname)
      render :new, status: :unprocessable_entity
    end
  end

  def show
    @installation_nodes = @installation.mlc_installation_nodes.includes(:node)
  end

  def destroy
    @installation.update!(status: :cancelled, completed_at: Time.current)
    @installation.mlc_installation_nodes.pending.update_all(status: :skipped, completed_at: Time.current)
    @installation.mlc_installation_nodes.running.update_all(status: :cancelled, completed_at: Time.current)

    redirect_to @installation, notice: "Installation cancelled"
  end

  def upload
    unless params[:tarball].present?
      return render json: { error: "No file provided" }, status: :unprocessable_entity
    end

    upload_result = handle_upload(params[:tarball])

    if upload_result.success?
      render json: { stored_path: upload_result.stored_path, checksum: upload_result.computed_checksum }
    else
      render json: { error: upload_result.error }, status: :unprocessable_entity
    end
  end

  def verify_checksum
    stored_path = validate_stored_path(params[:stored_path])
    unless stored_path
      return render json: { error: "Invalid file path" }, status: :unprocessable_entity
    end

    upload_service = Mlc::UploadService.new(nil)
    upload_service.instance_variable_set(:@result, Mlc::UploadService::Result.new(
      success?: true,
      stored_path: stored_path
    ))

    verified = upload_service.verify_checksum(params[:algorithm], params[:checksum])

    render json: { verified: verified }
  end

  def select_binary
    extract_dir = extract_tarball_for_selection(params[:stored_path])
    detection_service = Mlc::BinaryDetectionService.new(extract_dir)
    result = detection_service.call

    if result.success?
      render json: { candidates: result.candidates.map(&:to_h) }
    else
      render json: { error: result.error }, status: :unprocessable_entity
    end
  ensure
    FileUtils.rm_rf(extract_dir) if extract_dir
  end

  private

  def set_installation
    @installation = MlcInstallation.find(params[:id])
  end

  def installation_params
    params.require(:mlc_installation).permit(
      :source_type, :source_path, :binary_path, :stored_path,
      :checksum_algorithm, :checksum_value, :checksum_verified,
      :install_dir, :module_dir, :failure_mode,
      node_ids: []
    )
  end

  def handle_upload(uploaded_file)
    upload_service = Mlc::UploadService.new(uploaded_file)
    upload_service.call
    upload_service.result
  end

  def create_installation_nodes
    node_ids = params[:mlc_installation][:node_ids]&.reject(&:blank?) || []
    node_ids.each do |node_id|
      @installation.mlc_installation_nodes.find_or_create_by!(node_id: node_id)
    end
  end

  def enqueue_installation_job
    Mlc::InstallJob.perform_later(
      @installation.id,
      server_url,
      agent_token,
      user_id: current_user.id
    )
  end

  def server_url
    request.base_url
  end

  def agent_token
    ApiKey.active.first&.token || ""
  end

  def extract_tarball_for_selection(stored_path)
    validated_path = validate_stored_path(stored_path)
    return nil unless validated_path

    extract_dir = Dir.mktmpdir("mlc-select-")
    system("tar", "-xzf", validated_path, "-C", extract_dir)
    extract_dir
  end

  def validate_stored_path(stored_path)
    return nil if stored_path.blank?

    upload_dir = Mlc::UploadService::UPLOAD_DIR.to_s
    expanded_path = File.expand_path(stored_path)

    # Ensure path is within upload directory (prevent path traversal)
    return nil unless expanded_path.start_with?(upload_dir)
    return nil unless File.exist?(expanded_path)

    expanded_path
  end
end
