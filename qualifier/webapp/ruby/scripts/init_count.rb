require 'dalli'
require 'mysql2-cs-bind'

dc = Dalli::Client.new('localhost:11212')
total = mysql.query("SELECT count(id) AS c FROM memos WHERE is_private=0").first["c"]
dc.set('total', total)
