require 'sinatra/base'
require 'json'
require 'mysql2-cs-bind'
require 'digest/sha2'
require 'dalli'
require 'rack/session/dalli'
require 'erubis'
require 'tempfile'
require 'kramdown'

class Isucon3App < Sinatra::Base
  $stdout.sync = true
  use Rack::Session::Dalli, {
    :key => 'isucon_session',
    :cache => Dalli::Client.new('localhost:11212')
  }

  helpers do
    set :erb, :escape_html => true

    def dalli
      return $dalli if $dalli
      $dalli = Dalli::Client.new('localhost:11212')
      $dalli
    end

    def connection
      config = JSON.parse(IO.read(File.dirname(__FILE__) + "/../config/#{ ENV['ISUCON_ENV'] || 'local' }.json"))['database']
      return $mysql if $mysql
      $mysql = Mysql2::Client.new(
        :host => config['host'],
        :port => config['port'],
        :username => config['username'],
        :password => config['password'],
        :database => config['dbname'],
        :reconnect => true,
      )
    end

    def get_user
      #mysql = connection
      user_id = session["user_id"]
      username = session["username"]
      if user_id
        user = {
          "id" => user_id,
          "username" => username
        }
        #user = mysql.xquery("SELECT * FROM users WHERE id=?", user_id).first
        headers "Cache-Control" => "private"
      end
      return user || {}
    end

    def require_user(user)
      unless user["username"]
        redirect "/"
        halt
      end
    end

    def gen_markdown(md)
      Kramdown::Document.new(md).to_html
      #tmp = Tempfile.open("isucontemp")
      #tmp.puts(md)
      #tmp.close
      #html = `../bin/markdown #{tmp.path}`
      #tmp.unlink
      #return html
    end

    def anti_csrf
      if params["sid"] != session["token"]
        halt 400, "400 Bad Request"
      end
    end

    def url_for(path)
      scheme = request.scheme
      if (scheme == 'http' && request.port == 80 ||
          scheme == 'https' && request.port == 443)
        port = ""
      else
        port = ":#{request.port}"
      end
      base = "#{scheme}://#{request.host}#{port}#{request.script_name}"
      "#{base}#{path}"
    end
  end

  get '/' do
    mysql = connection
    user  = get_user

    # total = mysql.query("SELECT count(id) AS c FROM memos WHERE is_private=0").first["c"]
    total = dalli.get('total')
    memos = mysql.xquery("SELECT memos.id, memos.user, substring_index(memos.content, '\n', 1) AS title, memos.is_private, memos.created_at, memos.updated_at, users.username FROM memos LEFT OUTER JOIN users ON memos.user = users.id WHERE memos.is_private=0 ORDER BY memos.created_at DESC, memos.id DESC LIMIT 100 ")
    erb :index, :layout => :base, :locals => {
      :memos => memos,
      :page  => 0,
      :total => total,
      :user  => user,
    }
  end

  get '/recent/:page' do
    mysql = connection
    user  = get_user

    page  = params["page"].to_i
    # total = mysql.xquery('SELECT count(id) AS c FROM memos WHERE is_private=0').first["c"]
    total = dalli.get('total')
    memos = mysql.xquery("SELECT memos.id, memos.user, memos.content, memos.is_private, memos.created_at, memos.updated_at, users.username FROM memos LEFT OUTER JOIN users ON memos.user = users.id WHERE memos.is_private=0 ORDER BY memos.created_at DESC, memos.id DESC LIMIT 100 OFFSET #{page * 100}")
    if memos.count == 0
      halt 404, "404 Not Found"
    end
    erb :index, :layout => :base, :locals => {
      :memos => memos,
      :page  => page,
      :total => total,
      :user  => user,
    }
  end

  post '/signout' do
    user = get_user
    require_user(user)
    anti_csrf

    session.destroy
    redirect "/"
  end

  get '/signin' do
    user = get_user
    erb :signin, :layout => :base, :locals => {
      :user => user,
    }
  end

  post '/signin' do
    mysql = connection

    username = params[:username]
    password = params[:password]
    user = mysql.xquery('SELECT id, username, password, salt FROM users WHERE username=?', username).first
    if user && user["password"] == Digest::SHA256.hexdigest(user["salt"] + password)
      session.clear
      session["user_id"] = user["id"]
      session["username"] = user["username"]
      session["token"] = Digest::SHA256.hexdigest(Random.new.rand.to_s)
      mysql.xquery("UPDATE users SET last_access=now() WHERE id=?", user["id"])
      redirect "/mypage"
    else
      erb :signin, :layout => :base, :locals => {
        :user => {},
      }
    end
  end

  get '/mypage' do
    mysql = connection
    user  = get_user
    require_user(user)

    memos = mysql.xquery("SELECT id, substring_index(content, '\n', 1) AS title, is_private, created_at, updated_at FROM memos WHERE user=? ORDER BY created_at DESC", user["id"])
    erb :mypage, :layout => :base, :locals => {
      :user  => user,
      :memos => memos,
    }
  end

  get '/memo/:memo_id' do
    mysql = connection
    user  = get_user

    memo = mysql.xquery('SELECT memos.id, memos.user, memos.content, memos.is_private, memos.created_at, memos.updated_at, users.username FROM memos LEFT OUTER JOIN users ON memos.user = users.id WHERE memos.id=?', params[:memo_id]).first
    unless memo
      halt 404, "404 Not Found"
    end
    if memo["is_private"] == 1
      if user["id"] != memo["user"]
        halt 404, "404 Not Found"
      end
    end
    # memo["username"] = mysql.xquery('SELECT username FROM users WHERE id=?', memo["user"]).first["username"]
    memo["content_html"] = gen_markdown(memo["content"])
    if user["id"] == memo["user"]
      cond = ""
    else
      cond = "AND is_private=0"
    end
    memos = []
    older = nil
    newer = nil
    results = mysql.xquery("SELECT id FROM memos WHERE user=? #{cond} ORDER BY created_at", memo["user"])
    results.each do |m|
      memos.push(m)
    end
    0.upto(memos.count - 1).each do |i|
      if memos[i]["id"] == memo["id"]
        older = memos[i - 1] if i > 0
        newer = memos[i + 1] if i < memos.count
      end
    end
    erb :memo, :layout => :base, :locals => {
      :user  => user,
      :memo  => memo,
      :older => older,
      :newer => newer,
    }
  end

  post '/memo' do
    mysql = connection
    user  = get_user
    require_user(user)
    anti_csrf

    mysql.xquery(
      'INSERT INTO memos (user, content, is_private, created_at) VALUES (?, ?, ?, ?)',
      user["id"],
      params["content"],
      params["is_private"].to_i,
      Time.now,
    )
    memo_id = mysql.last_id
    if params["is_private"].to_i == 0
      total = dalli.get('total')
      dalli.set('total', total+1)
    end

    redirect "/memo/#{memo_id}"
  end

  run! if app_file == $0
end
