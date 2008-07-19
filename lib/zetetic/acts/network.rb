#
# ActsAsNetwork contains
# * Zetetic::Acts::Network::ClassMethods - provides the actual acts_as_network ActiveRecord functionality
# * Zetetic::Acts::UnionCollection - the basis for the "union" capability that allows acts_as_network
#   to expose both inbound and outbound relationships in a single collection
#
module Zetetic #:nodoc:
  module Acts #:nodoc:  
    # = UnionCollection
    # UnionCollection provides useful application-space functionality
    # for emulating set unions acrosss ActiveRecord collections. 
    #
    # A UnionCollection can be initialized with zero or more sets, 
    # although generally it must contain at least two to do anything 
    # useful. Once initialized, the UnionCollection itself will 
    # act as an array containing all of the records from each of its 
    # member sets. The following will create a union object containing
    # the unique results of each individual find
    #
    #   union = Zetetic::Acts::UnionCollection.new(
    #     Person.find(:all, :conditions => "id <= 1"),                # set 0
    #     Person.find(:all, :conditions => "id >= 10 AND id <= 15"),  # set 1
    #     Person.find(:all, :conditions => "id >= 20")                # set 2
    #   )
    #
    # UnionCollection's more interesting feature is how it will 
    # intelligently forward ActiveRecord method calls to its member 
    # sets. This allows you to execute find operations directly on a 
    # UnionCollection, that will be executed on one or more 
    # of the member sets. Given the prior definition calling
    #
    #   union.find(:all, :conditions => "id <= 1 OR id >= 20")
    #
    # would return an array containing all the records from set 0
    # and set 2 (set 1 would be implicity excluded by the <tt>:conditions</tt>),
    #
    #   union.find_by_name('george')
    #
    # would return a single entry fetched from set 2 if george's id was >= 20,
    # 
    #   union.find(30)
    # 
    # would retrieve the record from set 2 with id == 30, and
    # 
    #   union.find(9)
    # 
    # would throw an #ActiveRecord::RecordNotFound exception because that id 
    # is specifically excluded from the union's member sets.
    # 
    # UnionCollection operates according to the following rules:
    #
    # * <tt>find :first</tt> - will search the sets in order and return the 
    #   first record that matches the find criteria.
    # * <tt>find :all</tt> - will search the sets, returning a 
    #   UnionCollection containing the all matching results. This UnionCollection
    #   can, of course, be searched further
    # * <tt>find(ids)</tt> - will look through all member sets in search
    #   of records with the given ids. #ActiveRecord::RecordNotFound will 
    #   be raised unless all the IDs are located.
    # * <tt>find_by_*</tt> - works as expected, behaving like <tt>find :first</tt>
    # * <tt>find_all_by_*</tt> - works as expected like <tt>find :all</tt>
    #
    class UnionCollection
      
      # UnionCollection should be initialized with a list of ActiveRecord collections
      #
      #   union = Zetetic::Acts::UnionCollection.new(
      #     Person.find(:all, :conditions => "id <= 1"),      # dynamic find set
      #     Person.managers                                   # an model association 
      #   )
      #
      def initialize(*sets)
        @sets = sets || []
        @sets.compact!     # remove nil elements
      end
      
      # Emulates the ActiveRecord::base.find method. 
      # Accepts all the same arguments and options
      #
      #   union.find(:first, :conditions => ["name = ?", "George"])
      #
      def find(*args)
        case args.first
          when :first then find_initial(:find, *args)
          when :all   then find_all(:find, *args)
          else             find_from_ids(:find, *args)
        end
      end
  
      def to_a
        load_sets
        @arr
      end
      
      private
      
      def load_sets
        @arr = []
        @sets.each{|set| @arr.concat set unless set.nil?} unless @sets.nil?
        @arr.uniq!
      end
      
      # start by passing the find to set 0. If no results are returned
      # pass the find on to set 1, and so on.
      def find_initial(method_id, *args)
        # conditions get anded together on subequent runs in this scope
        # by ActiveRecord. We'lls separate the conditions out, save a copy of the initial
        # state, and pass it to subsequent runs
        conditions = args[1][:conditions] if args.size > 1 and args[1].kind_of?(Hash)
        
        # this iteration is a great opportunity for future optimization - with
        # find initial there is no need to continue processing once we find
        # a match
        results = @sets.collect { |set| 
          args[1][:conditions] = conditions unless conditions.nil?
          set.empty? ? nil : set.send(method_id, *args)
        }.compact
        results.size > 0 ? results[0] : nil
      end
      
      def find_all(method_id, *args)
        # create a new UnionCollection with new member sets containing the 
        # results of the find accross the current member sets
        UnionCollection.new(*@sets.collect{|set| set.empty? ? nil : set.send(method_id, *Marshal::load(Marshal.dump(args))) })
      end
      
      # Invokes method against set1, catching ActiveRecord::RecordNotFound. if exception
      # is raised try the method execution against set2
      def find_from_ids(method_id, *args)
        res = []
        
        # another good target for future optimization - if only
        # one id is presented for the search there is no need to proxy
        # the call out to ever set - we can stop when we hit a match
        args.each do |id|
          @sets.each do |set|
            begin
              res << set.send(method_id, id) unless set.empty?
            rescue ActiveRecord::RecordNotFound
              # rethrow later
            end
          end
        end 
        
        res.uniq!
        if args.uniq.size != res.size
          #FIXME
          raise ActiveRecord::RecordNotFound.new "Couldn't find all records with IDs (#{args.join ','})"
        end
        args.size == 1 ? res[0] : res
      end
      
      # Handle find_by convienince methods
      def method_missing(method_id, *args, &block)
        if method_id.to_s =~ /^find_all_by/
          find_all method_id, *args, &block
        elsif method_id.to_s =~ /^find_by/
          find_initial method_id, *args, &block
        else
          load_sets
          @arr.send method_id, *args, &block
        end
      end
    end
    
    module Network #:nodoc:
      def self.included(base)
        base.extend ClassMethods
      end
  
      module ClassMethods
        # = acts_as_network
        # ActsAsNetork expects a few things to be present before it is
        # called. Namely, you need to establish the existance of either
        # 1. a HABTM join table; or
        # 2. an intermediate Join model
        # 
        # == HABTM
        #
        # In the first case, +acts_as_network+ will assume that your HABTM table is named
        # in a self-referential manner based on the model name. i.e. if your model is called
        # +Person+ it will assume the HABTM join table is called +people_people+.
        # It will also default the +foreign_key+ column to be named after the model: +person_id+. 
        # The default +association_foreign_key+ column will be the +foreign_key+ name with +_target+
        # appended.
        #
        #   acts_as_network :friends
        #
        # You can override any of these options in your call to +acts_as_network+. The
        # following will use a join table named +friends+ with a foreign key of +person_id+
        # and an association foreign key of +friend_id+
        #
        #   acts_as_network :friends, :join_table => :friends, :foreign_key => 'person_id', :association_foreign_key => 'friend_id'
        #
        # == Join Model
        #
        # In the second case +acts_as_network+ will need to be told which model to use to perform the join - this is 
        # accomplished by passing a symbol for the join model to the <tt>:through</tt> option. So, with a join model called invites
        # use:
        #
        #   acts_as_network :friends, :through => :invites
        #
        # The same assumptions are made relative to the foreign_key and association_foreign_key columns, which can be overriden using
        # the same options. It may be useful to include <tt>:conditions</tt> as well depending on the specific requirements of the 
        # join model. The following will create a network relation using a join model named +Invite+ with a foreign_key of 
        # +person_id+, an association_foreign_key of +friend_id+, where the Invite's +is_accepted+ field
        # is true.
        #
        #   acts_as_network :friends, :through => :invites, :foreign_key => 'person_id', 
        #                   :association_foreign_key => 'friend_id', :conditions => "is_accepted = 't'"
        #
        # The valid configuration options that can be passed to +acts_as_network+ follow:
        #
        # * <tt>:through</tt> - class to use for has_many :through relationship. If omitted acts_as_network 
        #   will fall back on a HABTM relation
        # * <tt>:join_table</tt> - when using a simple HABTM relation, this allows you to override the 
        #   name of the join table. Defaults to <tt>model_model</tt> format, i.e. people_people
        # * <tt>:foreign_key</tt> - name of the foreign key for the origin side of relation - 
        #   i.e. person_id.
        # * <tt>:association_foreign_key</tt> - name of the foreign key for the target side, 
        #   i.e. person_id_target. Defaults to the same value as +foreign_key+ with a <tt>_target</tt> suffix
        # * <tt>:conditions</tt> - optional, standard ActiveRecord SQL contition clause
        #
        def acts_as_network(relationship, options = {})
          configuration = { 
            :foreign_key => name.foreign_key, 
            :association_foreign_key => "#{name.foreign_key}_target", 
            :join_table => "#{name.tableize}_#{name.tableize}"
          }
          configuration.update(options) if options.is_a?(Hash)
      
          if configuration[:through].nil?
            has_and_belongs_to_many "#{relationship}_out".to_sym, :class_name => name,  
              :foreign_key => configuration[:foreign_key], :association_foreign_key => configuration[:association_foreign_key],
              :join_table => configuration[:join_table], :conditions => configuration[:conditions]
          
            has_and_belongs_to_many "#{relationship}_in".to_sym, :class_name => name,  
              :foreign_key => configuration[:association_foreign_key], :association_foreign_key => configuration[:foreign_key],
              :join_table => configuration[:join_table], :conditions => configuration[:conditions]
          
          else
            through_class = configuration[:through].to_s.classify
            through_sym = configuration[:through]
      
            # a node has many outbound realationships
            has_many "#{through_sym}_out".to_sym, :class_name => through_class, 
              :foreign_key => configuration[:foreign_key]
            has_many "#{relationship}_out".to_sym, :through => "#{through_sym}_out".to_sym, 
              :source => "#{name.tableize.singularize}_target",  :foreign_key => configuration[:foreign_key],
              :conditions => configuration[:conditions]
      
            # a node has many inbound relationships
            has_many "#{through_sym}_in".to_sym, :class_name => through_class, 
              :foreign_key => configuration[:association_foreign_key]
            has_many "#{relationship}_in".to_sym, :through => "#{through_sym}_in".to_sym, 
              :source => name.tableize.singularize, :foreign_key => configuration[:association_foreign_key],
              :conditions => configuration[:conditions]
            
            # when using a join model, define a method providing a unioned view of all the join
            # records. i.e. if People acts_as_network :contacts :through => :invites, this method
            # is defined as def invites
            class_eval <<-EOV
              acts_as_union :#{through_sym}, [ :#{through_sym}_in, :#{through_sym}_out ]
            EOV
              
          end
       
          # define the accessor method for the reciprocal network relationship view itself. 
          # i.e. if People acts_as_network :contacts, this method is defind as def contacts
          class_eval <<-EOV
            acts_as_union :#{relationship}, [ :#{relationship}_in, :#{relationship}_out ]
          EOV
        end
      end
    end
  
    module Union
      def self.included(base)
        base.extend ClassMethods
      end
      
      module ClassMethods
        # = acts_as_union
        # acts_as_union simply presents a union'ed view of one or more ActiveRecord 
        # relationships (has_many or has_and_belongs_to_many, acts_as_network, etc).
        # 
        #   class Person < ActiveRecord::Base
        #     acts_as_network :friends
        #     acts_as_network :colleagues, :through => :invites, :foreign_key => 'person_id', 
        #                     :conditions => ["is_accepted = 't'"]
        #     acts_as_union   :aquantainces, [:friends, :colleagues]
        #   end
        #
        # In this case a call to the +aquantainces+ method will return a UnionCollection on both 
        # a person's +friends+ and their +colleagues+. Likewise, finder operations will work accross 
        # the two distinct sets as if they were one. Thus, for the following code
        # 
        #   stephen = Person.find_by_name('Stephen')
        #   # search for user by login
        #   billy = stephen.aquantainces.find_by_name('Billy')
        #
        # both Stephen's +friends+ and +colleagues+ collections would be searched for someone named Billy.
        # 
        # +acts_as_union+ doesn't accept any options.
        #
        def acts_as_union(relationship, methods)
          # define the accessor method for the union.
          # i.e. if People acts_as_union :jobs, this method is defined as def jobs
          class_eval <<-EOV
            def #{relationship}
              UnionCollection.new(#{methods.collect{|m| "self.#{m.to_s}"}.join(',')})
            end
          EOV
        end
      end
    end # module Union
  end  # module Acts
end
