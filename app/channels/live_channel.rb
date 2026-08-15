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
    method, path, params = parse_request(data)

    component, url = dispatch(method, path, params)
    return unless component

    Fiber[:live_components] = {}
    Fiber[:live_counter] = 0

    transmit(action: "update", html: component.call, url: url)
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

    component.public_send(event)
  end

  # Maps a request to a [root_component, canonical_url] pair. Mutating verbs perform
  # their side effect and then resolve to the page the user should land on. `url` is
  # nil when we re-render in place (e.g. a form with validation errors), so the client
  # leaves the address bar untouched.
  #
  # This mirrors ArticlesController, which still serves the initial JS-less page load.
  # A fuller implementation would share a single router between HTTP and the socket.
  def dispatch(method, path, params)
    case
    when method == "GET" && (path == "/" || path == "/articles")
      [Articles::Index.new(articles: Article.order(id: :desc)), path]
    when method == "GET" && path == "/articles/new"
      [Articles::Form.new(article: Article.new), path]
    when method == "GET" && (id = path[%r{\A/articles/(\d+)/edit\z}, 1])
      [Articles::Form.new(article: Article.find(id)), path]
    when method == "GET" && (id = path[%r{\A/articles/(\d+)\z}, 1])
      [Articles::Show.new(article: Article.find(id)), path]
    when method == "POST" && path == "/articles"
      article = Article.new(article_params(params))
      article.save ? show(article) : [Articles::Form.new(article: article), nil]
    when method == "PATCH" && (id = path[%r{\A/articles/(\d+)\z}, 1])
      article = Article.find(id)
      if article.update(article_params(params))
        show(article)
      else
        [Articles::Form.new(article: article), nil]
      end
    when method == "DELETE" && (id = path[%r{\A/articles/(\d+)\z}, 1])
      Article.find(id).destroy
      [Articles::Index.new(articles: Article.order(id: :desc)), "/articles"]
    end
  end

  def show(article)
    [Articles::Show.new(article: article), "/articles/#{article.id}"]
  end

  def article_params(params)
    { title: params["title"], body: params["body"], status: params["status"] }
  end

  # Turns a { url, method, body } message into [method, path, params], honouring the
  # Rails-style `_method` override that HTML forms use for PATCH/DELETE.
  def parse_request(data)
    uri = URI.parse(data["url"].to_s)
    params = {}
    params.merge!(URI.decode_www_form(uri.query).to_h) if uri.query

    body = data["body"]
    params.merge!(URI.decode_www_form(body).to_h) if body && !body.empty?

    method = (params.delete("_method") || data["method"] || "GET").to_s.upcase
    [method, uri.path, params]
  end
end
