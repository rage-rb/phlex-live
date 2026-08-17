# Base class for interactive, individually-updatable components ("live" components).
#
# A LiveView differs from a plain Phlex view in three ways:
#
#   1. Identity — it is wrapped in a <div> with a generated id and registered in the
#      connection's fiber-local registry (`Fiber[:live_components]`). The server can
#      therefore find this exact instance again when the client dispatches an event
#      to it. No id encoding, no database reconstruction — just a lookup.
#
#   2. State — the instance lives in fiber storage for the lifetime of the WebSocket
#      connection, so it can hold transient UI state (e.g. "expanded?") across events.
#      Navigating to a new page drops the registry, which unmounts it.
#
#   3. Reactivity — stream operations (replace/append/prepend/remove) re-render the
#      component and push the HTML to its own connection over the socket, through the
#      `Fiber[:live_update]` closure installed by LiveChannel#subscribed.
class LiveView < Phlex::HTML
  # --- Stream operations: re-render and push to THIS connection. ---

  # Re-render this component and morph it in place on the client.
  def replace
    emit(action: "replace", html: render_html)
  end

  # Render this component and append it to a target container element.
  def append(target:)
    emit(action: "append", target: target, html: render_html)
  end

  # Render this component and prepend it to a target container element.
  def prepend(target:)
    emit(action: "prepend", target: target, html: render_html)
  end

  # Remove this component's element from the client and drop it from the registry.
  def remove
    Fiber[:live_components]&.delete(@live_id)
    emit(action: "remove", id: @live_id)
  end

  # Data attributes binding a DOM event to a server-side method on this instance:
  #   button(**live_click(:toggle_status)) { "Publish" }
  # The client sends the id + method name back over the socket; LiveChannel looks the
  # instance up by id and invokes the method.
  def live_click(event_name)
    # TODO: support additional parameters
    { data_live_click: event_name.to_s, data_live_id: @live_id }
  end

  # TODO: expose connected? to allow users skip parts for dead render

  private

  # Push a payload to the current connection. `Fiber[:live_update]` closes over this
  # connection's `transmit` and only exists inside the WebSocket fiber.
  def emit(payload)
    Fiber[:live_update]&.call(payload)
  end

  # Phlex refuses to render an instance more than once. Because a live component
  # persists and re-renders on every update, we clear the render guard before each
  # pass while keeping all other state (@article, @expanded, ...) intact.
  def render_html
    @_state = nil
    call
  end

  # Wrap each live component in an identifiable element and register the instance so
  # that later events can be routed back to it. Runs on every render; the id is
  # assigned once and preserved, so re-renders keep targeting the same element.
  def around_template
    @live_id ||= "el-#{object_id}"
    (Fiber[:live_components] ||= {})[@live_id] = self
    div(id: @live_id) { super }
  end
end
