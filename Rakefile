require 'rake'
require 'active_record'
require 'yaml'

# Load database configuration
db_config = YAML.load_file('config/database.yml')
ActiveRecord::Base.establish_connection(db_config['development'])

# Load all migration files
Dir.glob('app/db/migrate/*.rb').each { |file| require_relative file }

namespace :db do
  desc 'Run database migrations'
  task :migrate do
    ActiveRecord::Migration.verbose = true
    ActiveRecord::MigrationContext.new('app/db/migrate', ActiveRecord::SchemaMigration).migrate
  end

  desc 'Rollback the last migration'
  task :rollback do
    ActiveRecord::Migration.verbose = true
    ActiveRecord::MigrationContext.new('app/db/migrate', ActiveRecord::SchemaMigration).rollback
  end

  desc 'Create the database'
  task :create do
    ActiveRecord::Base.connection.create_database(db_config['development']['database'])
  end

  desc 'Drop the database'
  task :drop do
    ActiveRecord::Base.connection.drop_database(db_config['development']['database'])
  end
end

desc 'Run all tasks'
task default: ['db:migrate']