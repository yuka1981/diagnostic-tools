# frozen_string_literal: true

require "rails_helper"

RSpec.describe BenchmarkRecipe, type: :model do
  describe "associations" do
    it { is_expected.to have_many(:benchmark_runs).dependent(:restrict_with_error) }
  end

  describe "validations" do
    # Use a subject with alpha characters in version for uniqueness test
    subject { build(:benchmark_recipe, version: "v1.0.0") }

    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:version) }
    it { is_expected.to validate_length_of(:name).is_at_most(100) }
    it { is_expected.to validate_length_of(:version).is_at_most(50) }
    it { is_expected.to validate_uniqueness_of(:version).scoped_to(:name) }
  end

  describe "factory" do
    it "creates a valid benchmark_recipe" do
      recipe = build(:benchmark_recipe)
      expect(recipe).to be_valid
    end

    it "creates a valid HPCG recipe" do
      recipe = build(:benchmark_recipe, :hpcg)
      expect(recipe.name).to eq("hpcg")
      expect(recipe.default_profile).to be_present
    end
  end

  describe "scopes" do
    describe ".by_name" do
      let!(:hpcg_recipe) { create(:benchmark_recipe, :hpcg) }
      let!(:other_recipe) { create(:benchmark_recipe, name: "hpl", version: "2.3") }

      it "returns recipes matching the name" do
        expect(BenchmarkRecipe.by_name("hpcg")).to contain_exactly(hpcg_recipe)
      end
    end
  end

  describe "#display_name" do
    it "returns name and version combined" do
      recipe = build(:benchmark_recipe, name: "hpcg", version: "3.1")
      expect(recipe.display_name).to eq("hpcg v3.1")
    end
  end
end
