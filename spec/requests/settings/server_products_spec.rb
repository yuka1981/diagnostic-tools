# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Settings::ServerProducts", type: :request do
  let(:approver) { create(:user, :approver) }
  let(:viewer) { create(:user) }

  describe "GET /settings/server_products" do
    context "when authenticated as approver" do
      before { sign_in approver }

      it "returns success" do
        get settings_server_products_path
        expect(response).to have_http_status(:success)
      end

      it "displays server products" do
        product = create(:server_product, name: "QuantaGrid D54Q-2U")
        get settings_server_products_path
        expect(response.body).to include("QuantaGrid D54Q-2U")
      end

      it "displays last sync information" do
        create(:sync_log, source: "qct", completed_at: 1.day.ago)
        get settings_server_products_path
        expect(response.body).to include("Last synced")
      end
    end

    context "when authenticated as viewer" do
      before { sign_in viewer }

      it "redirects to root" do
        get settings_server_products_path
        expect(response).to redirect_to(root_path)
      end
    end

    context "when not authenticated" do
      it "redirects to sign in" do
        get settings_server_products_path
        expect(response).to redirect_to(new_user_session_path)
      end
    end

    describe "pagination" do
      before do
        sign_in approver
        create_list(:server_product, 15)
      end

      it "paginates results to 10 per page" do
        get settings_server_products_path
        doc = Nokogiri::HTML(response.body)
        product_rows = doc.css("tbody tr")
        expect(product_rows.size).to eq(10)
      end

      it "shows second page when requested" do
        get settings_server_products_path, params: { page: 2 }
        doc = Nokogiri::HTML(response.body)
        product_rows = doc.css("tbody tr")
        expect(product_rows.size).to eq(5)
      end
    end
  end

  describe "GET /settings/server_products/new" do
    before { sign_in approver }

    it "returns success" do
      get new_settings_server_product_path
      expect(response).to have_http_status(:success)
    end
  end

  describe "POST /settings/server_products" do
    before { sign_in approver }

    context "with valid params" do
      let(:valid_params) do
        {
          server_product: {
            name: "QuantaGrid Test-1U",
            product_series: "QuantaGrid",
            form_factor: "1U",
            rack_height: 1
          }
        }
      end

      it "creates a new server product" do
        expect {
          post settings_server_products_path, params: valid_params
        }.to change(ServerProduct, :count).by(1)
      end

      it "redirects to index" do
        post settings_server_products_path, params: valid_params
        expect(response).to redirect_to(settings_server_products_path)
      end
    end

    context "with invalid params" do
      let(:invalid_params) { { server_product: { name: "" } } }

      it "does not create a server product" do
        expect {
          post settings_server_products_path, params: invalid_params
        }.not_to change(ServerProduct, :count)
      end

      it "renders new with unprocessable_entity" do
        post settings_server_products_path, params: invalid_params
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe "GET /settings/server_products/:id/edit" do
    let!(:product) { create(:server_product) }
    before { sign_in approver }

    it "returns success" do
      get edit_settings_server_product_path(product)
      expect(response).to have_http_status(:success)
    end
  end

  describe "PATCH /settings/server_products/:id" do
    let!(:product) { create(:server_product) }
    before { sign_in approver }

    context "with valid params" do
      it "updates the product" do
        patch settings_server_product_path(product), params: { server_product: { name: "Updated Name" } }
        expect(product.reload.name).to eq("Updated Name")
      end

      it "redirects to index" do
        patch settings_server_product_path(product), params: { server_product: { name: "Updated Name" } }
        expect(response).to redirect_to(settings_server_products_path)
      end
    end
  end

  describe "DELETE /settings/server_products/:id" do
    let!(:product) { create(:server_product) }
    before { sign_in approver }

    it "deletes the product" do
      expect {
        delete settings_server_product_path(product)
      }.to change(ServerProduct, :count).by(-1)
    end

    it "redirects to index" do
      delete settings_server_product_path(product)
      expect(response).to redirect_to(settings_server_products_path)
    end
  end

  describe "GET /settings/server_products/:id" do
    let!(:product) { create(:server_product) }
    before { sign_in approver }

    it "returns success" do
      get settings_server_product_path(product)
      expect(response).to have_http_status(:success)
    end
  end
end
