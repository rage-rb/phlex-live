# phlex-live

A proof of concept for **LiveView-style reactivity in Ruby**: stateful Phlex components
that live for the length of a WebSocket connection and update themselves on the page in
real time. Built on [Phlex](https://github.com/phlex-ruby/phlex) (views as Ruby classes),
[Rage](https://github.com/rage-rb/rage) (fiber-based, native WebSockets), and
[morphlex](https://github.com/yippee-fun/morphlex) (DOM morphing).

The demo is a small article CMS. A component is the unit of both rendering and behavior —
no template files, no per-interaction controllers, no hand-written client framework:

```ruby
class Articles::Card < LiveView
  def initialize(article:)
    @article  = article
    @expanded = false          # transient UI state, kept in memory for the session
  end

  def view_template
    div(class: "card") do
      button(**live_click(:toggle_status)) { @article.status == "draft" ? "Publish" : "Unpublish" }
      button(**live_click(:toggle_details)) { @expanded ? "Show less" : "Show more" }
      # ...
    end
  end

  def toggle_status   # persistent change: writes the DB, then re-renders
    @article.update!(status: @article.status == "draft" ? "published" : "draft")
    replace
  end

  def toggle_details  # transient change: in-memory only, survives across events
    @expanded = !@expanded
    replace
  end
end
```

The component stays in memory on the server (in the connection's fiber storage) between
events, so it can hold transient state and re-render itself without any id encoding or
database reload.

## Documentation

See **[ARCHITECTURE.md](ARCHITECTURE.md)** for the motivation, what the system does, and a
full walkthrough of how it works — the fiber model, the message protocol, the four request
flows, and the current state (including what's not yet done, such as authentication).

## Run it

```sh
bundle install
bundle exec rage db:setup
bundle exec rage s          # http://localhost:3000
```
