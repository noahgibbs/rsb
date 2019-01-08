module BenchLib
  # Checked system - error if the command fails
  def csystem(cmd, err, debug: true, fail_ok: false, console: true)
    print "Running command: #{cmd.inspect}\n" if debug
    if console
      system(cmd, out: $stdout, err: $stderr)
    else
      out = `#{cmd}`
    end
    unless $?.success? || fail_ok
      puts "Error running command:\n#{cmd.inspect}"
      puts "Output:\n#{out}\n=====" unless console
      raise err
    end
  end

  def system_environment
    {
        "RUBY_VERSION" => RUBY_VERSION,
        "RUBY_DESCRIPTION" => RUBY_DESCRIPTION,
        "rvm current" => `rvm current 2>&1`.strip,
        "repo git sha" => `cd #{__dir__} && git rev-parse HEAD`.chomp,
        "repo status" => `cd #{__dir__} && git status`,
        #"ec2 instance id" => `wget -q -O - http://169.254.169.254/latest/meta-data/instance-id`,
        #"ec2 instance type" => `wget -q -O - http://169.254.169.254/latest/meta-data/instance-type`,
        "ab_path" => `which ab`,
        "uname" => `uname -a`,
        "dir" => Dir.pwd,
    }
  end

  class ServerEnvironment
    def initialize(server_start_cmd = "rackup", server_pre_cmd: "echo Skipping", server_kill_substring: "rackup", url: "http://localhost:3000")
      @server_start_cmd = server_start_cmd
      @server_pre_cmd = server_pre_cmd
      @server_kill_substring = server_kill_substring
      @url = url
    end

    def running_server_pids
      ps_out = `ps x`
      proc_lines = ps_out.split("\n").select { |line| line[@server_kill_substring] && !line["grep"] && !line["ab_bench"] }
      proc_lines.map { |line| line.split(" ", 2)[0].to_i }
    end

    def server_cleanup
      pids = running_server_pids
      return if pids == []
      pids.each { |pid| Process.kill "HUP", pid }
      sleep 3 # Leave time to clean up after SIGHUP
      pids = running_server_pids
      pids.each { |pid| Process.kill "KILL", pid }
    end

    def server_pre_cmd
      csystem("#{@server_pre_cmd}", "Couldn't run precommand(s) (#{@server_pre_cmd.inspect}) for server process!")
    end

    def start_server
      csystem("#{@server_start_cmd} &", "Can't run server!")
    end

    def url_available?
      system("curl #{@url}")
    end

    def ensure_url_available
      100.times do
        return true if url_available?
        sleep 0.3
      end
    end

    def with_url_available
      server_pre_cmd
      start_server
      begin
        ensure_url_available
        yield
      ensure
        server_cleanup
      end
    end
  end

  module ApacheBenchClient
    def self.installed?
      which_ab = `which ab`
      which_ab && which_ab.strip != ""
    end
  end

end
