# frozen_string_literal: true

module Mlc
  class RunForm
    include ActiveModel::Model

    attr_accessor :node_id, :profile, :binary_path, :modules, :log_path

    validates :node_id, presence: true
    validates :profile, presence: true
    validate :validate_profile_exists
    validate :validate_node_exists

    def node
      return @node if defined?(@node)

      @node = Node.find_by(id: node_id) if node_id.present?
    end

    def argument_overrides_hash
      overrides = { "profile" => profile }
      overrides["binary_path"] = binary_path if binary_path.present?
      overrides["modules"] = parse_modules if modules.present?
      overrides
    end

    private

    def validate_profile_exists
      return if profile.blank?
      return if Mlc::PROFILES.key?(profile.to_sym)

      errors.add(:profile, "is not a valid profile")
    end

    def validate_node_exists
      return if node_id.blank?
      return if node.present?

      errors.add(:node_id, "node not found")
    end

    def parse_modules
      modules.split(",").map(&:strip).reject(&:blank?)
    end
  end
end
