# frozen_string_literal: true

class NodeFormWizardComponent < ViewComponent::Base
  def initialize(node:, ssh_profiles: [], api_keys: [], agent_config: nil)
    @node = node
    @ssh_profiles = ssh_profiles
    @api_keys = api_keys
    @agent_config = agent_config || SshSetting.current
  end

  private

  attr_reader :node, :ssh_profiles, :api_keys, :agent_config

  def roles_for_select
    Node.roles.keys.map { |r| [ r.titleize, r ] }
  end

  def architectures_for_select
    [ [ "x86_64", "x86_64" ], [ "ARM64", "aarch64" ] ]
  end

  def ssh_profiles_for_select
    ssh_profiles.map { |p| [ p.name, p.id ] }
  end

  def api_keys_for_select
    api_keys.map { |k| [ k.name, k.id ] }
  end

  def form_url
    node.persisted? ? helpers.node_path(node) : helpers.nodes_path
  end

  def form_method
    node.persisted? ? :patch : :post
  end

  def default_agent_path
    agent_config&.default_agent_path.presence || SshSetting::DEFAULT_AGENT_PATH
  end

  def default_benchmark_work_dir
    agent_config&.benchmark_work_dir.presence || BenchmarkConfig::DEFAULT_WORK_DIR
  end

  def racks_for_select
    ServerRack.includes(room: :site).order("sites.name, rooms.name, racks.name").map do |r|
      [ "#{r.site.name} / #{r.room.name} / #{r.name}", r.id ]
    end
  end

  def ssh_connect_methods_for_select
    Node.ssh_connect_methods.keys.map { |m| [ m.humanize, m ] }
  end
end
