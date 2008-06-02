require File.join(File.dirname(__FILE__), 'test_helper')

class Channel < ActiveRecord::Base
  has_many :shows
  has_many :premium_shows, :class_name => 'Show', :conditions => ['package = ?', 'premium']
  has_many :mega_shows, :class_name => 'Show', :conditions => ['package = ?', 'mega']
  acts_as_union :pay_shows, [ :premium_shows, :mega_shows ]
end

class Show < ActiveRecord::Base
  belongs_to :channel
end


class Person < ActiveRecord::Base
  
  # network relationship using has_many :through invites
  acts_as_network :contacts, :through => :invites
  
  # network relation through invotes with additional conditions
  acts_as_network :acquaintances, :through => :invites, :conditions => ["invites.is_accepted = 't'"]
  
  # simple network relation through a has_and_belongs_to_many table
  acts_as_network :connections
  
  # network relations has_and_belongs_to_many with custom table and foreign_key names
  acts_as_network :friends, :join_table => :friends, :foreign_key => 'person_id', 
                  :association_foreign_key => 'person_id_friend'
  
  # network relationship with has_many_through and overrides
  acts_as_network :colleagues, :through => :invites, 
                  :foreign_key => 'person_id', :association_foreign_key => 'person_id_target', 
                  :conditions => ["is_accepted = 't'"]
                  
  # simple usage of acts_as_union to combine friends and colleagues sets
  acts_as_union   :associates, [:friends, :colleagues]
                                 
end

class Invite < ActiveRecord::Base
  belongs_to :person
  belongs_to :person_target, :class_name => 'Person', :foreign_key => 'person_id_target'
  validates_presence_of :person, :person_target
end

class Array
  def ids
    collect &:id
  end
end

