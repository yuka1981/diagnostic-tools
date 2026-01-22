# frozen_string_literal: true

FactoryBot.define do
  factory :ssh_profile do
    sequence(:name) { |n| "SSH Profile #{n}" }
    ssh_connect_method { :global_bastion }
    ssh_port { 22 }
    ssh_user { "deploy" }

    trait :direct do
      ssh_connect_method { :direct }
    end

    trait :global_bastion do
      ssh_connect_method { :global_bastion }
    end

    trait :custom_bastion do
      ssh_connect_method { :custom_bastion }
      jump_host { "bastion.example.com" }
      jump_user { "bastion_user" }
      jump_port { 22 }
    end

    trait :with_key do
      ssh_key { "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQ..." }
    end

    trait :with_password do
      ssh_password { "secret123" }
    end
  end
end
