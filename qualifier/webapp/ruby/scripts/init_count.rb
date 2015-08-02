require 'dalli'
require 'json'
require 'mysql2-cs-bind'

dc = Dalli::Client.new('localhost:11212')
config = JSON.parse(IO.read(File.dirname(__FILE__) + "/../../config/#{ ENV['ISUCON_ENV'] || 'local' }.json"))['database']
mysql = Mysql2::Client.new(
        :host => config['host'],
        :port => config['port'],
        :username => config['username'],
        :password => config['password'],
        :database => config['dbname'],
        :reconnect => true,
      )
total = mysql.query("SELECT count(id) AS c FROM memos WHERE is_private=0").first["c"]
dc.set('total', total)
