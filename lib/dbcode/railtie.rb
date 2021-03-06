module DBCode
  class Railtie < Rails::Railtie
    initializer "dbcode.setup" do |app|
      DBCode.sql_file_path = app.root.join 'db/code'
      DBCode.logger = Rails.logger
      DBCode.env = Rails.env
      config.watchable_dirs[DBCode.sql_file_path.to_s] = ['sql']
    end

    config.to_prepare &DBCode.method(:prepare)

    rake_tasks do
      load 'dbcode/tasks/db_code.rake'
    end
  end
end
