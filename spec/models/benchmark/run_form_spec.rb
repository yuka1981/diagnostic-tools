# frozen_string_literal: true

require "rails_helper"

RSpec.describe Benchmark::RunForm do
  describe "validations" do
    it "is valid with valid attributes" do
      recipe = create(:benchmark_recipe)
      form = described_class.new(benchmark_recipe_id: recipe.id)
      expect(form).to be_valid
    end

    it "is valid without optional log_path" do
      recipe = create(:benchmark_recipe)
      form = described_class.new(benchmark_recipe_id: recipe.id)
      expect(form).to be_valid
    end

    it "validates log_path format when provided" do
      recipe = create(:benchmark_recipe)
      form = described_class.new(benchmark_recipe_id: recipe.id, log_path: "/var/log/benchmark")
      expect(form).to be_valid
    end

    it "rejects invalid log_path characters" do
      recipe = create(:benchmark_recipe)
      form = described_class.new(benchmark_recipe_id: recipe.id, log_path: "path with spaces")
      expect(form).not_to be_valid
      expect(form.errors[:log_path]).to be_present
    end

    it "requires benchmark_recipe_id" do
      form = described_class.new(benchmark_recipe_id: nil)
      expect(form).not_to be_valid
      expect(form.errors[:benchmark_recipe_id]).to include("can't be blank")
    end

    it "validates benchmark_recipe exists" do
      form = described_class.new(benchmark_recipe_id: 999999)
      expect(form).not_to be_valid
      expect(form.errors[:benchmark_recipe_id]).to include("recipe not found")
    end
  end

  describe "#benchmark_recipe" do
    it "returns the associated benchmark recipe" do
      recipe = create(:benchmark_recipe, :hpcg)
      form = described_class.new(benchmark_recipe_id: recipe.id)
      expect(form.benchmark_recipe).to eq(recipe)
    end

    it "returns nil when recipe_id is blank" do
      form = described_class.new(benchmark_recipe_id: nil)
      expect(form.benchmark_recipe).to be_nil
    end
  end

  describe "#argument_overrides_hash" do
    context "with valid JSON" do
      it "parses JSON string to hash" do
        recipe = create(:benchmark_recipe)
        form = described_class.new(
          benchmark_recipe_id: recipe.id,
          argument_overrides: '{"nx": 128, "ny": 128}'
        )
        expect(form.argument_overrides_hash).to eq({ "nx" => 128, "ny" => 128 })
      end
    end

    context "with empty string" do
      it "returns empty hash" do
        recipe = create(:benchmark_recipe)
        form = described_class.new(benchmark_recipe_id: recipe.id, argument_overrides: "")
        expect(form.argument_overrides_hash).to eq({})
      end
    end

    context "with nil" do
      it "returns empty hash" do
        recipe = create(:benchmark_recipe)
        form = described_class.new(benchmark_recipe_id: recipe.id, argument_overrides: nil)
        expect(form.argument_overrides_hash).to eq({})
      end
    end

    context "with invalid JSON" do
      it "returns empty hash and adds error" do
        recipe = create(:benchmark_recipe)
        form = described_class.new(
          benchmark_recipe_id: recipe.id,
          argument_overrides: "not valid json"
        )
        form.valid?
        expect(form.argument_overrides_hash).to eq({})
        expect(form.errors[:argument_overrides]).to include("is not valid JSON")
      end
    end

    context "with JSON that is not an object" do
      it "returns empty hash and adds error" do
        recipe = create(:benchmark_recipe)
        form = described_class.new(
          benchmark_recipe_id: recipe.id,
          argument_overrides: "[1, 2, 3]"
        )
        form.valid?
        expect(form.argument_overrides_hash).to eq({})
        expect(form.errors[:argument_overrides]).to include("must be a JSON object")
      end
    end
  end
end
