class MlcInstallation < ApplicationRecord
  belongs_to :created_by, class_name: "User", optional: true
  has_many :mlc_installation_nodes, dependent: :destroy
  has_many :nodes, through: :mlc_installation_nodes

  enum :status, { pending: 0, running: 1, completed: 2, failed: 3, cancelled: 4 }, default: :pending
  enum :source_type, { upload: 0, shared_path: 1 }, default: :upload
  enum :failure_mode, { stop_on_first: 0, continue_on_failure: 1 }, default: :stop_on_first

  validates :uuid, presence: true, uniqueness: true

  before_validation :generate_uuid, on: :create

  def progress_percentage
    return 0 if mlc_installation_nodes.empty?

    completed = mlc_installation_nodes.where(status: [ :success, :failed, :skipped ]).count
    total = mlc_installation_nodes.count
    ((completed.to_f / total) * 100).to_i
  end

  private

  def generate_uuid
    self.uuid ||= SecureRandom.uuid
  end
end
