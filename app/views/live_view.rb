# Base class for all live-updatable Phlex components.
#
# Provides three core capabilities:
#   1. Component identity — deterministic IDs that encode the component class and its
#      model dependencies, enabling the server to reconstruct a component instance from
#      its ID string (e.g. "Articles::Card--Article--42").
#   2. Stream operations — replace, append, prepend, remove. These render the component
#      and broadcast the resulting HTML to all connected browsers via SSE.
class LiveView < Phlex::HTML
  SEPARATOR = "--"
  STREAM = "live"

  include ServerSideHandlers

  class << self
    # Declares which constructor arguments form the component's identity.
    # Each attribute should correspond to an ActiveRecord model instance.
    #
    # Example:
    #   class Articles::Card < LiveView
    #     live_id :article   # => ID will be "Articles::Card--Article--42"
    #   end
    def live_id(*attrs)
      @live_id_attrs = attrs
    end

    def live_id_attrs
      @live_id_attrs || []
    end
  end

  # --- Stream operations ---
  # These methods render the component to HTML and broadcast the result
  # to all connected SSE clients as a "stream" event. The client-side JS
  # in LiveUpdateJs handles each action type accordingly.

  # Re-renders this component and morphs it in place on all connected clients.
  # The client finds the existing DOM element by its ID and patches it.
  def replace
    broadcast(action: "replace", html: call)
  end

  # Renders this component and appends it to a target container element.
  def append(target:)
    broadcast(action: "append", target: target, html: call)
  end

  # Renders this component and prepends it to a target container element.
  def prepend(target:)
    broadcast(action: "prepend", target: target, html: call)
  end

  # Removes this component's DOM element from all connected clients.
  # Does not re-render — only sends the element ID.
  def remove
    broadcast(action: "remove", id: live_component_id)
  end

  private

  def broadcast(payload)
    Rage::SSE.broadcast(STREAM, Rage::SSE.message(payload.to_json, event: "stream"))
  end

  # Builds a deterministic ID string for this component instance.
  # For ActiveRecord-backed attributes, encodes both the class name and record ID.
  # Example: "Articles::Card--Article--42"
  def live_component_id
    parts = [self.class.name]

    self.class.live_id_attrs.each do |attr|
      value = instance_variable_get(:"@#{attr}")

      if value.respond_to?(:id) && value.respond_to?(:class)
        parts << value.class.name << value.id.to_s
      else
        parts << value.to_s
      end
    end

    parts.join(SEPARATOR)
  end

  # Wraps the component's template in a <div> with the component's ID when
  # the component has a live_id. This wrapper div is what enables targeted
  # replace and remove operations — the client finds the element by this ID.
  def around_template(&block)
    if self.class.live_id_attrs.any?
      div(id: live_component_id) do
        super
      end
    else
      super
    end
  end
end
