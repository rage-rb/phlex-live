# Subscribe a live component to model changes across connections. Wraps `Rage::PubSub`
# so that a component can track a model with a single call:
#
#   @article = stream(article)                    # auto-reload + re-render
#   @article = stream(article) { |a| notify(a) }  # …with a side-effect block
#
# On a dead (HTTP) render `stream` is a no-op and returns the model as-is, so the same
# component code works for both the initial page load and the WebSocket session.
#
# When a message arrives via `Rage::PubSub`, a new fiber is scheduled to handle the
# update. The connection's `Fiber[:live_state]` is reconstructed in that fiber so
# that the component can and push updates to the client.
module ModelStream
  # Wrap `model` in a delegator that stays current: when another connection publishes
  # a change, the delegator swaps in a freshly loaded instance (via GlobalID), runs the
  # optional block, and re-renders this component. The subscription is registered for
  # cleanup so it is torn down on navigation or disconnect (see
  # LiveChannel#cleanup_live_components).
  def stream(model, &block)
    unless model.is_a?(ActiveRecord::Base)
      raise ArgumentError, "should be an Active Record model"
    end

    live_state = Fiber[:live_state]
    return model unless live_state

    wrapped = SimpleDelegator.new(model)

    Rage::PubSub.subscribe(topic: model, subscription_id: self) do |gid|
      Fiber.schedule do
        Fiber[:live_state] = live_state

        new_model = begin
          GlobalID::Locator.locate(gid)
        rescue ActiveRecord::RecordNotFound
        end

        wrapped.__setobj__(new_model)
        block&.call(new_model)
        new_model.nil? ? remove : replace

      rescue => e
        Rage.logger.error("#{e.class} (#{e.message}):\n#{e.backtrace.join("\n")}")
        Rage::Errors.report(e)
      end
    end

    Fiber[:live_state][:cleanup] << -> { Rage::PubSub.unsubscribe(topic: model, subscription_id: self) }

    wrapped
  end

  # Publish a change notification for `object`, encoding its identity as a GlobalID so
  # that subscribers can locate a fresh copy from the database.
  def self.emit(object)
    Rage::PubSub.publish(object.to_global_id(app: "live").to_s, topic: object)
  end
end
