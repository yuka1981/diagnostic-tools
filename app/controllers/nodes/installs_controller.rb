# frozen_string_literal: true

require "resolv"

module Nodes
  class InstallsController < ApplicationController
    before_action :authenticate_user!
    before_action :authorize_approver!
    before_action :reject_localhost_installation, only: [ :new, :create ]

    def new
      @target_host = params[:hostname]
      @node = Node.find_by(hostname: @target_host)

      # If node doesn't exist, always show modal (need API key at minimum)
      if @node.nil?
        setup_modal_variables
        return render :new
      end

      # Check if we have all required credentials
      @checker = Agent::CredentialChecker.new(@node, operation: :install)

      if @checker.needs_modal?
        setup_modal_variables
        @required_fields = @checker.required_fields
        render :new
      else
        start_installation_directly
      end
    end

    def create
      # Find or create the node immediately so we have an ID for log streaming
      @node = Node.find_or_initialize_by(hostname: install_params[:hostname])
      @node.arch = install_params[:arch]
      @node.source = :agent_push
      if install_params[:hostname] =~ Regexp.union(Resolv::IPv4::Regex, Resolv::IPv6::Regex)
        @node.ip = install_params[:hostname]
      end

      # For direct connections, save the password to the node record so future collections can use it
      if @node.direct?
        password_to_save = install_params[:bastion_password].presence || install_params[:sudo_password].presence
        @node.sudo_credential = password_to_save if password_to_save
      end

      @node.save!

      # Store sensitive credentials in a short-lived cache to avoid passing them as job arguments
      cache_key = SecureRandom.hex(16)
      credentials = {
        bastion_password: install_params[:bastion_password],
        sudo_password: install_params[:sudo_password]
      }
      Rails.cache.write("install_creds_#{cache_key}", credentials, expires_in: 5.minutes)

      Agent::InstallJob.perform_later(
        node: @node,
        target_host: install_params[:hostname],
        arch: install_params[:arch],
        bastion_host: install_params[:bastion_host],
        bastion_user: install_params[:bastion_user],
        credentials_cache_key: cache_key,
        server_url: install_params[:server_url].presence || request.base_url,
        api_key_id: install_params[:api_key_id],
        user_id: current_user.id
      )

      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to nodes_path, notice: "Installation started for #{install_params[:hostname]}" }
      end
    end

    private

    def authorize_approver!
      return if current_user.approver?

      redirect_to nodes_path, alert: "You are not authorized to install agents."
    end

    def install_params
      params.require(:install).permit(:hostname, :arch, :server_url, :api_key_id, :bastion_host, :bastion_user, :bastion_password, :sudo_password)
    end

    def reject_localhost_installation
      hostname = params[:hostname] || params.dig(:install, :hostname)
      return unless Node.localhost?(hostname)

      @target_host = hostname
      @localhost_error = true

      respond_to do |format|
        format.turbo_stream { render "localhost_not_supported" }
        format.html { render "localhost_not_supported", status: :unprocessable_entity }
      end
    end

    def setup_modal_variables
      # Determine arch: prioritize node's arch, fallback to params, default to x86_64
      raw_arch = @node&.arch.presence || params[:arch]
      @arch = raw_arch == "aarch64" ? "arm64" : raw_arch

      @api_keys = ApiKey.active.order(:name)
      @ssh_setting = SshSetting.current
      @server_url = @ssh_setting.server_url.presence || request.base_url

      # Adjust preloaded settings based on node configuration
      # For direct connections, don't prefill global bastion settings
      if @node&.effective_ssh_connect_method == "direct"
        @ssh_setting = SshSetting.new # Empty settings to avoid prefilling global bastion
      end
    end

    def start_installation_directly
      # One-click install: bypass modal when all credentials are stored
      ssh_setting = SshSetting.current

      # Store credentials from node's stored values
      cache_key = SecureRandom.hex(16)
      credentials = {
        bastion_password: @node.effective_ssh_password,
        sudo_password: @node.effective_sudo_credential
      }
      Rails.cache.write("install_creds_#{cache_key}", credentials, expires_in: 5.minutes)

      # Update node for installation
      @node.source = :agent_push
      @node.save!

      Agent::InstallJob.perform_later(
        node: @node,
        target_host: @node.hostname,
        arch: @node.arch || "x86_64",
        bastion_host: ssh_setting.bastion_host,
        bastion_user: ssh_setting.bastion_user.presence || @node.effective_ssh_user,
        credentials_cache_key: cache_key,
        server_url: ssh_setting.server_url.presence || request.base_url,
        api_key_id: @node.api_key_id,
        user_id: current_user.id
      )

      respond_to do |format|
        format.html { render "started" }
        format.turbo_stream { render "started" }
      end
    end
  end
end
