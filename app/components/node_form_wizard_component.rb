# frozen_string_literal: true

class NodeFormWizardComponent < ViewComponent::Base
  def initialize(node:, api_keys: [], testid: nil)
    @node = node
    @api_keys = api_keys
    @testid = testid
  end

  private

  attr_reader :node, :api_keys, :testid

  def roles_for_select
    Node.roles.keys.map { |r| [ r.titleize, r ] }
  end

  def architectures_for_select
    [ [ "x86_64", "x86_64" ], [ "ARM64", "aarch64" ] ]
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

  def form_data
    {
      controller: "hostname-validation",
      hostname_validation_node_id_value: node.persisted? ? node.id : nil
    }
  end

  def racks_for_select
    ServerRack.includes(room: :site).order("sites.name, rooms.name, racks.name").map do |r|
      [ "#{r.site.name} / #{r.room.name} / #{r.name}", r.id ]
    end
  end

  def bmc_protocols_for_select
    BmcCredential.protocols.keys.map { |p| [ p.titleize, p ] }
  end
end
