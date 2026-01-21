# frozen_string_literal: true

require "rails_helper"

RSpec.describe NotificationsChannel, type: :channel do
  let(:user) { create(:user) }

  describe "#subscribed" do
    context "with valid user" do
      before do
        stub_connection current_user: user
      end

      it "streams from the user's notifications channel" do
        subscribe
        expect(subscription).to be_confirmed
        expect(subscription).to have_stream_from("notifications_user_#{user.id}")
      end
    end

    context "without user" do
      before do
        stub_connection current_user: nil
      end

      it "rejects the subscription" do
        subscribe
        expect(subscription).to be_rejected
      end
    end
  end

  describe "#unsubscribed" do
    before do
      stub_connection current_user: user
    end

    it "stops all streams" do
      subscribe
      expect(subscription).to be_confirmed

      subscription.unsubscribe_from_channel
      expect(subscription).not_to have_streams
    end
  end
end
