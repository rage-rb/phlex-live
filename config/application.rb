require "bundler/setup"
require "rage"
Bundler.require(*Rage.groups)

require "active_record"
require "rage/all"

Rage.configure do
  config.middleware.use Rack::MethodOverride
  config.router.form_actions = true

  config.renderer :phlex do |component, **props|
    html = component.new(**props).call

    if request.headers["Phlex-Live"]
      Rage::SSE.broadcast("live", Rage::SSE.message(html, event: "update"))
      head 200
    else
      headers["content-type"] = "text/html"
      html
    end
  end
end

require "rage/setup"
