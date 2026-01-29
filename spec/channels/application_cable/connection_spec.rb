# frozen_string_literal: true

require "rails_helper"

RSpec.describe ApplicationCable::Connection, type: :channel do
  let(:user) { create(:user) }

  describe "#connect" do
    context "with authenticated user" do
      it "connects successfully" do
        connect "/cable", env: { "warden" => double(user: user) }
        expect(connection.current_user).to eq(user)
      end
    end

    context "without authentication" do
      it "rejects the connection" do
        expect { connect "/cable" }.to have_rejected_connection
      end
    end
  end
end
