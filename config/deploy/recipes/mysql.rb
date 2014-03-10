set(:environment, "production")
set(:db_host, "localhost")


namespace :db do
  namespace :mysql do
    desc <<-EOF
    |DarkRecipes| Performs a compressed database dump. \
    WARNING: This locks your tables for the duration of the mysqldump.
    Don't run it madly!
    EOF
    task :dump do
      on roles(:db, :only => { :primary => true }) do
        prepare_from_yaml
        run "mysqldump --user=#{db_user} -p --host=#{db_host} #{db_name} | bzip2 -z9 > #{db_remote_file}" do |ch, stream, out|
        ch.send_data "#{db_pass}\n" if out =~ /^Enter password:/
          puts out
        end
      end
    end

    desc "|DarkRecipes| Restores the database from the latest compressed dump"
    task :restore do
      on roles(:db, :only => { :primary => true }) do
        prepare_from_yaml
        run "bzcat #{db_remote_file} | mysql --user=#{db_user} -p --host=#{db_host} #{db_name}" do |ch, stream, out|
        ch.send_data "#{db_pass}\n" if out =~ /^Enter password:/
          puts out
        end
      end
    end

    desc "|DarkRecipes| Downloads the compressed database dump to this machine"
    task :fetch_dump do
      on roles(:db, :only => { :primary => true }) do
        prepare_from_yaml
        download db_remote_file, db_local_file, :via => :scp
      end
    end
  
    desc "|DarkRecipes| Create MySQL database and user for this environment using prompted values"
    task :setup do
      on roles(:db, :only => { :primary => true }) do
        # prepare_for_db_command

        set :db_name, "#{fetch(:application)}_#{fetch(:environment)}"
        # set(:db_admin_user) { Capistrano::CLI.ui.ask("Username with priviledged database access (to create db):") }
        # set(:db_user) { Capistrano::CLI.ui.ask("Enter #{fetch(:environment)} database username:") }
        # set(:db_pass) { Capistrano::CLI.password_prompt("Enter #{fetch(:environment)} database password:") }
        # 
        sql = <<-SQL
        CREATE DATABASE #{fetch(:db_name)}
        GRANT ALL PRIVILEGES ON #{fetch(:db_name)}.* TO #{fetch(:db_user)}@localhost IDENTIFIED BY '#{fetch(:db_pass)}'
        SQL

        ask :db_admin_user, 'root'
        ask :password, '********'
        execute "mysql -u#{fetch(:db_admin_user)} -p#{fetch(:password)} --execute=\"#{sql}\"" 
      end
    end
    
    # Sets database variables from remote database.yaml
    def prepare_from_yaml
      set(:db_file) { "#{application}-dump.sql.bz2" }
      set(:db_remote_file) { "#{shared_path}/backup/#{db_file}" }
      set(:db_local_file)  { "tmp/#{db_file}" }
      set(:db_user) { db_config[rails_env]["username"] }
      set(:db_pass) { db_config[rails_env]["password"] }
      set(:db_host) { db_config[rails_env]["host"] }
      set(:db_name) { db_config[rails_env]["database"] }
    end
      
    def db_config
      @db_config ||= fetch_db_config
    end

    def fetch_db_config
      require 'yaml'
      file = capture "cat #{shared_path}/config/database.yml"
      db_config = YAML.load(file)
    end
  end
  
  desc "|DarkRecipes| Create database.yml in shared path with settings for current stage and test env"
  task :create_yaml do
    # set(:db_user) { Capistrano::CLI.ui.ask "Enter #{fetch(:environment)} database username:" }
    # set(:db_pass) { Capistrano::CLI.password_prompt "Enter #{fetch(:environment)} database password:" }

    db_config = ERB.new <<-EOF
    base: &base
      adapter: mysql
      encoding: utf8
      reconnect: false
      pool: 5
      username: #{fetch(:db_user)}
      password: #{fetch(:db_pass)}
      host: localhost

    #{fetch(:environment)}:
      database: #{fetch(:application)}_#{fetch(:environment)}
      <<: *base

    test:
      database: #{fetch(:application)}_test
      <<: *base
    EOF

    put db_config.result, "#{shared_path}/config/database.yml"
    puts "create database.yml"
  end
end
  
# def prepare_for_db_command
#   set :db_name, "#{fetch(:application)}_#{fetch(:environment)}"
#   set(:db_admin_user) { Capistrano::CLI.ui.ask("Username with priviledged database access (to create db):") }
#   set(:db_user) { Capistrano::CLI.ui.ask("Enter #{fetch(:environment)} database username:") }
#   set(:db_pass) { Capistrano::CLI.password_prompt("Enter #{fetch(:environment)} database password:") }
# end

desc "Populates the database with seed data"
task :seed do
  Capistrano::CLI.ui.say "Populating the database..."
  run "cd #{current_path}; bundle exec rake RAILS_ENV=#{variables[:rails_env]} db:seed"
end

# after "seed", "copy_seed_tables"




