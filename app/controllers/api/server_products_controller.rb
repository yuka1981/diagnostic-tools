# frozen_string_literal: true

module Api
  class ServerProductsController < ApplicationController
    skip_before_action :verify_authenticity_token
    skip_forgery_protection

    def index
      products = ServerProduct.all
      products = products.by_series(params[:series]) if params[:series].present?
      products = products.by_form_factor(params[:form_factor]) if params[:form_factor].present?
      products = products.order(:name)

      render json: products.map { |p| product_json(p) }
    end

    def search
      products = ServerProduct
        .search_by_name(params[:q])
        .limit(10)
        .order(:name)

      render json: products.map { |p| product_json(p) }
    end

    private

    def product_json(product)
      {
        id: product.id,
        name: product.name,
        product_series: product.product_series,
        form_factor: product.form_factor,
        rack_height: product.rack_height,
        cpu_generations: product.cpu_generations,
        max_memory_gb: product.max_memory_gb,
        gpu_support: product.gpu_support,
        thumbnail_url: product.images.attached? ? url_for(product.images.first.variant(resize_to_limit: [ 100, 100 ])) : nil
      }
    end
  end
end
