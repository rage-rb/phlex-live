# phlex-live — System Architecture

A proof of concept for **LiveView-style reactivity in Ruby**, built from:

- **[Phlex](https://github.com/phlex-ruby/phlex)** — views are plain Ruby classes.
- **[Rage](https://github.com/rage-rb/rage)** — a Rails-compatible fiber-based framework with native
  WebSockets (`Rage::Cable`).
- **[morphlex](https://github.com/yippee-fun/morphlex)** — DOM morphing in the browser.

The demo is a small article CMS. Once the page loads, a single WebSocket per tab carries
everything: navigation is dispatched to ordinary **Rage controllers**, and interactive
updates are dispatched to **Phlex component methods** — both over the same socket, with the
server rendering HTML and the browser morphing it into the page. No template files, no
hand-written client framework.

---

## Motivation

An earlier version of this project drove the UI over **Server-Sent Events (SSE)**. It
worked, but it had two properties we wanted to change:

1. **Statelessness forced identity into the DOM.** With SSE there is no durable
   server-side handle on a component. To route a click back to "the card for article
   42," the component encoded its identity into a `live_id` string (`Articles::Card--Article--42`),
   which the server parsed and used to *rebuild* the component from the database on every
   interaction. It was hard to reason about, and every event meant a fresh
   reload from the DB.

2. **No place to keep transient UI state.** Because the component was reconstructed each
   time, there was nowhere to hold ephemeral, non-persisted state (is this card expanded?
   which tab is active?) without writing it to the database or the URL. That kept the
   system in the "Hotwire" category (server renders, client swaps) rather than the
   "LiveView" category (a live, stateful component per connection).

Switching the transport to a **WebSocket** changes the model fundamentally:

- **A connection is a durable thing.** It maps to one long-lived server-side fiber, which
  gives us a natural home for per-session state — and a natural place for **authentication
  and authorization** to live (authenticate once, at connect time, instead of on every
  request).
- **Components can simply *stay in memory*.** A rendered component is kept in the
  connection's fiber storage and re-used across events. This **removes `live_id`
  entirely** (identity is just a registry key now) and lets components **hold transient UI
  state**.

---

## What it does

A CMS admin for articles (list / view / create / edit / delete). Concretely:

- **SPA-style navigation** over the WebSocket — links, forms, and back/forward buttons all
  update the page by morphing, without full reloads.
- **Live components** that update themselves in place. Each article card can:
  - **Publish / Unpublish** — a *persistent* change (writes the DB), then re-renders.
  - **Show more / Show less** — a *transient* change (`@expanded`, in memory only), then
    re-renders. This is the capability the stateful model unlocks.
- **Progressive enhancement** — the first page load is ordinary server-rendered HTML from
  a normal controller, so direct URLs and a JS-disabled browser still work.

---

## How it works

### The big picture

```
  Browser                                      Rage server
  ┌───────────────────────────┐                ┌─────────────────────────────────────┐
  │ 1. GET /articles          │ ─ HTTP ──────► │ router → ArticlesController#index    │
  │    (first paint)          │ ◄───────────── │ → dead-rendered HTML                │
  │                           │     HTML       │                                     │
  │ 2. new WebSocket(         │                │                                     │
  │      "/live/live")        │ ═ WS open ════►│ LiveChannel#subscribed              │
  │                           │                │   Fiber[:live_state] = {…}          │  one
  │ 3. {type:"navigate",      │ ═ WS msg ═════►│ receive → navigate                  │  fiber
  │     url:"/articles"}      │                │   build a Rack env from the message │  per
  │    (hydrate / link /      │                │   app.call(env) ── in THIS fiber ──┐│  conn
  │     form / back-fwd)      │                │     router → ArticlesController     ││
  │                           │                │       renders Phlex; LiveView      ││
  │                           │                │       children self-register    ◄──┘│
  │                           │ ◄═ WS msg ═════│   {action:"update", html, url}      │
  │    morph document         │                │   live_state[:components] =          │
  │                           │                │     {"el-8420"=>#<Card…>, …}         │
  │ 4. click Publish          │ ═ WS msg ═════►│ receive → event                     │
  │    {type:"event",         │                │   comp = registry["el-8420"]        │
  │     id:"el-8420",         │                │   comp.handle_event → auto-replace  │
  │     event:"toggle_status"}│ ◄═ WS msg ═════│   {action:"replace", html}          │
  │    morph #el-8420         │                │                                     │
  └───────────────────────────┘                └─────────────────────────────────────┘
```

### Where the logic lives

The design splits cleanly along one line — *is this a page transition, or an in-place
update?*

- **Controllers own routing, business logic, and page rendering.** The `resources
  :articles` routes and `ArticlesController` are completely ordinary. They serve the
  initial HTTP load *and* every socket navigation — the **same code**, no duplication.
- **`LiveView` Phlex components own transient UI state** (and any behaviour attached to it,
  via event-handler methods). They persist in the connection's fiber storage between
  events.
- **The WebSocket connection multiplexes both.** After the first paint, the client sends
  every interaction over the one socket; the framework routes `navigate` messages to
  controllers and `event` messages to component methods.

### Why Rage: one connection = one persistent fiber

The whole design rests on a property of `Rage::Cable`: **each WebSocket connection is
serviced by a single, long-lived fiber.** `subscribed` and *every* subsequent `receive`
run in that same fiber. That means anything stored in Ruby's fiber-local storage
(`Fiber[...]`) during `subscribed` is still there on the next message.

Fibers make this cheap: a mostly-idle connection is a parked fiber, not a parked thread,
and blocking ActiveRecord calls yield to the scheduler instead of pinning a thread. So
"keep a live object per open tab" scales.

All connection state lives in `Fiber[:live_state]`, a hash with these keys:

| Key          | What it is                                                                    |
|--------------|-------------------------------------------------------------------------------|
| `:update`    | A closure over this connection's `transmit` — how components push.            |
| `:components`| Registry: `{ "el-8420" => <component>, … }` — the mounted components.         |
| `:cleanup`   | Array of teardown lambdas (e.g. `Rage::PubSub.unsubscribe` calls) run on navigation and disconnect. |

This is also what lets navigation delegate to a controller *and* have the rendered
components register themselves here (see below): the controller runs **in this same
fiber**, so `Fiber[:live_state][:components]` is the one the connection will read on the next event.

### The building blocks

| Piece | File | Responsibility |
|-------|------|----------------|
| **`LiveChannel`** | `app/channels/live_channel.rb` | The live session. Installs the fiber storage on `subscribe`; on `receive`, **delegates a `navigate` to the Rage app (controllers)** or delegates an `event` to the component's `handle_event`. |
| **`ArticlesController`** | `app/controllers/articles_controller.rb` | Ordinary Rage controller. Serves **both** the initial HTTP load and every socket navigation — one implementation, two entry points. |
| **`LiveView`** | `app/views/live_view.rb` | Base class for interactive components. Generates an id, registers the instance, wraps it in a `<div id>`, handles event dispatch with auto-`replace`, and provides stream ops (`replace`/`append`/`prepend`/`remove`) + `live_click`. Includes `ModelStream`. |
| **`ModelStream`** | `app/views/model_stream.rb` | The `stream` helper: subscribes a component to model changes via `Rage::PubSub`, auto-reloads via GlobalID, re-renders, and registers cleanup. Also provides `ModelStream.emit` for models. |
| **`LiveUpdateJs`** | `app/views/live_update_js.rb` | ~140 lines of dependency-light client JS: WebSocket connect/reconnect, event delegation (clicks, forms, popstate), and applying server messages via morphlex. |
| **`:phlex` renderer** | `config/application.rb` | Renders a component to HTML — used by controllers for both HTTP and socket rendering. |

`Articles::Index` and `Form` are **plain `Phlex::HTML` pages**. `Articles::Card`,
`Articles::Show`, and `Notification` are **`LiveView`s** — the distinction is simply "is
this an individually updatable, stateful fragment?"

### The message protocol

All server↔client traffic is JSON over the one socket.

**Client → server** (handled by `LiveChannel#receive`, keyed on `type`):

```jsonc
{ "type": "navigate", "url": "/articles/42", "method": "GET" }        // link / form / popstate
{ "type": "event",    "id": "el-8420", "event": "toggle_status" }     // a live_click
```

**Server → client** (via `Fiber[:live_state][:update]` → `transmit`, keyed on `action`):

```jsonc
{ "action": "update",  "html": "<!doctype…>", "url": "/articles/42" } // full-page morph
{ "action": "replace", "html": "<div id='el-8420'>…</div>" }         // targeted morph
{ "action": "navigate", "url": "/articles/42" }                     // redirect
{ "action": "append",  "target": "main", "html": "…" }
{ "action": "prepend", "target": "main", "html": "…" }
{ "action": "remove",  "id": "el-8420" }
```

### The four flows

**1. Initial load (dead render).** `GET /articles` hits `ArticlesController#index`, which
renders `Articles::Index` to HTML through the `:phlex` renderer. The page is real,
complete HTML — good for first paint, direct links, and no-JS — and it embeds the
`LiveUpdateJs` `<script>`.

**2. Hydration.** The script opens `new WebSocket("/live/live")`. `Rage::Cable` (in
`:raw_websocket_json` mode) maps that path to `LiveChannel` and runs `subscribed`, which
installs the fiber storage. The client immediately sends a `navigate` for the current URL.
The server renders that page **inside the connection fiber**, which registers each
`LiveView` child in `Fiber[:live_state][:components]`, and pushes it back as an `update`. The
client morphs it over the identical dead-rendered DOM — visually a no-op, but now the
server holds live component instances for this tab.

**3. Navigation — delegated to the Rage app.** A link click, form submit, or back/forward
sends a `navigate` message. Rather than route it itself, `LiveChannel` **reconstructs an
HTTP request and hands it to the Rage router**:

```ruby
def parse_request(data)
  # ...
  env["PATH_INFO"] = data["url"]
  env["REQUEST_METHOD"] = data["method"] || "GET"
  env["QUERY_STRING"] = data["query"] || ""
  # ...

  env
end

def navigate(data)
  # ...
  app = Rage.with_middlewares(Rage::Application.new(Rage.__router), Rage.config.cable.middlewares)
  env = parse_request(data)
  _, response_headers, response_body = app.call(env)
  # ...
end
```

Two things make this work:

- **It runs in the current fiber.** The app is wrapped in `Rage.config.cable.middlewares`,
  *not* the HTTP stack — so it deliberately omits `Rage::FiberWrapper` (which would spawn a
  new request fiber). `app.call(env)` therefore executes synchronously in this connection's
  fiber, and every `LiveView` the controller renders registers itself in *this*
  `Fiber[:live_state][:components]`.
- **Redirects become the URL.** `ArticlesController` still uses `redirect_to` after a
  mutation; the channel reads the `Location` header and returns it as the canonical `url`
  for the client to place in history.

**4. Events.** A `data-live-click` element sends an `event` message with the component id
and method name. The channel looks the instance up in the registry — **it is still in
memory, with all its state** — and delegates to `handle_event`. The method mutates state;
if it doesn't explicitly call a stream op, `replace` is called automatically after the
method returns, re-rendering and pushing the change to *this* connection.

### Identity and state without `live_id`

When a `LiveView` renders, `around_template` assigns it an id derived from the Ruby
instance itself (`el-#{object_id}`), stores the **actual instance** in
`Fiber[:live_state][:components]`, and wraps its output in `<div id="el-8420">`:

```ruby
def around_template
  @live_id ||= "el-#{object_id}"
  Fiber[:live_state][:components][@live_id] = self if Fiber[:live_state]
  div(id: @live_id) { super }
end
```

The id is tied to the instance, so it is stable for that object's lifetime and needs no
per-page counter or reset — a component keeps the same element id across every re-render,
and freshly created components (e.g. an appended one) get a fresh id automatically. The ids
from the initial dead render and the hydration render differ, which is fine: hydration
sends a whole-document `update` that morphlex reconciles by structure anyway.

Identity is now just a hash key into live objects — no string encoding, no DB round-trip
to reconstruct. And because the instance persists, it can hold transient state. `Card`
demonstrates both kinds side by side:

```ruby
def toggle_status   # persistent: writes the DB, then re-renders
  @article.update!(status: @article.status == "draft" ? "published" : "draft")
end

def toggle_details  # transient: in-memory only, survives across events
  @expanded = !@expanded
end
```

Event handlers don't need to call `replace` explicitly — `handle_event` calls it
automatically if the method didn't invoke any stream operation.

Toggling "Show more" repeatedly flips `@expanded` on the same instance across independent
events. Navigating away resets the registry, which is exactly the right unmount semantics.

### Re-rendering a component that already rendered

Phlex forbids rendering an instance twice (it raises `DoubleRenderError`). But a persisted
live component *must* re-render on every update. The single guard is the internal
`@_state` variable, so `LiveView` clears it before each pass, keeping every other ivar
intact:

```ruby
def render_html
  @_state = nil   # reset Phlex's one-shot render guard
  call
end
```

### Cross-connection updates — the `stream` helper

Everything above pushes only to the connection that triggered it. To let *one* user's
change reach *other* users' open tabs, the app uses `Rage::PubSub`, a lightweight pub/sub
mechanism that allows Rage instances to communicate across processes and servers. The raw
`Rage::PubSub` API (`subscribe`/`unsubscribe`/`publish`) is wrapped by the **`ModelStream`**
module so that components never interact with it directly.

**Publishing.** A model calls `ModelStream.emit(self)` in an `after_commit`
callback. The method encodes the model's identity as a
[GlobalID](https://github.com/rails/globalid) and publishes it via `Rage::PubSub`:

```ruby
class Article < ApplicationRecord
  after_commit :broadcast_status

  def broadcast_status
    ModelStream.emit(self) if previous_changes.key?("status")
  end
end
```

**Subscribing.** A component uses the `stream` helper in its initializer. `stream` wraps the
model in a `SimpleDelegator`, subscribes to messages for that model, and — when a message
arrives — schedules a new fiber, reconstructs `Fiber[:live_state]` in it, locates a fresh
copy via GlobalID, swaps it into the delegator, runs an optional block (for side effects
like toasts), and re-renders the component:

```ruby
class Articles::Card < LiveView
  def initialize(article:)
    @article = stream(article) do |article|
      Notification.new(
        message: "…updated to '#{article.status}'"
      ).append(target: "main")
    end
  end
end
```

When no extra side effect is needed, a bare `@article = stream(article)` is enough — the
component will still auto-reload and re-render on changes.

During a dead (HTTP) render, `stream` is a no-op: it returns the model unwrapped so the same
component code works for both the initial page load and the WebSocket session.

**Cleanup.** Each `stream` call pushes a teardown lambda (`Rage::PubSub.unsubscribe`) into
`Fiber[:live_state][:cleanup]`. `LiveChannel` runs these on every navigation (unmount the
old page before rendering the new one) and on disconnect, so subscriptions no longer
accumulate.

**Fiber scheduling.** When a pub/sub message arrives, `Rage::PubSub` invokes the callback
in the current context — but the callback needs to perform blocking operations (like
`GlobalID::Locator.locate`) and push updates to the client. To handle this, `ModelStream`
schedules a new fiber via `Fiber.schedule` and reconstructs `Fiber[:live_state]` (captured
at subscription time) into that fiber. This allows the callback to call `replace` and have
it push to the correct client connection.

**Publishing facts.** The conventional way to fan a change out — render HTML once in the
`after_commit` and broadcast those bytes for every subscriber to swap in — is deliberately
not what happens here. `ModelStream.emit(self)` publishes a fact (i.e. only the model's identity — a GlobalID); the payload carries no markup and knows nothing about views. Each per-connection component decides how to re-render itself (honoring its own in-memory state) and pushes only to its own socket.

So a single publish becomes **N independent re-renders, each correct for its own UI**, rather
than one render copied into N identical DOMs.

### Security

`/live` events are a remote-method-call surface, so dispatch is deliberately narrow: only
**public methods defined directly on the component class** are callable, and
`view_template` is excluded. This check lives in `LiveView#handle_event`:

```ruby
def handle_event(event)
  allowed = self.class.public_instance_methods(false) - [:view_template]
  return unless allowed.include?(event)

  @_streamed = false
  public_send(event)
  replace unless @_streamed
end
```

Everything inherited from `LiveView` / `Phlex::HTML` / `Object` (including the stream ops)
is unreachable from the client.

---

## Current state

**Implemented**
- WebSocket transport via `Rage::Cable` (`:raw_websocket_json`) — native browser
  `WebSocket`, no client library.
- Stateful, in-memory components stored per connection in fiber storage.
- `live_id` removed; identity is the instance's `object_id`.
- Transient UI state on components (`toggle_details` / `@expanded`).
- **Navigation delegated to the Rage app** — one controller implementation serves both the
  HTTP load and every socket navigation (links, forms, back/forward, `_method` overrides).
- Targeted stream ops (`replace` / `append` / `prepend` / `remove`) + `live_click`.
- Auto-`replace` after event handlers — if a handler doesn't call a stream op, `replace` is called automatically.
- Cross-connection updates via `Rage::PubSub` + toast `Notification`s.
- `stream` helper for declarative model tracking — auto-reload, re-render, optional side-effect block, with subscription cleanup on navigation and disconnect.
- Progressive enhancement: HTTP dead render for first paint / no-JS.

**Not yet done / known limitations**
- **Authentication & authorization.** Not implemented. The connection is the intended
  home for it — add `app/channels/rage_cable/connection.rb` with
  `identified_by :current_user` and `reject_unauthorized_connection`. (Boot currently logs
  a warning that no connection class is defined, so all connections are accepted.)
- **Mutation redirects don't carry a body.** A `redirect_to` (create/update/delete) returns
  a 302 with an empty body, so the `navigate` message carries the target `url` but no HTML;
  the target page isn't rendered as part of the same round-trip yet.
- **No server-side diffing.** The whole component (or page) is re-rendered and morphlex
  computes the patch in the browser — fine for small components, wasteful for large ones.
- **Reconnect re-hydrates from scratch.** A dropped socket re-mounts the page, so transient
  UI state resets (expected, but worth knowing).

---

## File map

```
app/
  channels/
    live_channel.rb        # the live session: subscribe, delegate navigation, event dispatch
  controllers/
    articles_controller.rb # ordinary controller — serves HTTP load AND socket navigations
    application_controller.rb
  models/
    article.rb             # after_commit -> ModelStream.emit on status change
  views/
    live_view.rb           # LiveView base: identity, registry, stream ops, live_click
    model_stream.rb        # `stream` helper: model tracking, publish, cleanup
    live_update_js.rb       # client: WebSocket + event delegation + morphlex
    layout.rb              # shared HTML shell (main#main); embeds live_update_scripts
    notification.rb        # LiveView toast, appended on pub/sub event
    articles/
      card.rb              # LiveView: toggle_status (persistent) + toggle_details (transient)
      show.rb              # LiveView: subscribes to article changes via `stream`
      index.rb  form.rb    # plain Phlex pages
config/
  application.rb           # :phlex renderer + config.cable.protocol = :raw_websocket_json
  routes.rb               # resources :articles + mount Rage::Cable.application at "/live"
```

---

## Run it

```sh
bundle install
bundle exec rage db:setup
bundle exec rage s          # http://localhost:3000
```

Open two tabs to see each maintain its own live session (its own expanded/collapsed
cards); publish/unpublish persists to the database, "Show more/less" does not.
