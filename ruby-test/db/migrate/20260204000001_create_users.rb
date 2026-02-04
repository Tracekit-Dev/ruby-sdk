# frozen_string_literal: true

class CreateUsers < ActiveRecord::Migration[7.1]
  def change
    create_table :users do |t|
      t.string :name
      t.string :email
      t.integer :age
      t.timestamps
    end

    # Add some seed data
    User.create(name: "Alice", email: "alice@example.com", age: 30)
    User.create(name: "Bob", email: "bob@example.com", age: 25)
    User.create(name: "Charlie", email: "charlie@example.com", age: 35)
  end
end
