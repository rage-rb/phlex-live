# A toast-style notification that slides into the top-right corner of the viewport,
# waits a few seconds, then slides back out.
#
# Deliberately JS-free: both the entrance and the dismissal are CSS keyframe
# animations, which the browser runs as soon as the element enters the document —
# so it plays on first paint with no client-side code at all. Note that on SPA
# navigation morphlex *preserves* the existing node rather than re-inserting it,
# so an already-dismissed notification stays dismissed until a full page load.
#
# The component carries its own CSS (see `css` below) rather than relying on the
# shared stylesheet in `Layout`, so it is self-contained: render it anywhere and
# it brings its styles with it.
class Notification < LiveView
  def initialize(message:, title: "Notification")
    @message = message
    @title = title
  end

  def view_template
    # `context` is Phlex's per-render shared hash — every component in a single
    # render tree sees the same object — so the <style> block is emitted once no
    # matter how many notifications render on the page.
    unless context[:notification_css_rendered]
      context[:notification_css_rendered] = true
      style { raw(safe(css)) }
    end

    div(class: "notification", role: "status", aria_live: "polite") do
      div(class: "notification-title") { @title }
      div(class: "notification-body") { @message }
    end
  end

  private

  def css
    <<~CSS
      .notification {
        position: fixed;
        top: 1rem;
        right: 1rem;
        z-index: 100;
        width: min(22rem, calc(100vw - 2rem));
        background: #fff;
        border-radius: 10px;
        border-left: 4px solid #4361ee;
        box-shadow: 0 4px 16px rgba(0,0,0,0.12);
        padding: 0.85rem 1.1rem;
        /* Two chained animations. The second is delayed, so it sits inert until
           the notification has been on screen for 6s; `forwards` makes its final
           (hidden) state stick instead of snapping back to visible. */
        animation:
          notification-in 0.35s cubic-bezier(0.16, 1, 0.3, 1) both,
          notification-out 0.4s ease-in 6s forwards;
      }
      .notification-title {
        font-size: 0.95rem;
        font-weight: 600;
        margin-bottom: 0.1rem;
      }
      .notification-body { color: #555; font-size: 0.875rem; }
      @keyframes notification-in {
        from { opacity: 0; transform: translateX(calc(100% + 1rem)); }
        to   { opacity: 1; transform: translateX(0); }
      }
      /* No `from`, so it animates out from whatever the element currently is. */
      @keyframes notification-out {
        to { opacity: 0; transform: translateX(calc(100% + 1rem)); visibility: hidden; }
      }
      /* Keep the auto-dismiss, drop the motion: delays are untouched here. */
      @media (prefers-reduced-motion: reduce) {
        .notification { animation-duration: 0.01ms, 0.01ms; }
      }
    CSS
  end
end
