# frozen_string_literal: true

namespace :agent_releases do
  desc "Migrate legacy single binaries to multi-arch AgentBinary model"
  task migrate_to_multi_arch: :environment do
    puts "Migrating AgentRelease binaries to AgentBinary model..."

    migrated = 0
    skipped = 0
    errors = 0

    AgentRelease.find_each do |release|
      # Skip if no legacy binary attached
      unless release.binary.attached?
        puts "  [SKIP] #{release.version}: No legacy binary attached"
        skipped += 1
        next
      end

      # Skip if already has AgentBinary records
      if release.agent_binaries.any?
        puts "  [SKIP] #{release.version}: Already has AgentBinary records"
        skipped += 1
        next
      end

      # Detect architecture from filename or default to x86_64
      filename = release.binary.filename.to_s.downcase
      arch = if filename.include?("aarch64") || filename.include?("arm64")
        "aarch64"
      else
        "x86_64"
      end

      puts "  [MIGRATE] #{release.version} -> #{arch}"

      begin
        # Create AgentBinary with the same binary blob
        agent_binary = release.agent_binaries.build(
          arch: arch,
          checksum: release.checksum
        )

        # Attach the same blob to the new record
        agent_binary.binary.attach(release.binary.blob)

        if agent_binary.save
          migrated += 1
          puts "    Created AgentBinary for #{release.version} (#{arch})"
        else
          errors += 1
          puts "    [ERROR] Failed to create AgentBinary: #{agent_binary.errors.full_messages.join(', ')}"
        end
      rescue StandardError => e
        errors += 1
        puts "    [ERROR] #{e.message}"
      end
    end

    puts "\nMigration complete:"
    puts "  Migrated: #{migrated}"
    puts "  Skipped: #{skipped}"
    puts "  Errors: #{errors}"
  end

  desc "Clean up legacy binary attachments after successful migration"
  task cleanup_legacy_binaries: :environment do
    puts "Cleaning up legacy AgentRelease binaries..."

    cleaned = 0
    skipped = 0

    AgentRelease.find_each do |release|
      # Only clean up if has AgentBinary records and legacy binary
      if release.agent_binaries.any? && release.binary.attached?
        puts "  [CLEANUP] #{release.version}: Removing legacy binary"
        release.binary.purge
        cleaned += 1
      else
        skipped += 1
      end
    end

    puts "\nCleanup complete:"
    puts "  Cleaned: #{cleaned}"
    puts "  Skipped: #{skipped}"
  end
end
