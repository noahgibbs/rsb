if ENV['RSB_COMPACT'] && ['y', 'Y'].include?(ENV['RSB_COMPACT'][0])
  config.finisher_hook do
    GC.compact
  end
end
