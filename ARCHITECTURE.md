# phlex-live — System Architecture

A proof of concept for **LiveView-style reactivity in Ruby**, built from:

- **[Phlex](https://github.com/phlex-ruby/phlex)** — views are plain Ruby classes.
- **[Rage](https://github.com/rage-rb/rage)** — a fiber-based framework with native
  WebSockets (`Rage::Cable`).
- **[morphlex](https://github.com/yippee-fun/morphlex)** — DOM morphing in the browser.

The demo is a small article CMS. Interactions and navigation happen over a single
WebSocket per tab; the server renders Phlex components and pushes HTML back; the browser
morphs it into the page. No template files, no per-interaction controllers, no
hand-written client framework.

---

## Motivation

An earlier version of this project drove the UI over **Server-Sent Events (SSE)**. It
worked, but it had two properties we wanted to change:

1. **Statelessness forced identity into the DOM.** With SSE there is no durable
   server-side handle on a component. To route a click back to "the card for article
   42," the component encoded its identity into a string (`Articles::Card--Article--42`),
   which the server parsed and used to *rebuild* the component from the database on every
   interaction. It was clever but hard to reason about, and every event meant a fresh
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
  state** — moving the system from the Hotwire category into the LiveView category.

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
  ┌───────────────────────────┐                ┌──────────────────────────────────┐
  │ 1. GET /articles          │ ─ HTTP ──────► │ ArticlesController#index          │
  │    (first paint)          │ ◄───────────── │ → dead-rendered HTML              │
  │                           │     HTML       │                                   │
  │ 2. new WebSocket(         │                │                                   │
  │      "/live/live")        │ ═ WS open ════►│ LiveChannel#subscribed            │
  │                           │                │   Fiber[:live_update] = transmit  │  one fiber
  │ 3. {type:"navigate",      │ ═ WS msg ═════►│ LiveChannel#receive → navigate    │  per
  │     url:"/articles"}      │                │   render page, register children  │  connection
  │    (hydrate)              │ ◄═ WS msg ═════│   {action:"update", html, url}    │
  │    morph document         │                │                                   │
  │                           │                │  Fiber[:live_components] =         │
  │                           │                │    {"live-1"=>#<Card…>, …}         │
  │ 4. click Publish          │ ═ WS msg ═════►│ receive → event                   │
  │    {type:"event",         │                │   comp = registry["live-1"]       │
  │     id:"live-1",          │                │   comp.toggle_status → replace    │
  │     event:"toggle_status"}│ ◄═ WS msg ═════│   {action:"replace", html}        │
  │    morph #live-1          │                │                                   │
  └───────────────────────────┘                └──────────────────────────────────┘
```

### Why Rage: one connection = one persistent fiber

The whole design rests on a property of `Rage::Cable`: **each WebSocket connection is
serviced by a single, long-lived fiber.** `subscribed` and *every* subsequent `receive`
run in that same fiber. That means anything stored in Ruby's fiber-local storage
(`Fiber[...]`) during `subscribed` is still there on the next message.

Fibers make this cheap: a mostly-idle connection is a parked fiber, not a parked thread,
and blocking ActiveRecord calls yield to the scheduler instead of pinning a thread. So
"keep a live object per open tab" scales.

Three things live in that fiber's storage for the life of the connection:

| Key                     | What it is                                                        |
|-------------------------|-------------------------------------------------------------------|
| `Fiber[:live_update]`   | A closure over this connection's `transmit` — how components push. |
| `Fiber[:live_components]` | Registry: `{ "live-1" => <component>, … }` — the mounted components. |
| `Fiber[:live_counter]`  | Per-page counter used to generate stable component ids.           |

### The building blocks

| Piece | File | Responsibility |
|-------|------|----------------|
| **`LiveChannel`** | `app/channels/live_channel.rb` | The live session. Installs the fiber storage on `subscribe`; on `receive`, dispatches `navigate` (render a page) or `event` (invoke a component method). |
| **`LiveView`** | `app/views/live_view.rb` | Base class for interactive components. Generates an id, registers the instance, wraps it in a `<div id>`, and provides stream ops (`replace`/`append`/`prepend`/`remove`) + `live_click`. |
| **`LiveUpdateJs`** | `app/views/live_update_js.rb` | ~130 lines of dependency-light client JS: WebSocket connect/reconnect, event delegation (clicks, forms, popstate), and applying server messages via morphlex. |
| **`:phlex` renderer** | `config/application.rb` | Renders a component to HTML for the initial (JS-less) load. |
| **`ArticlesController`** | `app/controllers/articles_controller.rb` | Ordinary HTTP controller for first paint / no-JS fallback. |

`Articles::Index`, `Show`, and `Form` are **plain `Phlex::HTML` pages**. Only
`Articles::Card` is a **`LiveView`** — the distinction is simply "is this an individually
updatable, stateful fragment?"

### The message protocol

All server↔client traffic is JSON over the one socket.

**Client → server** (handled by `LiveChannel#receive`, keyed on `type`):

```jsonc
{ "type": "navigate", "url": "/articles/42", "method": "GET" }        // link / form / popstate
{ "type": "event",    "id": "live-1", "event": "toggle_status" }      // a live_click
```

**Server → client** (via `Fiber[:live_update]` → `transmit`, keyed on `action`):

```jsonc
{ "action": "update",  "html": "<!doctype…>", "url": "/articles/42" } // full-page morph
{ "action": "replace", "html": "<div id='live-1'>…</div>" }          // targeted morph
{ "action": "append",  "target": "list", "html": "…" }
{ "action": "prepend", "target": "list", "html": "…" }
{ "action": "remove",  "id": "live-1" }
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
`LiveView` child in `Fiber[:live_components]`, and pushes it back as an `update`. The
client morphs it over the identical dead-rendered DOM — visually a no-op, but now the
server holds live component instances for this tab.

**3. Navigation.** A link click, form submit, or back/forward sends a `navigate` message.
`LiveChannel#dispatch` maps `(method, path, params)` to a root component (or performs a
mutation and resolves the redirect target), the channel **resets the registry** (which
*unmounts* the previous page's components), re-renders, and pushes an `update` with the
canonical `url` for the client to place in history. Rails-style `_method` overrides from
forms (`PATCH`/`DELETE`) are honored; validation failures re-render the form in place with
`url: nil` so the address bar is left untouched.

**4. Events.** A `data-live-click` element sends an `event` message with the component id
and method name. The channel looks the instance up in the registry — **it is still in
memory, with all its state** — checks the method is allowed, and calls it. The method
mutates state and calls a stream op (e.g. `replace`), which re-renders and pushes the
change to *this* connection.

### Identity and state without `live_id`

When a `LiveView` renders, `around_template` assigns it a stable per-page id
(`live-1`, `live-2`, …), stores the **actual instance** in `Fiber[:live_components]`, and
wraps its output in `<div id="live-1">`:

```ruby
def around_template
  @live_id ||= LiveView.next_id
  (Fiber[:live_components] ||= {})[@live_id] = self
  div(id: @live_id) { super }
end
```

Identity is now just a hash key into live objects — no string encoding, no DB round-trip
to reconstruct. And because the instance persists, it can hold transient state. `Card`
demonstrates both kinds side by side:

```ruby
def toggle_status   # persistent: writes the DB, then re-renders
  @article.update!(status: @article.status == "draft" ? "published" : "draft")
  replace
end

def toggle_details  # transient: in-memory only, survives across events
  @expanded = !@expanded
  replace
end
```

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

### Security

`/live` events are a remote-method-call surface, so dispatch is deliberately narrow: only
**public methods defined directly on the component class** are callable, and
`view_template` is excluded.

```ruby
allowed = component.class.public_instance_methods(false) - [:view_template]
return unless allowed.include?(event)
component.public_send(event)
```

Everything inherited from `LiveView` / `Phlex::HTML` / `Object` (including the stream ops)
is unreachable from the client.

---

## Current state

**Implemented**
- WebSocket transport via `Rage::Cable` (`:raw_websocket_json`) — native browser
  `WebSocket`, no client library.
- Stateful, in-memory components stored per connection in fiber storage.
- `live_id` removed; identity is a registry key.
- Transient UI state on components (`toggle_details` / `@expanded`).
- SPA navigation over the socket (links, forms, back/forward, `_method` overrides,
  redirects, validation-failure re-render).
- Targeted stream ops (`replace` / `append` / `prepend` / `remove`) + `live_click`.
- Progressive enhancement: HTTP dead render for first paint / no-JS.

**Not yet done / known limitations**
- **Authentication & authorization.** Not implemented. The connection is the intended
  home for it — add `app/channels/rage_cable/connection.rb` with
  `identified_by :current_user` and `reject_unauthorized_connection`. (Boot currently logs
  a warning that no connection class is defined, so all connections are accepted.)
- **Updates are per-connection, not broadcast.** A component pushes only to *its own*
  socket via `Fiber[:live_update]`. There is no cross-client fan-out (user A does not see
  user B's change). For that you'd add `stream_for current_user` + `broadcast_to`. For a
  single-user CMS admin this per-session behavior is the correct default.
- **Navigation dispatch mirrors `ArticlesController`.** `LiveChannel#dispatch` re-derives
  routing/CRUD that the HTTP controller also expresses. A fuller implementation would
  share one router between HTTP and the socket.
- **No server-side diffing.** The whole component (or page) is re-rendered and morphlex
  computes the patch in the browser — fine for small components, wasteful for large ones.
- **Reconnect re-hydrates from scratch.** A dropped socket re-mounts the page, so transient
  UI state resets (expected, but worth knowing).

---

## File map

```
app/
  channels/
    live_channel.rb        # the live session: subscribe + navigate + event dispatch
  controllers/
    articles_controller.rb # HTTP dead render / no-JS fallback
    application_controller.rb
  models/
    article.rb
  views/
    live_view.rb           # LiveView base: identity, registry, stream ops, live_click
    live_update_js.rb       # client: WebSocket + event delegation + morphlex
    layout.rb              # shared HTML shell; embeds live_update_scripts
    articles/
      card.rb              # the one LiveView (toggle_status + toggle_details)
      index.rb  show.rb  form.rb   # plain Phlex pages
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