class UnionCollectionTest < Test::Unit::TestCase
  fixtures :shows, :channels
  
  def setup
    @union = Zetetic::Acts::UnionCollection.new(
      channels(:discovery).shows,
      channels(:usa).shows,
      channels(:amc).shows
    )
  end
  
  def test_union_non_collection
    union = Zetetic::Acts::UnionCollection.new(
      Person.find(:all, :conditions => "id <= 1"),
      Person.find(:all, :conditions => "id >= 2 AND id <= 4"),
      Person.find(:all, :conditions => "id >= 5")
    )
    assert_equal 7, @union.size
  end
  
  def test_standard_finder
    set = channels(:usa).shows
    assert_equal "Monk", set.find_by_name("Monk").name
    assert_equal("Burn Notice", set.find(
        :first, :conditions => "channel_id = 1", 
        :order => "name").name) # dynamic initial finder syntax
  end
  
  def test_union_finder_all
    assert_equal 7, @union.size # check raw size of @union array
    assert_equal 7, @union.find(:all).size # verify size returned from finder
  end
  
  def test_union_find_first
    assert_equal "Monk", @union.find_by_name("Monk").name # dynamic initial finder syntax
    
    assert_equal 3, @union.find_all_by_channel_id(0).size # dynamic all finder
    
    assert_equal("Mad Men", @union.find(
        :first, :conditions => "id = 6", 
        :order => "name").name) # dynamic initial finder syntax
    
    assert_equal("Burn Notice", @union.find(
        :first, :conditions => "channel_id = 1", 
        :order => "name").name) # dynamic initial finder syntax
  end
  
  def test_union_find_by_ids
    assert_equal 7, @union.find(0,1,2,3,4,5,6).size # find by ids accross muliple collections
    assert @union.find(0,1,2,3,4,5,6).kind_of?(Array)
    assert @union.find(0).kind_of?(Show)
    assert @union.find(0,0).kind_of?(Array)
    assert_equal 1, @union.find(0,0).size
    
    begin # verify that find by id for an unknown id fails
      @union.find(2,3,4,900)
      fail "should have failed with ActiveRecord::RecordNotFound error"
    rescue ActiveRecord::RecordNotFound 
    end
    
  end
  
  def test_find_with_scope
    Show.send(:with_scope, :find => {:conditions => "channel_id = 1"}) do
      assert_not_nil @union.find(4)
      assert_not_nil @union.find_by_name("Monk")
      assert_not_nil @union.find(:first, :conditions => ["name = ?", "Psych"])
      
      assert_nil @union.find(:first, :conditions => "id = 6", :order => "name")
      begin # verify that find by id for an out of scope id fails
        @union.find(2)
        fail "should have failed with ActiveRecord::RecordNotFound error"
      rescue ActiveRecord::RecordNotFound 
      end
    end
  end
  
  def test_empty_sets
    assert_equal Zetetic::Acts::UnionCollection.new().size, 0
    assert_equal Zetetic::Acts::UnionCollection.new().to_ary, []
    assert_equal Zetetic::Acts::UnionCollection.new([],[]).size, 0
    assert_equal Zetetic::Acts::UnionCollection.new([],[]).to_ary, []
    assert_equal Zetetic::Acts::UnionCollection.new(nil,nil).size, 0
    assert_equal Zetetic::Acts::UnionCollection.new(nil,nil).to_ary, []
    assert_equal Zetetic::Acts::UnionCollection.new([],nil).size, 0
    assert_equal Zetetic::Acts::UnionCollection.new([],nil).to_ary, []
  end
  
  def test_mixed_sets
    union = Zetetic::Acts::UnionCollection.new(
      channels(:discovery).shows, # one populated set
      channels(:discovery).shows.find_all_by_name("does not exist"),
      nil
    )
    
    assert_equal "Dirty Jobs", union.find_by_name('Dirty Jobs').name
    assert_equal channels(:discovery).shows.size, union.size
  end
  
  def test_unique
    # adding the same set twice should not affect the size of the union
    # collection or the results that are returned (no duplicates)
    union = Zetetic::Acts::UnionCollection.new(
      channels(:discovery).shows, 
      channels(:discovery).shows
    )
    
    assert_equal "Dirty Jobs", union.find_by_name('Dirty Jobs').name
    assert_equal channels(:discovery).shows.size, union.size
    assert_equal channels(:discovery).shows.size, union.find(:all).size
  end
  
  def test_lazy_load
    # internal array should start out nil
    assert_nil @union.instance_variable_get(:@arr)
    
    # finder operations shouldn't affect state
    @union.find(0)
    assert_nil @union.instance_variable_get(:@arr)
    
    # array operations should cause data load
    @union.collect{|a| a}
    assert !@union.instance_variable_get(:@arr).empty?
  end
end

class ActsAsUntionTest < Test::Unit::TestCase
  fixtures :shows, :channels
  
  def test_union_method
    assert_equal 0, channels(:abc).pay_shows.length
    assert_equal 3, channels(:discovery).pay_shows.length
  end
end

