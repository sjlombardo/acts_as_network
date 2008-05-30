ActiveRecord::Schema.define(:version => 1) do

  create_table :channels, :force => true do |t|
    t.column :name, :string
  end

  create_table :shows, :force => true do |t|
    t.column :name, :string
    t.column :channel_id, :integer
    t.column :package, :string
  end

  # people
  create_table :people, :force => true do |t|
    t.column :name, :string
  end

  # people_people
  create_table :people_people, {:id => false} do |t|
    t.column :person_id, :integer, :null => false
    t.column :person_id_target, :integer, :null => false
  end
  
  # invites
  create_table :invites, :force => true do |t|
    t.column :person_id,  :integer, :null => false
    t.column :person_id_target,   :integer, :null => false
    t.column :message, :text
    t.column :is_accepted, :boolean
  end
  
  # friends
  create_table :friends, {:id => false} do |t|
    t.column :person_id, :integer, :null => false
    t.column :person_id_friend, :integer, :null => false
  end
  
end