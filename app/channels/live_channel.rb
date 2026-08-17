require "uri"

# The live session. One WebSocket connection is handled by one long-lived fiber, and
# this channel runs inside it: `subscribed` and every `receive` execute in that same
# fiber. Anything stored in `Fiber[...]` here therefore persists for the lifetime of
# the connection — which is what makes the components stateful. A rendered component
# is kept in `Fiber[:live_components]` and can hold transient UI state across events,
# with no id encoding and no database reload to reconstruct it.
class LiveChannel < Rage::Cable::Channel
  def subscribed
    # A closure over THIS connection's `transmit`. Any component rendered in this
    # fiber can push an update straight to this client via `Fiber[:live_update].call`.
    Fiber[:live_update] = ->(payload) { transmit(payload) }
    Fiber[:live_components] = {}
  end

  # Single client -> server entrypoint. `type` distinguishes a page navigation from an
  # event dispatched to a specific live component.
  def receive(data)
    case data["type"]
    when "navigate" then navigate(data)
    when "event"    then handle_event(data)
    end
  end

  private

  # Render a root component (the "page") into this connection. Rendering a new root
  # unmounts the previous page's components — we simply drop the old registry, and the
  # fresh render repopulates it.
  def navigate(data)
    Fiber[:live_components].clear

    app = Rage.with_middlewares(Rage::Application.new(Rage.__router), Rage.config.cable.middlewares)
    env = parse_request(data)
    _, response_headers, response_body = app.call(env)

    if location_url = response_headers["location"]
      transmit(action: "navigate", url: location_url)
    else
      transmit(action: "update", html: response_body[0])
    end
  end

  # Dispatch an event to the live component that produced the clicked element. The
  # component is still in memory with all of its state, so we just look it up and call
  # the requested method; the method pushes any resulting update itself (via #replace).
  def handle_event(data)
    component = Fiber[:live_components][data["id"]]
    return unless component

    event = data["event"].to_sym
    # Only public methods defined directly on the component are callable (RPC-style).
    allowed = component.class.public_instance_methods(false) - [:view_template]
    return unless allowed.include?(event)

    # TODO: batch responses
    component.public_send(event)
  end

  # Build the Rack env hash representing the request
  def parse_request(data)
    env = __connection.env.dup
    env["rack.upgrade?"] = env["rack.upgrade"] = env["rage.request_id"] = nil

    env["PATH_INFO"] = data["url"]
    env["REQUEST_METHOD"] = data["method"] || "GET"
    env["QUERY_STRING"] = data["query"] || ""

    if (body = data["body"])
      env["rack.input"] = StringIO.new(body)
      env["IODINE_HAS_BODY"] = true
      env["CONTENT_TYPE"] = "application/json"
    end

    env
  end
end
