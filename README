= acts_as_network

acts_as_network is intended to simplify the definition 
and storage of reciprocal relationships between entities using
ActiveRecord, exposing a "network" of 2-way connections between
records. It does this in DRY way using only <b>a single record</b>
in a <tt>has_and_belongs_to_many</tt> join table or <tt>has_many :through</tt> 
join model. Thus, there is no redundancy and you need only one instance of 
an association or join model to represent both directions of the relationship.

This is especially useful for social networks where 
a "friend" relationship in one direction implies the reverse 
relationship (when Jack is a friend of Jane then Jane should also
be a friend of Jack). 

{Zetetic LLC}[http://www.zetetic.net] extracted acts_as_network from
PingMe[http://www.gopingme.com] where it drives the social 
networking features of the site.

== INSTALLATION (git on edge rails)

  % cd rails_project_path
  % ./script/plugin install git://github.com/sjlombardo/acts_as_network.git
  % rake doc:plugins

== INSTALLATION (subversion, rails <= 2.0.2))
 
  % cd rails_project_path
  % script/plugin source http://actsasnetwork.rubyforge.org/svn/plugins
  % script/plugin install acts_as_network  
  % rake doc:plugins 

== GitHub

  http://github.com/sjlombardo/acts_as_network/tree/master

= INTRODUCTION

The usual way of representing network relationships in a database is 
to use an intermediate, often self-referential, join table (HABTM). 
For example one might define a simple person type

  create_table :people, :force => true do |t|
    t.column :name, :string
  end

and then a join table to store the friendship relation

  create_table :friends, {:id => false} do |t|
    t.column :person_id, :integer, :null => false
    t.column :person_id_friend, :integer, :null => false      # target of the relationship
  end

Unfortunately this model requires TWO rows in the intermediate table to
make a relationship bi-directional

  jane = Person.create(:name => 'Jane')
  jack = Person.create(:name => 'Jack')
  
  jane.friends << jack              # Jack is Janes friend
  jane.friends.include?(jack)    =>  true

Clearly Jack is Jane's friend, yet Jane is *not* Jack's friend

  jack.friends.include?(jane)    => false

unless you need to explicitly define the reverse relation

  jack.friends << jane

Of course, this isn't horrible, and can in fact be implemented
in a fairly DRY way using association callbacks. However, things get
more complicated when you consider disassociation (what to do when Jane 
doesn't want to be friends with Jack any more), or the very common
case where you want to express the relationship through a more complicated
join model via <tt>has_many :through</tt>

  create_table :invites do |t|
    t.column :person_id, :integer, :null => false           # source of the relationship
    t.column :person_id_friend, :integer, :null => false    # target of the relationship
    t.column :code, :string                                 # random invitation code
    t.column :message, :text                                # invitation message
    t.column :is_accepted, :boolean
    t.column :accepted_at, :timestamp                       # when did they accept?
  end

In this case creating a reverse relationship is painful, and depending on 
validations might require the duplication of multiple values, making the
data model decidedly un-DRY.

== Using acts_as_network

Acts As Network DRYs things up by representing only a single record
in a <tt>has_and_belongs_to_many</tt> join table or <tt>has_many :through</tt> 
join model. Thus, you only need one instance of an association or join model to
represent both directions of the relationship.

== With HABTM

For a HABTM style relationship, it's as simple as

  class Person < ActiveRecord::Base
    acts_as_network :friends, :join_table => :friends
  end

In this case <tt>acts_as_network</tt> will expose three new properies
on the Person model
  
  me.friends_out        # friends where I have originated the friendship relationship 
                        # target in another entry (people I consider friends)

  me.friends_in         # friends where a different entry has originated the freindship 
                        # with me (people who consider me a friend)

  me.friends            # the union of the two sets, that is all people who I consider 
                        # friends and all those who consider me a friend

Thus

  jane = Person.create(:name => 'Jane')
  jack = Person.create(:name => 'Jack')
  
  jane.friends_out << jack                  # Jane adds Jack as a friend
  jane.friends.include?(jack)    =>  true   # Jack is Janes friend
  jack.friends.include?(jane)    =>  true   # Jane is also Jack's friend!

== With a join model

This may seem more natural when considering a join style with a proper Invite model. In this case
one person will "invite" another person to be friends.

  class Invite < ActiveRecord::Base
    belongs_to :person
    belongs_to :person_target, :class_name => 'Person', :foreign_key => 'person_id_target'        # the target of the friend relationship 
    validates_presence_of :person, :person_target
  end

  class Person < ActiveRecord::Base
    acts_as_network :friends, :through => :invites, :conditions => "is_accepted = 't'"
  end

In this case <tt>acts_as_network</tt> implicitly defines five new properies
on the Person model
  
  person.invites_out        # has_many invites originating from me to others
  person.invites_in         # has_many invites orginiating from others to me
  person.friends_out        # has_many friends :through outbound accepted invites from me to others
  person.friends_in         # has_many friends :through inbound accepted invites from others to me
  person.friends            # the union of the two friend sets - all people who I have
                        # invited and all the people who have invited me

Thus

  jane = Person.create(:name => 'Jane')
  jack = Person.create(:name => 'Jack')

  # Jane invites Jack to be friends
  invite = Invite.create(:person => jane, :person_target => jack, :message => "let's be friends!")    
  
  jane.friends.include?(jack)    =>  false   # Jack is not yet Jane's friend
  jack.friends.include?(jane)    =>  false   # Jane is not yet Jack's friend either

  invite.is_accepted = true  # Now Jack accepts the invite
  invite.save and jane.reload and jack.reload

  jane.friends.include?(jack)    =>  true   # Jack is Janes friend now
  jack.friends.include?(jane)    =>  true   # Jane is also Jacks friend

For more details and specific options see Zetetic::Acts::Network::ClassMethods

The applications of this plugin to social network situations are fairly obvious,
but it should also be usable in the general case to represent inherant 
bi-directional relationships between entities.

= TESTS

The plugin's unit tests are located in +test+ directory under 
<tt>vendor/plugins/acts_as_network</tt>. Run:

  [%] cd vendor/plugins/acts_as_network
  [%] ruby test/network_test.rb

This will create a temporary sqlite3 database, a number of tables,
fixture data, and run the tests. You can delete the sqlite database
when you are done.

  [%] rm acts_as_network.test.db
  
The test suite requires sqlite3. 
