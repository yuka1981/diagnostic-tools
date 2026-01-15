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
    it { is_expected.to validate_presence_of(:command) }
    it { is_expected.to validate_length_of(:name).is_at_most(100) }
    it { is_expected.to validate_length_of(:version).is_at_most(50) }
    it { is_expected.to validate_uniqueness_of(:version).scoped_to(:name) }
    it { is_expected.to validate_uniqueness_of(:slug) }
  end

  describe "enums" do
    it { is_expected.to define_enum_for(:status).with_values(active: 0, archived: 1) }
  end

  describe "factory" do
    it "creates a valid benchmark_recipe" do
      recipe = build(:benchmark_recipe)
      expect(recipe).to be_valid
    end

    it "creates a valid HPCG recipe" do
      recipe = build(:benchmark_recipe, :hpcg)
      expect(recipe.name).to eq("hpcg")
      expect(recipe.command).to eq("hpcg")
      expect(recipe.default_profile).to be_present
    end

    it "creates an archived recipe" do
      recipe = build(:benchmark_recipe, :archived)
      expect(recipe).to be_archived
    end
  end

  describe "scopes" do
    describe ".by_name" do
      let!(:hpcg_recipe) { create(:benchmark_recipe, :hpcg) }
      let!(:other_recipe) { create(:benchmark_recipe, name: "hpl", version: "2.3", slug: "hpl-2-3-test", command: "hpl") }

      it "returns recipes matching the name" do
        expect(BenchmarkRecipe.by_name("hpcg")).to contain_exactly(hpcg_recipe)
      end
    end

    describe ".active" do
      let!(:active_recipe) { create(:benchmark_recipe) }
      let!(:archived_recipe) { create(:benchmark_recipe, :archived) }

      it "returns only active recipes" do
        expect(BenchmarkRecipe.active).to contain_exactly(active_recipe)
      end
    end
  end

  describe "slug generation" do
    it "auto-generates slug from name and version if not provided" do
      recipe = build(:benchmark_recipe, name: "My Benchmark", version: "1.0", slug: nil)
      recipe.valid?
      expect(recipe.slug).to eq("my-benchmark-1-0")
    end

    it "does not overwrite an existing slug" do
      recipe = build(:benchmark_recipe, name: "Test", version: "1.0", slug: "custom-slug")
      recipe.valid?
      expect(recipe.slug).to eq("custom-slug")
    end

    it "handles special characters in name" do
      recipe = build(:benchmark_recipe, name: "HPL (Linpack)", version: "2.3", slug: nil)
      recipe.valid?
      expect(recipe.slug).to match(/hpl-linpack-2-3/)
    end
  end

  describe "#display_name" do
    it "returns name and version combined" do
      recipe = build(:benchmark_recipe, name: "hpcg", version: "3.1")
      expect(recipe.display_name).to eq("hpcg v3.1")
    end
  end

  describe "defaults" do
    it "has default timeout_seconds of 3600" do
      recipe = BenchmarkRecipe.new
      expect(recipe.timeout_seconds).to eq(3600)
    end

    it "has default status of active" do
      recipe = BenchmarkRecipe.new
      expect(recipe).to be_active
    end
  end
end
