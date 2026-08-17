# Phlex mixin that injects the client-side JavaScript for the live view system.
# Include this in your layout component and call `live_update_scripts` to emit a
# <script> tag that handles:
#   - a WebSocket connection with automatic reconnect + re-hydration
#   - navigation over the socket (links, forms, back/forward), morphed into the page
#   - targeted stream operations (replace, append, prepend, remove)
#   - server-side event dispatch (live_click)
module LiveUpdateJs
  def live_update_scripts(cable_path: "/live/live")
    script(type: "module") { raw(safe(live_update_js(cable_path: cable_path))) }
  end

  private

  def live_update_js(cable_path:)
    <<~JS
      import { morph, morphDocument } from "https://cdn.jsdelivr.net/npm/morphlex@1.4.0/dist/morphlex.min.js";

      (function() {
        // Module scripts run once, but guard anyway in case the DOM is re-morphed.
        if (window.__phlexLive) return;
        window.__phlexLive = true;

        var cablePath = #{cable_path.to_json};
        var morphOpts = { preserveChanges: true };
        var socket;

        function wsUrl() {
          var scheme = location.protocol === "https:" ? "wss:" : "ws:";
          return scheme + "//" + location.host + cablePath;
        }

        function send(message) {
          if (socket && socket.readyState === WebSocket.OPEN) {
            socket.send(JSON.stringify(message));
          }
        }

        // Ask the server to (re)render a page into this connection. Sent on connect
        // (hydration), on link clicks, on form submits, and on back/forward.
        function navigate(url, options) {
          send(Object.assign({ type: "navigate", url: url }, options || {}));
        }

        // Server -> client messages. "update" carries a full page (SPA-style morph);
        // the others are targeted operations produced by a component's stream methods.
        function handle(data) {
          switch (data.action) {
            case "update":
              morphDocument(document, data.html, morphOpts);
              var here = location.pathname + location.search;
              if (data.url && data.url !== here) {
                history.pushState(null, "", data.url);
              }
              break;
            case "replace":
              var tmp = document.createElement("div");
              tmp.innerHTML = data.html;
              var newEl = tmp.firstElementChild;
              if (newEl && newEl.id) {
                var target = document.getElementById(newEl.id);
                if (target) morph(target, newEl, morphOpts);
              }
              break;
            case "append":
              var container = document.getElementById(data.target);
              if (container) container.insertAdjacentHTML("beforeend", data.html);
              break;
            case "prepend":
              var head = document.getElementById(data.target);
              if (head) head.insertAdjacentHTML("afterbegin", data.html);
              break;
            case "remove":
              var el = document.getElementById(data.id);
              if (el) el.remove();
              break;
            case "navigate":
              navigate(data.url);
              break;
          }
        }

        function connect() {
          socket = new WebSocket(wsUrl());
          socket.addEventListener("open", function() {
            // Hydrate: render the current page on the server into this connection.
            navigate(location.pathname + location.search);
          });
          socket.addEventListener("message", function(e) {
            handle(JSON.parse(e.data));
          });
          // Reconnect (and re-hydrate) if the connection drops.
          socket.addEventListener("close", function() {
            setTimeout(connect, 1000);
          });
        }

        // --- Event delegation ---

        // Clicks: a live_click dispatches a server-side event; a same-origin link
        // navigates over the socket instead of triggering a full page load.
        document.addEventListener("click", function(e) {
          var liveEl = e.target.closest("[data-live-click]");
          if (liveEl) {
            e.preventDefault();
            send({ type: "event", id: liveEl.dataset.liveId, event: liveEl.dataset.liveClick });
            return;
          }

          var link = e.target.closest("a");
          if (!link) return;
          if (link.origin !== location.origin) return;
          if (e.ctrlKey || e.metaKey || e.shiftKey) return;

          e.preventDefault();
          history.pushState(null, "", link.href);
          navigate(link.pathname + link.search);
        });

        // Forms submit over the socket; the server performs the mutation and replies
        // with the page to land on (including the URL to push into history).
        document.addEventListener("submit", function(e) {
          var form = e.target;
          var url = new URL(form.action, location.href);
          if (url.origin !== location.origin) return;

          e.preventDefault();
          navigate(url.pathname + url.search, {
            method: (form.method || "POST").toUpperCase(),
            body: new URLSearchParams(new FormData(form)).toString()
          });
        });

        window.addEventListener("popstate", function() {
          navigate(location.pathname + location.search);
        });

        connect();
      })();
    JS
  end
end
