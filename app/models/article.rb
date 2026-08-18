class Article < ApplicationRecord
  validates :title, presence: true
  validates :body, presence: true
  validates :status, inclusion: { in: %w[draft published] }

  after_commit :broadcast_status

  private

  def broadcast_status
    if self.previous_changes.key?("status")
      LiveTracking.broadcast(self)
    end
  end
end
