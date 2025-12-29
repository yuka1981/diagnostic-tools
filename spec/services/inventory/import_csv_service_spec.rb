# frozen_string_literal: true

require "rails_helper"

RSpec.describe Inventory::ImportCsvService do
  describe "#call" do
    subject(:service) { described_class.new(csv_content) }

    context "with valid CSV content" do
      let(:csv_content) do
        <<~CSV
          hostname,ip,role,arch
          compute-001,192.168.1.101,compute,x86_64
          compute-002,192.168.1.102,compute,x86_64
          login-001,192.168.1.1,login,x86_64
        CSV
      end

      it "creates new nodes" do
        expect { service.call }.to change(Node, :count).by(3)
      end

      it "returns success result" do
        result = service.call
        expect(result.success?).to be true
        expect(result.created_count).to eq(3)
        expect(result.updated_count).to eq(0)
        expect(result.error_count).to eq(0)
      end

      it "sets correct attributes on created nodes" do
        service.call
        node = Node.find_by(hostname: "compute-001")
        expect(node.ip).to eq("192.168.1.101")
        expect(node.role).to eq("compute")
        expect(node.arch).to eq("x86_64")
        expect(node.source).to eq("csv")
      end
    end

    context "with existing nodes (upsert)" do
      let!(:existing_node) { create(:node, hostname: "compute-001", ip: "10.0.0.1", role: :compute, arch: "aarch64") }

      let(:csv_content) do
        <<~CSV
          hostname,ip,role,arch
          compute-001,192.168.1.101,compute,x86_64
          compute-002,192.168.1.102,compute,x86_64
        CSV
      end

      it "updates existing node and creates new one" do
        expect { service.call }.to change(Node, :count).by(1)
      end

      it "updates existing node attributes" do
        service.call
        existing_node.reload
        expect(existing_node.ip).to eq("192.168.1.101")
        expect(existing_node.arch).to eq("x86_64")
      end

      it "returns correct counts" do
        result = service.call
        expect(result.created_count).to eq(1)
        expect(result.updated_count).to eq(1)
      end
    end

    context "with optional fields" do
      let(:csv_content) do
        <<~CSV
          hostname,ip,role,arch
          compute-001,,compute,
          compute-002,192.168.1.102,compute,x86_64
        CSV
      end

      it "creates nodes with blank optional fields" do
        service.call
        node = Node.find_by(hostname: "compute-001")
        expect(node.ip).to be_blank
        expect(node.arch).to be_blank
      end
    end

    context "with invalid CSV content" do
      context "when hostname is missing" do
        let(:csv_content) do
          <<~CSV
            hostname,ip,role,arch
            ,192.168.1.101,compute,x86_64
          CSV
        end

        it "records the error" do
          result = service.call
          expect(result.error_count).to eq(1)
          expect(result.errors).to include(hash_including(row: 2))
        end
      end

      context "when role is invalid" do
        let(:csv_content) do
          <<~CSV
            hostname,ip,role,arch
            compute-001,192.168.1.101,invalid_role,x86_64
          CSV
        end

        it "records a specific error" do
          result = service.call
          expect(result.error_count).to eq(1)
          expect(result.errors.first[:message]).to match(/is not a valid role/i)
        end
      end

      context "when IP is invalid" do
        let(:csv_content) do
          <<~CSV
            hostname,ip,role,arch
            compute-001,invalid-ip,compute,x86_64
          CSV
        end

        it "records the error" do
          result = service.call
          expect(result.error_count).to eq(1)
          expect(result.errors.first[:message]).to include("Ip")
        end
      end
    end

    context "with empty CSV" do
      let(:csv_content) { "" }

      it "returns error result" do
        result = service.call
        expect(result.success?).to be false
        expect(result.errors).to include(hash_including(message: /empty/i))
      end
    end

    context "with header-only CSV" do
      let(:csv_content) do
        <<~CSV
          hostname,ip,role,arch
        CSV
      end

      it "returns success with zero counts" do
        result = service.call
        expect(result.success?).to be true
        expect(result.created_count).to eq(0)
      end
    end

    context "with missing required headers" do
      let(:csv_content) do
        <<~CSV
          ip,role,arch
          192.168.1.101,compute,x86_64
        CSV
      end

      it "returns error result" do
        result = service.call
        expect(result.success?).to be false
        expect(result.errors).to include(hash_including(message: /hostname/i))
      end
    end

    context "with extra columns (ignored)" do
      let(:csv_content) do
        <<~CSV
          hostname,ip,role,arch,extra_column
          compute-001,192.168.1.101,compute,x86_64,ignored_value
        CSV
      end

      it "ignores extra columns and creates node" do
        expect { service.call }.to change(Node, :count).by(1)
      end
    end

    context "with different role values" do
      let(:csv_content) do
        <<~CSV
          hostname,ip,role,arch
          node-1,192.168.1.1,compute,x86_64
          node-2,192.168.1.2,login,x86_64
          node-3,192.168.1.3,admin,x86_64
        CSV
      end

      it "creates nodes with correct roles" do
        service.call
        expect(Node.find_by(hostname: "node-1")).to be_compute
        expect(Node.find_by(hostname: "node-2")).to be_login
        expect(Node.find_by(hostname: "node-3")).to be_admin
      end
    end

    context "with duplicate hostnames in CSV" do
      let(:csv_content) do
        <<~CSV
          hostname,ip,role,arch
          compute-001,192.168.1.101,compute,x86_64
          compute-001,192.168.1.102,compute,aarch64
        CSV
      end

      it "uses the last occurrence" do
        service.call
        node = Node.find_by(hostname: "compute-001")
        expect(node.ip).to eq("192.168.1.102")
        expect(node.arch).to eq("aarch64")
      end

      it "creates only one node" do
        expect { service.call }.to change(Node, :count).by(1)
      end
    end
  end
end
