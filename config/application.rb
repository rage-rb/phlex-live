require "bundler/setup"
require "rage"
Bundler.require(*Rage.groups)

require "active_record"
require "rage/all"

Rage.configure do
  config.middleware.use Rack::MethodOverride
  config.router.form_actions = true

  config.renderer :phlex do |component, **props|
    headers["content-type"] = "text/html"
    component.new(**props).call
  end
end

require "rage/setup"
