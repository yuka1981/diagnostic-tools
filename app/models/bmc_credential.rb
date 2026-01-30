# frozen_string_literal: true

class BmcCredential < ApplicationRecord
  belongs_to :node, optional: true
end
