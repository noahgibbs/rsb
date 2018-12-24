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
end
