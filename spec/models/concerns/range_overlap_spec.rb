# frozen_string_literal: true

require "rails_helper"

RSpec.describe RangeOverlap do
  let(:test_class) do
    Class.new do
      include RangeOverlap
    end
  end

  subject(:instance) { test_class.new }

  describe "#ranges_overlap?" do
    it "returns true when ranges overlap completely" do
      expect(instance.ranges_overlap?(1, 5, 2, 4)).to be true
    end

    it "returns true when ranges overlap partially" do
      expect(instance.ranges_overlap?(1, 5, 4, 8)).to be true
    end

    it "returns true when ranges share an edge" do
      expect(instance.ranges_overlap?(1, 5, 5, 8)).to be true
    end

    it "returns false when ranges do not overlap" do
      expect(instance.ranges_overlap?(1, 5, 6, 10)).to be false
    end

    it "returns true when one range contains another" do
      expect(instance.ranges_overlap?(1, 10, 3, 7)).to be true
    end
  end
end
