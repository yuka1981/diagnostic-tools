# frozen_string_literal: true

namespace :agent_releases do
  desc "Recalculate checksums for all agent releases with invalid format"
  task recalculate_checksums: :environment do
    puts "Scanning agent releases for invalid checksums..."

    total = AgentRelease.count
    puts "Found #{total} agent release(s)"

    results = AgentRelease.recalculate_invalid_checksums!

    puts "\nResults:"
    puts "  - Recalculated: #{results[:success]}"
    puts "  - Already valid: #{results[:skipped]}"
    puts "  - Failed: #{results[:failed]}"

    if results[:failed] > 0
      puts "\nWarning: Some checksums could not be recalculated. Check logs for details."
      exit 1
    end

    puts "\nDone!"
  end

  desc "Show checksum status for all agent releases"
  task checksum_status: :environment do
    puts "Agent Release Checksum Status"
    puts "=" * 60

    AgentRelease.latest_first.each do |release|
      status = if release.checksum.blank?
        "MISSING"
      elsif release.valid_sha256_checksum?
        "OK (SHA256)"
      else
        "INVALID (#{release.checksum.length} chars, likely MD5 Base64)"
      end

      puts "#{release.version.ljust(15)} #{status}"
    end
  end
end
