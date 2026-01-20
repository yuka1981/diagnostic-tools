# frozen_string_literal: true

require "rails_helper"

RSpec.describe SidebarHelper, type: :helper do
  describe "#sidebar_collapsed?" do
    it "returns true when cookie is set to 'true'" do
      helper.request.cookies[:sidebar_collapsed] = "true"

      expect(helper.sidebar_collapsed?).to be true
    end

    it "returns false when cookie is set to 'false'" do
      helper.request.cookies[:sidebar_collapsed] = "false"

      expect(helper.sidebar_collapsed?).to be false
    end

    it "returns false when cookie is not set" do
      expect(helper.sidebar_collapsed?).to be false
    end
  end
end
