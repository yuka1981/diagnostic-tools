# frozen_string_literal: true

module SidebarHelper
  def sidebar_rooms
    Room.order(:name)
  end
end
