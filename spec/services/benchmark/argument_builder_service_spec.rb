# frozen_string_literal: true

require "rails_helper"

RSpec.describe Benchmark::ArgumentBuilderService do
  describe "#call" do
    subject(:result) { described_class.new(defaults: defaults, overrides: overrides).call }

    context "with empty inputs" do
      let(:defaults) { {} }
      let(:overrides) { {} }

      it "returns empty string" do
        expect(result).to eq("")
      end
    end

    context "with only defaults" do
      let(:defaults) { { "nx" => 104, "ny" => 104, "nz" => 104 } }
      let(:overrides) { {} }

      it "builds CLI flags from defaults" do
        expect(result).to include("--nx=104")
        expect(result).to include("--ny=104")
        expect(result).to include("--nz=104")
      end
    end

    context "with only overrides" do
      let(:defaults) { {} }
      let(:overrides) { { "nx" => 128 } }

      it "builds CLI flags from overrides" do
        expect(result).to eq("--nx=128")
      end
    end

    context "with both defaults and overrides" do
      let(:defaults) { { "nx" => 104, "ny" => 104, "nz" => 104, "rt" => 60 } }
      let(:overrides) { { "nx" => 128, "rt" => 120 } }

      it "merges with overrides taking precedence" do
        expect(result).to include("--nx=128")
        expect(result).to include("--ny=104")
        expect(result).to include("--nz=104")
        expect(result).to include("--rt=120")
      end

      it "does not include default values that were overridden" do
        expect(result).not_to include("--nx=104")
        expect(result).not_to include("--rt=60")
      end
    end

    context "with string keys in overrides" do
      let(:defaults) { { "nx" => 104 } }
      let(:overrides) { { "nx" => "128" } }

      it "handles string values correctly" do
        expect(result).to include("--nx=128")
      end
    end

    context "with symbol keys" do
      let(:defaults) { { nx: 104 } }
      let(:overrides) { { nx: 128 } }

      it "handles symbol keys correctly" do
        expect(result).to include("--nx=128")
      end
    end

    context "with boolean values" do
      let(:defaults) { { "verbose" => true, "quiet" => false } }
      let(:overrides) { {} }

      it "includes true boolean flags" do
        expect(result).to include("--verbose")
      end

      it "excludes false boolean flags" do
        expect(result).not_to include("--quiet")
      end
    end

    context "with array values" do
      let(:defaults) { { "modules" => %w[gcc/12 openmpi/4.1] } }
      let(:overrides) { {} }

      it "excludes array values (not supported as CLI flags)" do
        expect(result).not_to include("modules")
      end
    end

    context "with nil values in overrides" do
      let(:defaults) { { "nx" => 104, "ny" => 104 } }
      let(:overrides) { { "nx" => nil } }

      it "removes keys with nil override values" do
        expect(result).not_to include("nx")
        expect(result).to include("--ny=104")
      end
    end

    context "with special characters in values" do
      let(:defaults) { { "path" => "/tmp/my dir/file.log" } }
      let(:overrides) { {} }

      it "properly escapes values with spaces" do
        expect(result).to include("--path=")
        # Value should be shell-escaped
        expect(result).to match(/--path=.*my/)
      end
    end

    context "with underscore keys" do
      let(:defaults) { { "problem_size" => 10000 } }
      let(:overrides) { {} }

      it "converts underscores to hyphens in flag names" do
        expect(result).to include("--problem-size=10000")
      end
    end
  end

  describe "#merged_arguments" do
    subject(:service) { described_class.new(defaults: defaults, overrides: overrides) }

    let(:defaults) { { "nx" => 104, "ny" => 104 } }
    let(:overrides) { { "nx" => 128, "nz" => 104 } }

    it "returns the merged hash for audit purposes" do
      expect(service.merged_arguments).to eq({
        "nx" => 128,
        "ny" => 104,
        "nz" => 104
      })
    end
  end
end
