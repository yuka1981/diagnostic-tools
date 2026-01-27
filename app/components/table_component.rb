# frozen_string_literal: true

class TableComponent < ViewComponent::Base
  renders_many :columns, ->(header:, &block) {
    TableColumnComponent.new(header: header, block: block)
  }
  renders_many :bulk_actions, ->(label:, method: :post, confirm: nil) {
    TableBulkActionComponent.new(label: label, http_method: method, confirm: confirm)
  }
  renders_one :empty

  def initialize(collection:, selectable: false, bulk_action_path: nil, id_method: :id)
    @collection = collection
    @selectable = selectable
    @bulk_action_path = bulk_action_path
    @id_method = id_method
  end

  def selectable?
    @selectable && @bulk_action_path.present?
  end

  def empty?
    collection.empty?
  end

  private

  attr_reader :collection, :bulk_action_path, :id_method

  class TableColumnComponent < ViewComponent::Base
    attr_reader :header, :block

    def initialize(header:, block:)
      @header = header
      @block = block
    end

    def call
      # This component doesn't render directly - it provides data to parent
    end

    def cell_content(item)
      block.call(item)
    end
  end

  class TableBulkActionComponent < ViewComponent::Base
    attr_reader :label, :http_method, :confirm

    def initialize(label:, http_method:, confirm:)
      @label = label
      @http_method = http_method
      @confirm = confirm
    end
  end
end
