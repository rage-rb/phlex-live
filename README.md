# phlex-live

Live Phlex components powered by Rage SSE. A proof of concept exploring LiveView-like reactivity for Ruby — event handlers and rendering logic in the same class, connected to the browser via Server-Sent Events.

## What this is

A small CMS app demonstrating Phlex components that update themselves on the page in real time:

```ruby
class Articles::Card < LiveView
  live_id :article

  def view_template
    div(class: "card") do
      span(class: "badge") { @article.status }
      button(**live_click(:toggle_status)) { "Publish" }
    end
  end

  def toggle_status
    new_status = @article.status == "draft" ? "published" : "draft"
    @article.update!(status: new_status)
    replace  # re-render, push to client via SSE, morph the DOM
  end
end
```

No template files, no separate controller, no JS written. The component is the unit of both rendering and behavior.

## How it works

1. Client establishes a persistent SSE connection to the server
2. User interactions (clicks, form submissions) are intercepted by a small client-side script and sent as events
3. The server reconstructs the component from its ID, calls the handler method, re-renders, and broadcasts the updated HTML via SSE
4. [morphlex](https://github.com/yippee-fun/morphlex) patches the DOM

## What's implemented

- **`LiveView` base class** — extends `Phlex::HTML`, wraps components in identifiable elements, reconstructs instances from their ID
- **`live_id`** — declarative component identity (e.g. `live_id :article` → `Articles::Card--Article--123`)
- **Stream operations** — `replace`, `append(target:)`, `prepend(target:)`, `remove`
- **Server-side event handlers** — `live_click(:method_name)` binds UI events to component methods
- **SPA-like navigation** — link clicks and form submissions morphed into the page without full reloads

## Stack

- [Rage](https://github.com/rage-rb/rage) — fiber-based Ruby framework with native SSE support
- [Phlex](https://github.com/phlex-ruby/phlex) — Ruby component framework
- [morphlex](https://github.com/yippee-fun/morphlex) — DOM morphing library
- SQLite3 + ActiveRecord

## Setup

```sh
bundle install
bundle exec rage db:setup
bundle exec rage s
```
