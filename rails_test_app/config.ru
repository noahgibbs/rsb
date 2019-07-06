# This file is used by Rack-based servers to start the application.

require ::File.expand_path('../config/environment', __FILE__)

if Rails.env.profile?
  use Rack::RubyProf,
    :path => File.expand_path(File.join(__dir__, 'log/profile')),
    :prefix => "rsb-rails-#{Process.pid}-",
    :max_requests => ENV["RSB_PROFILE_REQS"] || 10_000
end

run Rails.application
