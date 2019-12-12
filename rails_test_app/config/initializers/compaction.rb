if ENV['RSB_COMPACT'] && ['y', 'Y'].include?(ENV['RSB_COMPACT'][0])
  Rails.application.config.after_initialize do
    GC.compact
  end
end
