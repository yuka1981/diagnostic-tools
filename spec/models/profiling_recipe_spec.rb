# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProfilingRecipe, type: :model do
  describe "associations" do
    it { is_expected.to have_many(:profiling_runs).dependent(:restrict_with_error) }
  end

  describe "validations" do
    subject { build(:profiling_recipe) }

    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:subcommand) }
    it { is_expected.to validate_presence_of(:module_name) }
    it { is_expected.to validate_uniqueness_of(:slug) }
    it { is_expected.to validate_inclusion_of(:subcommand).in_array(%w[report telemetry flame]) }
  end

  describe "enums" do
    it "defines active and archived statuses" do
      expect(ProfilingRecipe.statuses).to eq({ "active" => 0, "archived" => 1 })
    end
  end

  describe "callbacks" do
    it "generates slug from name if blank" do
      recipe = create(:profiling_recipe, name: "Quick System Report", slug: nil)
      expect(recipe.slug).to eq("quick-system-report")
    end
  end

  describe "#display_name" do
    it "returns formatted name with tool" do
      recipe = build(:profiling_recipe, name: "System Report", tool: "perfspect")
      expect(recipe.display_name).to eq("System Report (perfspect)")
    end
  end
end
