# frozen_string_literal: true

module Benchmark
  class RunForm
    include ActiveModel::Model

    attr_accessor :log_path, :benchmark_recipe_id, :argument_overrides

    # Validations
    validates :benchmark_recipe_id, presence: true
    validates :log_path, format: { with: /\A[\w\-\.\/]+\z/, message: "contains invalid characters" }, allow_blank: true
    validate :validate_recipe_exists
    validate :validate_argument_overrides_json

    # Get the associated benchmark recipe
    # @return [BenchmarkRecipe, nil]
    def benchmark_recipe
      return @benchmark_recipe if defined?(@benchmark_recipe)

      @benchmark_recipe = BenchmarkRecipe.find_by(id: benchmark_recipe_id) if benchmark_recipe_id.present?
    end

    # Parse argument_overrides JSON string to hash
    # @return [Hash] Parsed overrides or empty hash
    def argument_overrides_hash
      return @argument_overrides_hash if defined?(@argument_overrides_hash)

      @argument_overrides_hash = parse_argument_overrides
    end

    private

    def validate_recipe_exists
      return if benchmark_recipe_id.blank?
      return if benchmark_recipe.present?

      errors.add(:benchmark_recipe_id, "recipe not found")
    end

    def validate_argument_overrides_json
      return if argument_overrides.blank?

      begin
        parsed = JSON.parse(argument_overrides)
        unless parsed.is_a?(Hash)
          errors.add(:argument_overrides, "must be a JSON object")
        end
      rescue JSON::ParserError
        errors.add(:argument_overrides, "is not valid JSON")
      end
    end

    def parse_argument_overrides
      return {} if argument_overrides.blank?

      begin
        parsed = JSON.parse(argument_overrides)
        parsed.is_a?(Hash) ? parsed : {}
      rescue JSON::ParserError
        {}
      end
    end
  end
end
