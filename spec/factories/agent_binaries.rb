# frozen_string_literal: true

FactoryBot.define do
  factory :agent_binary do
    association :agent_release, factory: [ :agent_release, :without_binary ]
    arch { "x86_64" }

    after(:build) do |agent_binary|
      # Create a real file for the attachment
      file_content = "#!/bin/bash\necho 'mock agent #{agent_binary.arch}'"
      file = Tempfile.new([ "hpc-agent-#{agent_binary.arch}", "" ])
      file.binmode
      file.write(file_content)
      file.rewind

      agent_binary.binary.attach(
        io: file,
        filename: "hpc-agent-#{agent_binary.arch}",
        content_type: "application/octet-stream"
      )
    end

    trait :aarch64 do
      arch { "aarch64" }
    end

    trait :x86_64 do
      arch { "x86_64" }
    end
  end
end
