$:.unshift(File.dirname(__FILE__) + '/../lib')

require 'test/unit'
require File.expand_path(File.join(File.dirname(__FILE__), '../../../../config/environment.rb'))
require 'rubygems'
require 'active_record/fixtures'

config = YAML::load(IO.read( File.join(File.dirname(__FILE__),'database.yml')))

# cleanup logs and databases between test runs
#FileUtils.rm File.join(File.dirname(__FILE__), "debug.log"), :force => true
FileUtils.rm File.join(RAILS_ROOT, config['sqlite3'][:dbfile]), :force => true

ActiveRecord::Base.logger = Logger.new(File.join(File.dirname(__FILE__), "debug.log"))
ActiveRecord::Base.establish_connection(config[ENV['DB'] || 'sqlite3'])

load(File.join(File.dirname(__FILE__), "schema.rb"))

Test::Unit::TestCase.fixture_path = File.dirname(__FILE__) + "/fixtures/"
$LOAD_PATH.unshift(Test::Unit::TestCase.fixture_path)

class Test::Unit::TestCase #:nodoc:
  def create_fixtures(*table_names)
    if block_given?
      Fixtures.create_fixtures(Test::Unit::TestCase.fixture_path, table_names) { yield }
    else
      Fixtures.create_fixtures(Test::Unit::TestCase.fixture_path, table_names)
    end
  end

  # Turn off transactional fixtures if you're working with MyISAM tables in MySQL
  self.use_transactional_fixtures = true

  # Instantiated fixtures are slow, but give you @david where you otherwise would need people(:david)
  self.use_instantiated_fixtures  = false
  
  # Instantiated fixtures are slow, but give you @david where you otherwise would need people(:david)
  
end