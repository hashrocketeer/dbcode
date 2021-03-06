require 'dbcode'

describe 'dbcode' do
  def database_name; 'dbcode_test' end
  before(:all) do
    system "dropdb #{database_name}; createdb #{database_name}"
  end

  around do |test|
    ActiveRecord::Base.establish_connection(
      adapter: 'postgresql', database: database_name
    )
    ActiveRecord::Base.connection.transaction do
      test.call
      raise ActiveRecord::Rollback
    end
    ActiveRecord::Base.clear_all_connections!
  end

  let(:sql_file_path) do
    Pathname(__FILE__).join('../test_app/db/code').tap(&:mkpath)
  end

  before do
    sql_file_path.rmtree
    DBCode.sql_file_path = sql_file_path
    DBCode.logger.level = Logger::Severity::FATAL
  end

  def create_file path, contents
    path = Pathname path
    sql_file_path.join(path.dirname)
      .tap(&:mkpath).join("#{path.basename}.sql").write contents
  end

  def create_view_file name, contents
    create_file Pathname('views').join(name), contents
  end

  def schema_oid
    (connection.select_one(<<-SQL) or {})['oid']
      select oid from pg_catalog.pg_namespace where nspname = '#{DBCode.code_schema_name}';
    SQL
  end

  def connection
    ActiveRecord::Base.connection
  end

  specify 'new connections use new declarations of a view' do
    create_view_file 'foo', <<-SQL
      create view foo as select 1 as number
    SQL
    DBCode.prepare

    expect(connection.select_one('select number from foo')).to eq 'number' => 1
    create_view_file 'foo', <<-SQL
      create view foo as select 2 as number
    SQL
    DBCode.prepare
    expect(connection.select_one('select number from foo')).to eq 'number' => 2
  end

  specify 'concatenates files with sprockets require statements' do
    create_view_file 'foo', <<-SQL
    create view foo as select 1 as number
    SQL

    create_view_file 'bar', <<-SQL
    -- require views/foo
    create view bar as select * from foo
    SQL

    expect { DBCode.prepare }.to_not raise_error
  end

  it 'only executes when the code is updated' do
    create_view_file 'foo', <<-SQL
      create view foo as select 1 as number
    SQL

    DBCode.prepare

    expect {
      DBCode.prepare
    }.to_not change { schema_oid }
  end

  specify "subsequent ddl statements work go into public schema" do
    expect(connection.schema_search_path.split(',')).to_not include 'code'
    DBCode.prepare
    connection.execute <<-SQL
    create table foos (id serial)
    SQL
    expect(connection.select_one(<<-SQL).fetch('nspname')).to eq 'public'
      select nspname
      from pg_class
      join pg_namespace on relnamespace = pg_namespace.oid
      where relname = 'foos'
    SQL
  end

  specify 'file_names is the name and the path' do
    create_file 'functions/kill_em_all', '-- hi!'
    expect(DBCode.files).to eq [name: 'functions/kill_em_all', contents: '-- hi!']
  end

  describe 'when there are pending migrations' do
    before do
      allow(ActiveRecord::Migrator).to receive(:check_pending!).and_raise(ActiveRecord::PendingMigrationError)
    end

    it 'does not reset out of date schemas' do
      DBCode.prepare
      create_view_file 'foo', <<-SQL
        create view foo as select 1 as number
      SQL
      expect { DBCode.prepare }.to_not change { schema_oid }
    end
  end

  describe 'in production mode' do
    before { DBCode.env = 'production' }
    it 'does not reset out of date schemas' do
      DBCode.prepare
      create_view_file 'foo', <<-SQL
        create view foo as select 1 as number
      SQL
      expect { DBCode.prepare }.to_not change { schema_oid }
    end
  end
end
