# Phlex mixin that injects the client-side JavaScript for the live view system.
# Include this in your layout component and call `live_update_scripts` to emit
# a <script> tag that handles:
#   - SSE connection with automatic reconnect
#   - Full-page morphing for SPA-like navigation
#   - Form interception (submits via fetch instead of full reload)
#   - Browser history management (back/forward buttons)
module LiveUpdateJs
  def live_update_scripts(sse_url: "/live")
    script(type: "module") { raw(safe(live_update_js(sse_url: sse_url))) }
  end

  private

  def live_update_js(sse_url:)
    <<~JS
      import { morphDocument } from "https://cdn.jsdelivr.net/npm/morphlex@1.4.0/dist/morphlex.min.js";

      (function() {
        var sseUrl = #{sse_url.to_json};
        var LIVE_HEADER = "Phlex-Live";
        var morphOpts = { preserveChanges: true };

        // Morphs the entire document (html, head, body) using the server-rendered
        // HTML. Used for full-page navigation updates sent as SSE "update" events
        // and for SPA-style fetch responses.
        function applyUpdate(html) {
          morphDocument(document, html, morphOpts);
        }

        function connect() {
          var source = new EventSource(sseUrl);

          source.addEventListener("update", function(e) {
            applyUpdate(e.data);
          });
        }

        // Fetches a page via AJAX and morphs the response into the current document,
        // creating an SPA-like navigation experience without full page reloads.
        // If the server responds with a redirect (e.g. after form submission),
        // the browser URL is updated to match.
        function liveNavigate(url, options) {
          return fetch(url, options).then(function(response) {
            if (response.redirected) {
              history.pushState(null, "", response.url);
            }
            return response.text();
          }).then(function(html) {
            if (html && html.length > 0) {
              applyUpdate(html);
            }
          });
        }

        document.addEventListener("click", function(e) {
          var link = e.target.closest("a");
          if (!link) return;
          if (link.origin !== location.origin) return;
          if (e.ctrlKey || e.metaKey || e.shiftKey) return;

          e.preventDefault();
          history.pushState(null, "", link.href);
          liveNavigate(link.href, { headers: { [LIVE_HEADER]: "true" } });
        });

        // Form handler: intercepts same-origin form submissions and sends them
        // via fetch with the Phlex-Live header. The server checks this header to
        // decide whether to broadcast via SSE (for live clients) or return
        // a normal HTML response.
        document.addEventListener("submit", function(e) {
          var form = e.target;
          var url = new URL(form.action, location.href);
          if (url.origin !== location.origin) return;

          e.preventDefault();
          liveNavigate(form.action, {
            method: form.method || "POST",
            headers: { [LIVE_HEADER]: "true" },
            body: new URLSearchParams(new FormData(form))
          });
        });

        window.addEventListener("popstate", function() {
          liveNavigate(location.href, { headers: { [LIVE_HEADER]: "true" } });
        });

        connect();
      })();
    JS
  end
end
