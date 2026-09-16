# phlex-live

<img width="800" alt="demo_full_1080" src="https://github.com/user-attachments/assets/661d38e5-f7db-4579-a6f1-f3b5d94ed52a" />

A working proof of concept for **LiveView-style reactivity in Ruby**: stateful Phlex components that persist for the life of a WebSocket connection and update themselves in place.

```ruby
class Articles::Card < LiveView
  def initialize(article:)
    @article  = article
    @expanded = false
  end

  def view_template
    div(class: "card") do
      button(**live_click(:toggle_status)) { @article.status == "draft" ? "Publish" : "Unpublish" }
      button(**live_click(:toggle_details)) { @expanded ? "Show less" : "Show more" }
      p { @expanded ? @article.body : @article.body.truncate(150) }
    end
  end

  def toggle_status   # persistent: writes the DB
    @article.update!(status: @article.status == "draft" ? "published" : "draft")
  end

  def toggle_details  # transient: in-memory only
    @expanded = !@expanded
  end
end
```

The component lives in memory on the server for the length of the WebSocket connection. Click "Show more" and `@expanded` flips to `true`; click again and it flips back. No database column, no URL param, no JavaScript — just an instance variable that survives across events because the object itself survives. `toggle_status` writes to the database; `toggle_details` doesn't. Both re-render the component automatically.

## Cross-connection updates

When one user publishes an article, every other user viewing that article should see it update. The `stream` helper subscribes a component to model changes via pub/sub:

```ruby
class Articles::Card < LiveView
  def initialize(article:)
    @article = stream(article) do |article|
      Notification.new(message: "#{article.title} is now #{article.status}").append(target: "main")
    end
    @expanded = false
  end
  # ...
end
```

When `Article` calls `ModelStream.emit(self)` in an `after_commit`, every subscribed component reloads the model and re-renders — each honoring its own `@expanded` state. Subscriptions are cleaned up automatically on navigation and disconnect.

## How it works

```
Browser                                      Server
┌───────────────────────────┐                ┌─────────────────────────────────────┐
│ 1. GET /articles          │ ── HTTP ─────► │ ArticlesController#index            │
│    (first paint)          │ ◄───────────── │   → server-rendered HTML            │
│                           │                │                                     │
│ 2. WebSocket /live        │ ═══ open ════► │ LiveChannel#subscribed              │
│                           │                │   Fiber[:live_state] = {…}          │
│ 3. navigate /articles     │ ═══ msg ═════► │ navigate → router → controller      │
│    (hydrate/link/form)    │                │   components self-register          │
│                           │ ◄══ msg ══════ │   {action:"update", html, url}      │
│    morph document         │                │                                     │
│                           │                │                                     │
│ 4. click Publish          │ ═══ msg ═════► │ event → component.toggle_status     │
│    {id:"el-42",           │                │   → auto-replace                    │
│     event:"toggle_status"}│ ◄══ msg ══════ │   {action:"replace", html}          │
│    morph #el-42           │                │                                     │
└───────────────────────────┘                └─────────────────────────────────────┘
```

The first page load is ordinary server-rendered HTML. Then the client opens a WebSocket connection — one per tab, one long-lived fiber on the server. Navigation (links, forms, back/forward) is delegated to the same controllers that serve HTTP, running in the connection's fiber so rendered components register themselves in fiber storage. Events are dispatched to component methods; components re-render and push HTML to the client, which morphs it into the page.

Built on:
- **[Phlex](https://github.com/phlex-ruby/phlex)** — views as Ruby classes
- **[Rage](https://github.com/rage-rb/rage)** — fiber-based framework with native WebSockets
- **[morphlex](https://github.com/yippee-fun/morphlex)** — DOM morphing

## Run it

```sh
bundle install
bundle exec rage db:setup
bundle exec rage s          # http://localhost:3000
```

Open two browser tabs. Each maintains its own live session with its own `@expanded` states. Publish/unpublish persists to the database and propagates to other tabs; "Show more/less" is local to each tab.

## Documentation

See **[ARCHITECTURE.md](ARCHITECTURE.md)** for the full deep dive: the fiber model, the message protocol, how navigation is delegated to controllers, how `stream` works, security considerations, and current limitations.
