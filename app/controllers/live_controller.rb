# Handles the SSE connection and incoming client events.
class LiveController < ApplicationController
  # Opens a persistent SSE connection on the "live" channel.
  # Every connected browser tab will receive broadcasts sent to this channel.
  def index
    render sse: Rage::SSE.stream("live")
  end
end
