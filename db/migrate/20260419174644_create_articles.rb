class CreateArticles < ActiveRecord::Migration[8.1]
  def change
    create_table :articles do |t|
      t.string :title, null: false
      t.text :body, null: false
      t.string :status, null: false, default: "draft"
      t.timestamps
    end
  end
end
