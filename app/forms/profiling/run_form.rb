# frozen_string_literal: true

module Profiling
  class RunForm
    include ActiveModel::Model
    include ActiveModel::Attributes

    attribute :subcommand, :string
    attribute :profiling_recipe_id, :integer
    attribute :options_json, :string
    attribute :module_name, :string, default: "perfspect/3.13.0"
    attribute :duration, :integer, default: 60

    validates :subcommand, presence: true, inclusion: { in: %w[report telemetry flame] }

    def options
      return { "duration" => duration } if %w[telemetry flame].include?(subcommand)

      {}
    end

    def profiling_recipe
      return nil if profiling_recipe_id.blank?

      ProfilingRecipe.find_by(id: profiling_recipe_id)
    end
  end
end
