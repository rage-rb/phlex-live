# Handles the SSE connection and incoming client events.
# GET /live — opens a persistent SSE stream so the browser receives real-time updates.
# POST /live/event — receives "live_click" events from the client and dispatches
#                    them to the appropriate component method.
class LiveController < ApplicationController
  # Opens a persistent SSE connection on the "live" channel.
  # Every connected browser tab will receive broadcasts sent to this channel.
  def index
    render sse: Rage::SSE.stream("live")
  end

  # Dispatches a client-side event (e.g. a live_click) to a server-side component method.
  #
  # The client sends a JSON body like:
  #   { "id": "Articles::Card--Article--42", "event": "toggle_status" }
  #
  # We reconstruct the component from its ID (which encodes the class and model),
  # verify the requested method is a public method defined on the component (not
  # inherited), and invoke it. The component method is responsible for mutating
  # state and broadcasting any resulting UI updates via stream operations.
  def event
    component = LiveView.reconstruct(params[:id])
    event_name = params[:event].to_sym

    # Only allow public methods defined directly on the component class (RPC-style).
    allowed = component.class.public_instance_methods(false) - [:view_template]
    unless allowed.include?(event_name)
      head 403
      return
    end

    component.public_send(event_name)
    head 204
  end
end
