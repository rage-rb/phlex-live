# Subscribe a live component to model changes. Hides the Rage::Signal wiring so that
# a component can track a model with a single call:
#
#   @article = live(article)                    # auto-reload + re-render
#   @article = live(article) { |a| notify(a) }  # …with a side-effect block
#
# On a dead (HTTP) render `live` is a no-op and returns the model as-is, so the same
# component code works for both the initial page load and the WebSocket session.
module LiveTracking
  # Wrap `model` in a delegator that stays current: when another connection broadcasts
  # a change, the delegator swaps in a freshly loaded instance (via GlobalID), runs the
  # optional block, and re-renders this component — all without the caller touching
  # Rage::Signal directly. The subscription is registered for cleanup so it is torn
  # down on navigation or disconnect (see LiveChannel#cleanup_live_components).
  def live(model, &block)
    unless model.is_a?(ActiveRecord::Base)
      raise ArgumentError, "should be an Active Record model"
    end

    return model unless live?

    wrapped = SimpleDelegator.new(model)

    # `self` (the component instance) is passed as the subscriber key so that
    # Rage::Signal.off can target this exact subscription during cleanup.
    Rage::Signal.on(model, self) do |gid|
      new_model = GlobalID::Locator.locate(gid)
      wrapped.__setobj__(new_model)
      block&.call(new_model)
      replace
    end

    Fiber[:live_cleanup] << -> { Rage::Signal.off(model, self) }

    wrapped
  end

  # Emit a change notification for `object`, encoding its identity as a GlobalID so
  # that subscribers can locate a fresh copy from the database.
  def self.broadcast(object)
    Rage::Signal.emit(object, object.to_global_id(app: "live").to_s)
  end

  # Whether this render is happening inside a live WebSocket connection. Components
  # can use this to skip expensive setup (subscriptions, cleanup hooks) during the
  # initial dead render that serves the first HTTP response.
  def live?
    !!Fiber[:live_update]
  end
end
