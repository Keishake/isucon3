worker_processes 10
preload_app true

# ROOT
ROOT = File.expand_path(File.dirname(__FILE__) + "/..")

working_directory ROOT

listen ROOT + '/tmp/sockets/unicorn.sock', :backlog => 512
#listen 8080, :tcp_nopush => true

pid ROOT + '/tmp/pids/unicorn.pid'

timeout 120

stdout_path ROOT + '/log/unicorn.stdout.log'
stderr_path ROOT + '/log/unicorn.stderr.log'

preload_app  true
GC.respond_to?(:copy_on_write_friendly=) and GC.copy_on_write_friendly = true

before_fork do |server, worker|
#  defined?(ActiveRecord::Base) and ActiveRecord::Base.connection.disconnect!
#
#  old_pid = "#{server.config[:pid]}.oldbin"
#  if old_pid != server.pid
#    begin
#      sig = (worker.nr + 1) >= server.worker_processes ? :QUIT : :TTOU
#      Process.kill(sig, File.read(old_pid).to_i)
#    rescue Errno::ENOENT, Errno::ESRCH
#    end
#  end
#
#  sleep 1
end

after_fork do |server, worker|
  #defined?(ActiveRecord::Base) and ActiveRecord::Base.establish_connection

  ## for memcache
  #if defined?(ActiveSupport::Cache::DalliStore) && Rails.cache.is_a?(ActiveSupport::Cache::DalliStore)
  #    Rails.cache.reset
  #    ObjectSpace.each_object(ActionDispatch::Session::DalliStore) { |obj| obj.reset }
  #end
end