class ActsAsNetworkTest < Test::Unit::TestCase
  fixtures :people, :people_people, :invites

  def test_habtm_assignments
    jane = Person.create(:name => 'Jane')
    jack = Person.create(:name => 'Jack')
    
    [jane, jack].each do |person|
      assert person.respond_to?(:friends)
      assert person.respond_to?(:friends_out)
      assert person.respond_to?(:friends_in)
    end
    
    jane.friends_in << jack             # Jane adds Jack as a friend
    
    assert jane.friends_in.include?(jack)
    assert jane.friends.include?(jack)  # Jack is Janes friend
    
    assert jack.friends_out.include?(jane)
    assert jack.friends.include?(jane)  # Jane is also Jack's friend!
  end
  
  def test_hmt_assignments
    jane = Person.create(:name => 'Jane')
    jack = Person.create(:name => 'Jack')
    
    [jane, jack].each do |person|
      assert person.respond_to?(:colleagues)
      assert person.respond_to?(:invites_out)
      assert person.respond_to?(:invites_in)
      assert person.respond_to?(:colleagues_out)
      assert person.respond_to?(:colleagues_in)
    end
    
    # Jane invites Jack to be friends
    invite = Invite.create(:person => jane, :person_target => jack, :message => "let's be friends!")    
    
    assert jane.invites_out.include?(invite)
    assert jack.invites_in.include?(invite)
    
    assert !jane.colleagues.include?(jack)  # Jack is not yet Jane's friend
    assert !jack.colleagues.include?(jane)  # Jane is not yet Jack's friend either

    invite.is_accepted = true  # Now Jack accepts the invite
    invite.save
    
    jane.reload and jack.reload
    
    assert jane.colleagues.include?(jack)  # Jack is Janes friend now
    assert jack.colleagues.include?(jane)  # Jane is also Jacks friend
  end
  
  def test_assigments_conditions
    jane = Person.create(:name => 'Jane')
    jack = Person.create(:name => 'Jack')
    alex = Person.create(:name => 'Alex')
    
    # Jane invited Jack to be friends
    invite = Invite.create(:person => jane, :person_target => jack, :message => "let's be friends!", :is_accepted => true)
    
    # Jack invited Alex to be friends
    invite = Invite.create(:person => jack, :person_target => alex, :message => "let's be friends!", :is_accepted => true)

    jane.reload and jack.reload and alex.reload

    assert_equal [alex].to_ary, jack.colleagues.find(:all, :conditions => { :name => "Alex" }).to_ary
  end
  
  def test_outbound_habtm
    assert_equal 2, people(:helene).connections_out.size
    assert_equal 1, people(:mary).connections_out.size
    assert_equal 1, people(:stephen).connections_out.size
    assert_equal 0, people(:vincent).connections_out.size
    assert_equal 1, people(:carmen).connections_out.size
  end
  
  def test_outbound_hmt
    assert_equal 2, people(:helene).contacts_out.size
    assert_equal 1, people(:mary).contacts_out.size
    assert_equal 1, people(:stephen).contacts_out.size
    assert_equal 0, people(:vincent).contacts_out.size
    assert_equal 1, people(:carmen).contacts_out.size
  end
  
  def test_conditional_outbound_hmt
    assert_equal 1, people(:helene).acquaintances_out.size
    assert_equal 0, people(:mary).acquaintances_out.size
    assert_equal 0, people(:stephen).acquaintances_out.size
    assert_equal 0, people(:vincent).acquaintances_out.size
    assert_equal 1, people(:carmen).acquaintances_out.size
  end

  def test_inbound_habtm
    assert_equal 1, people(:helene).connections_in.size
    assert_equal 0, people(:mary).connections_in.size
    assert_equal 2, people(:stephen).connections_in.size
    assert_equal 2, people(:vincent).connections_in.size
    assert_equal 0, people(:carmen).connections_in.size
  end
  
  def test_inbound_hmt
    assert_equal 1, people(:helene).contacts_in.size
    assert_equal 0, people(:mary).contacts_in.size
    assert_equal 2, people(:stephen).contacts_in.size
    assert_equal 2, people(:vincent).contacts_in.size
    assert_equal 0, people(:carmen).contacts_in.size
  end
  
  def test_conditional_inbound_hmt
    assert_equal 1, people(:helene).acquaintances_in.size
    assert_equal 0, people(:mary).acquaintances_in.size
    assert_equal 0, people(:stephen).acquaintances_in.size
    assert_equal 1, people(:vincent).acquaintances_in.size
    assert_equal 0, people(:carmen).acquaintances_in.size
  end
  
  def test_union_habtm
    assert_equal 3, people(:helene).connections.size
    assert_equal 1, people(:mary).connections.size
    assert_equal 3, people(:stephen).connections.size
    assert_equal 2, people(:vincent).connections.size
    assert_equal 1, people(:carmen).connections.size
  end
  
  def test_union_hmt
    assert_equal 3, people(:helene).contacts.size
    assert_equal 1, people(:mary).contacts.size
    assert_equal 3, people(:stephen).contacts.size
    assert_equal 2, people(:vincent).contacts.size
    assert_equal 1, people(:carmen).contacts.size
  end
  
  def test_conditional_union_hmt
    assert_equal 2, people(:helene).acquaintances.size
    assert_equal 0, people(:mary).acquaintances.size
    assert_equal 0, people(:stephen).acquaintances.size
    assert_equal 1, people(:vincent).acquaintances.size
    assert_equal 1, people(:carmen).acquaintances.size    
  end
end