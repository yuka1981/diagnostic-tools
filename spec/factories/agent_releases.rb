# frozen_string_literal: true

FactoryBot.define do
  factory :agent_release do
    sequence(:version) { |n| "v1.0.#{n}" }
    release_notes { "Bug fixes and improvements" }
    status { :active }

    # Skip checksum validation for factory builds
    transient do
      skip_binary { false }
    end

    after(:build) do |release, evaluator|
      next if evaluator.skip_binary

      # Create a real file for the attachment
      file_content = "#!/bin/bash\necho 'mock agent v#{release.version}'"
      file = Tempfile.new([ "hpc-agent", "" ])
      file.binmode
      file.write(file_content)
      file.rewind

      release.binary.attach(
        io: file,
        filename: "hpc-agent",
        content_type: "application/octet-stream"
      )
    end

    trait :deprecated do
      status { :deprecated }
    end

    trait :recalled do
      status { :recalled }
    end

    trait :with_release_notes do
      release_notes do
        <<~NOTES
          ## Changes in this release

          - Fixed memory leak in collector module
          - Added support for new CPU architectures
          - Improved benchmark result parsing
        NOTES
      end
    end

    trait :without_binary do
      skip_binary { true }
    end
  end
end
