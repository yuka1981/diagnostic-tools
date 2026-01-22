# frozen_string_literal: true

require "rails_helper"

RSpec.describe Nodes::BulkCreateService do
  describe "#call" do
    subject(:service) { described_class.new(pattern, base_params, overrides) }

    let(:base_params) { { role: :compute, arch: "x86_64" } }
    let(:overrides) { {} }

    context "with valid pattern" do
      let(:pattern) { "compute-[001-003]" }

      it "creates multiple nodes" do
        expect { service.call }.to change(Node, :count).by(3)
      end

      it "returns success result" do
        result = service.call
        expect(result.success?).to be true
        expect(result.nodes.size).to eq(3)
        expect(result.conflicts).to be_empty
        expect(result.error).to be_nil
      end

      it "creates nodes with expected hostnames" do
        service.call
        expect(Node.where(hostname: %w[compute-001 compute-002 compute-003]).count).to eq(3)
      end

      it "applies base_params to all nodes" do
        service.call
        nodes = Node.where(hostname: %w[compute-001 compute-002 compute-003])
        nodes.each do |node|
          expect(node.role).to eq("compute")
          expect(node.arch).to eq("x86_64")
        end
      end
    end

    context "with single-digit range pattern" do
      let(:pattern) { "node-[1-5]" }

      it "creates nodes with single-digit hostnames" do
        expect { service.call }.to change(Node, :count).by(5)
        expect(Node.where(hostname: %w[node-1 node-2 node-3 node-4 node-5]).count).to eq(5)
      end
    end

    context "with zero-padded range pattern" do
      let(:pattern) { "gpu-[01-04]" }

      it "creates nodes preserving zero-padding" do
        expect { service.call }.to change(Node, :count).by(4)
        expect(Node.where(hostname: %w[gpu-01 gpu-02 gpu-03 gpu-04]).count).to eq(4)
      end
    end

    context "with larger range" do
      let(:pattern) { "compute-[010-015]" }

      it "creates nodes with correct range" do
        expect { service.call }.to change(Node, :count).by(6)
        expect(Node.where(hostname: %w[compute-010 compute-011 compute-012 compute-013 compute-014 compute-015]).count).to eq(6)
      end
    end

    context "with per-node overrides" do
      let(:pattern) { "compute-[001-003]" }
      let(:overrides) do
        {
          "compute-002" => { ip: "192.168.1.102", role: :login }
        }
      end

      it "applies overrides to specific nodes" do
        service.call
        node = Node.find_by(hostname: "compute-002")
        expect(node.ip).to eq("192.168.1.102")
        expect(node.role).to eq("login")
      end

      it "does not apply overrides to other nodes" do
        service.call
        node = Node.find_by(hostname: "compute-001")
        expect(node.ip).to be_blank
        expect(node.role).to eq("compute")
      end
    end

    context "when conflicts exist" do
      let(:pattern) { "compute-[001-003]" }

      before do
        create(:node, hostname: "compute-002")
      end

      it "does not create any nodes" do
        expect { service.call }.not_to change(Node, :count)
      end

      it "returns failure result with conflicts" do
        result = service.call
        expect(result.success?).to be false
        expect(result.nodes).to be_empty
        expect(result.conflicts).to eq([ "compute-002" ])
        expect(result.error).to be_nil
      end
    end

    context "when multiple conflicts exist" do
      let(:pattern) { "compute-[001-005]" }

      before do
        create(:node, hostname: "compute-001")
        create(:node, hostname: "compute-003")
        create(:node, hostname: "compute-005")
      end

      it "returns all conflicting hostnames" do
        result = service.call
        expect(result.success?).to be false
        expect(result.conflicts).to contain_exactly("compute-001", "compute-003", "compute-005")
      end
    end

    context "with invalid pattern" do
      context "when pattern has no bracket range" do
        let(:pattern) { "compute-001" }

        it "returns failure result" do
          result = service.call
          expect(result.success?).to be false
          expect(result.error).to match(/invalid pattern/i)
        end
      end

      context "when range is malformed" do
        let(:pattern) { "compute-[abc-def]" }

        it "returns failure result" do
          result = service.call
          expect(result.success?).to be false
          expect(result.error).to match(/invalid pattern/i)
        end
      end

      context "when range start is greater than end" do
        let(:pattern) { "compute-[010-005]" }

        it "returns failure result" do
          result = service.call
          expect(result.success?).to be false
          expect(result.error).to match(/invalid range/i)
        end
      end

      context "when pattern is empty" do
        let(:pattern) { "" }

        it "returns failure result" do
          result = service.call
          expect(result.success?).to be false
          expect(result.error).to match(/invalid pattern/i)
        end
      end
    end

    context "with transaction rollback on validation error" do
      let(:pattern) { "compute-[001-003]" }
      let(:overrides) do
        {
          "compute-002" => { hostname: "localhost" } # This should fail validation
        }
      end

      it "does not create any nodes when one fails validation" do
        expect { service.call }.not_to change(Node, :count)
      end

      it "returns failure result with error" do
        result = service.call
        expect(result.success?).to be false
        expect(result.error).to be_present
      end
    end

    context "with suffix after range" do
      let(:pattern) { "node-[01-03]-gpu" }

      it "creates nodes with correct hostnames" do
        expect { service.call }.to change(Node, :count).by(3)
        expect(Node.where(hostname: %w[node-01-gpu node-02-gpu node-03-gpu]).count).to eq(3)
      end
    end
  end
end
