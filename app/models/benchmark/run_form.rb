# frozen_string_literal: true

module Benchmark
  class RunForm
    include ActiveModel::Model

    attr_accessor :log_path

    # Validations
    # log_path is optional, but if provided, we might want to validate it looks like a path
    validates :log_path, format: { with: /\A[\w\-\.\/]+\z/, message: "contains invalid characters" }, allow_blank: true
  end
end
