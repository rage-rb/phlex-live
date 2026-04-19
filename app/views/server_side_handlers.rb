module ServerSideHandlers
  def self.included(klass)
    klass.extend ClassMethods
  end

  # Returns data attributes for a clickable element that triggers a server-side
  # method on this component. The client JS intercepts clicks on elements with
  # these attributes and POSTs to /live/event.
  #
  # Usage in a template:
  #   button(**live_click(:toggle_status)) { "Toggle" }
  def live_click(event_name)
    { data_live_click: event_name.to_s, data_live_id: live_component_id }
  end

  module ClassMethods
    # Reconstructs a component instance from its serialized ID string.
    # Parses the ID to extract the component class and model references,
    # loads each model from the database, and instantiates the component.
    #
    # Example:
    #   LiveView.reconstruct("Articles::Card--Article--42")
    #   # => Articles::Card.new(article: Article.find(42))
    def reconstruct(component_id)
      parts = component_id.split(LiveView::SEPARATOR)
      component_class = Object.const_get(parts.shift)

      kwargs = {}
      component_class.live_id_attrs.each do |attr|
        model_class = Object.const_get(parts.shift)
        kwargs[attr] = model_class.find(parts.shift)
      end

      component_class.new(**kwargs)
    end
  end
end