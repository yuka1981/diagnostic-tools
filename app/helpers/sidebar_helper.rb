# frozen_string_literal: true

module SidebarHelper
  def sidebar_collapsed?
    cookies[:sidebar_collapsed] == "true"
  end
end
