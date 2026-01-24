# frozen_string_literal: true

module RangeOverlap
  extend ActiveSupport::Concern

  # Checks if two ranges overlap (inclusive boundaries)
  # @param a_start [Integer] Start of first range
  # @param a_end [Integer] End of first range
  # @param b_start [Integer] Start of second range
  # @param b_end [Integer] End of second range
  # @return [Boolean] true if ranges overlap
  def ranges_overlap?(a_start, a_end, b_start, b_end)
    a_start <= b_end && b_start <= a_end
  end
end
