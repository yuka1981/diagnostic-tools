# frozen_string_literal: true

require "rails_helper"

RSpec.describe Runs::FilterQuery do
  let(:node1) { create(:node, hostname: "compute-001") }
  let(:node2) { create(:node, hostname: "login-001", role: :login) }
  let(:recipe1) { create(:benchmark_recipe, name: "HPL") }
  let(:recipe2) { create(:benchmark_recipe, name: "STREAM") }

  let!(:run1) do
    create(:benchmark_run, :success, node: node1, benchmark_recipe: recipe1, started_at: 1.hour.ago)
  end
  let!(:run2) do
    create(:benchmark_run, :failed, node: node2, benchmark_recipe: recipe2, started_at: 2.hours.ago)
  end
  let!(:run3) do
    create(:benchmark_run, :pending, node: node1, benchmark_recipe: recipe2, started_at: nil)
  end
  let!(:run4) do
    create(:benchmark_run, :running, node: node2, benchmark_recipe: recipe1, started_at: 30.minutes.ago)
  end

  describe "#call" do
    subject(:query) { described_class.new(params).call }

    context "with no filters" do
      let(:params) { {} }

      it "returns all runs ordered by recent" do
        expect(query.to_a).to eq([ run4, run1, run2, run3 ])
      end
    end

    context "with status filter" do
      let(:params) { { status: "success" } }

      it "filters by status" do
        expect(query).to contain_exactly(run1)
      end
    end

    context "with multiple status filter" do
      let(:params) { { status: "failed" } }

      it "filters by the specified status" do
        expect(query).to contain_exactly(run2)
      end
    end

    context "with node_id filter" do
      let(:params) { { node_id: node1.id } }

      it "filters by node" do
        expect(query).to contain_exactly(run1, run3)
      end
    end

    context "with recipe_id filter" do
      let(:params) { { recipe_id: recipe1.id } }

      it "filters by recipe" do
        expect(query).to contain_exactly(run1, run4)
      end
    end

    context "with search query" do
      let(:params) { { q: "compute" } }

      it "searches by node hostname" do
        expect(query).to contain_exactly(run1, run3)
      end
    end

    context "with search query for recipe name" do
      let(:params) { { q: "HPL" } }

      it "searches by recipe name" do
        expect(query).to contain_exactly(run1, run4)
      end
    end

    context "with combined filters" do
      let(:params) { { status: "success", node_id: node1.id } }

      it "applies all filters" do
        expect(query).to contain_exactly(run1)
      end
    end

    context "with invalid status" do
      let(:params) { { status: "invalid_status" } }

      it "ignores invalid status and returns all runs" do
        expect(query.count).to eq(4)
      end
    end

    context "with blank params" do
      let(:params) { { status: "", node_id: "", recipe_id: "", q: "" } }

      it "ignores blank params and returns all runs" do
        expect(query.count).to eq(4)
      end
    end
  end

  describe "#filtered?" do
    subject(:filter_query) { described_class.new(params) }

    context "with no filters" do
      let(:params) { {} }

      it "returns false" do
        expect(filter_query).not_to be_filtered
      end
    end

    context "with status filter" do
      let(:params) { { status: "success" } }

      it "returns true" do
        expect(filter_query).to be_filtered
      end
    end

    context "with search query" do
      let(:params) { { q: "compute" } }

      it "returns true" do
        expect(filter_query).to be_filtered
      end
    end
  end
end
