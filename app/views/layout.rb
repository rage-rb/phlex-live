class Layout < Phlex::HTML
  include LiveUpdateJs

  def initialize(title: "CMS Admin")
    @title = title
  end

  def view_template(&block)
    doctype
    html(lang: "en") do
      head do
        meta(charset: "utf-8")
        meta(name: "viewport", content: "width=device-width, initial-scale=1")
        title { @title }
        style { raw(safe(css)) }
      end
      body do
        nav(class: "navbar") do
          div(class: "container") do
            a(href: "/articles", class: "logo") { "CMS Admin" }
          end
        end
        main(class: "container") do
          yield
        end

        live_update_scripts
      end
    end
  end

  private

  def css
    <<~CSS
      *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
      body {
        font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
        background: #f5f7fa;
        color: #1a1a2e;
        line-height: 1.6;
      }
      .navbar {
        background: #1a1a2e;
        padding: 1rem 0;
        margin-bottom: 2rem;
      }
      .logo {
        color: #fff;
        text-decoration: none;
        font-size: 1.25rem;
        font-weight: 700;
        letter-spacing: -0.02em;
      }
      .container { max-width: 960px; margin: 0 auto; padding: 0 1.5rem; }
      h1 { font-size: 1.75rem; font-weight: 700; margin-bottom: 1.5rem; letter-spacing: -0.02em; }
      .card {
        background: #fff;
        border-radius: 10px;
        box-shadow: 0 1px 3px rgba(0,0,0,0.08);
        padding: 1.5rem;
        margin-bottom: 1rem;
      }
      .card-header {
        display: flex;
        justify-content: space-between;
        align-items: center;
        margin-bottom: 0.5rem;
      }
      .card-title {
        font-size: 1.125rem;
        font-weight: 600;
        color: #1a1a2e;
        text-decoration: none;
      }
      .card-title:hover { color: #4361ee; }
      .card-body { color: #555; font-size: 0.95rem; }
      .badge {
        display: inline-block;
        padding: 0.2rem 0.6rem;
        border-radius: 999px;
        font-size: 0.75rem;
        font-weight: 600;
        text-transform: uppercase;
        letter-spacing: 0.04em;
      }
      .badge-draft { background: #fef3c7; color: #92400e; }
      .badge-published { background: #d1fae5; color: #065f46; }
      .meta { color: #888; font-size: 0.8rem; margin-top: 0.5rem; }
      .btn {
        display: inline-block;
        padding: 0.55rem 1.2rem;
        border-radius: 7px;
        font-size: 0.9rem;
        font-weight: 500;
        text-decoration: none;
        border: none;
        cursor: pointer;
        transition: background 0.15s;
      }
      .btn-primary { background: #4361ee; color: #fff; }
      .btn-primary:hover { background: #3a56d4; }
      .btn-secondary { background: #e5e7eb; color: #374151; }
      .btn-secondary:hover { background: #d1d5db; }
      .btn-danger { background: #fee2e2; color: #991b1b; }
      .btn-danger:hover { background: #fecaca; }
      .btn-sm { padding: 0.35rem 0.8rem; font-size: 0.8rem; }
      .actions { display: flex; gap: 0.5rem; align-items: center; }
      .top-bar {
        display: flex;
        justify-content: space-between;
        align-items: center;
        margin-bottom: 1.5rem;
      }
      .form-group { margin-bottom: 1.25rem; }
      .form-group label {
        display: block;
        font-weight: 500;
        margin-bottom: 0.35rem;
        font-size: 0.9rem;
      }
      .form-group input,
      .form-group textarea,
      .form-group select {
        width: 100%;
        padding: 0.6rem 0.8rem;
        border: 1px solid #d1d5db;
        border-radius: 7px;
        font-size: 0.95rem;
        font-family: inherit;
        background: #fff;
        transition: border-color 0.15s;
      }
      .form-group input:focus,
      .form-group textarea:focus,
      .form-group select:focus {
        outline: none;
        border-color: #4361ee;
        box-shadow: 0 0 0 3px rgba(67,97,238,0.1);
      }
      .form-group textarea { min-height: 200px; resize: vertical; }
      .error-list {
        background: #fef2f2;
        border: 1px solid #fecaca;
        border-radius: 7px;
        padding: 1rem 1.25rem;
        margin-bottom: 1.5rem;
        color: #991b1b;
        font-size: 0.9rem;
      }
      .error-list ul { margin: 0.5rem 0 0 1.25rem; }
      .empty-state {
        text-align: center;
        padding: 3rem 1rem;
        color: #888;
      }
      .empty-state p { margin-bottom: 1rem; font-size: 1.1rem; }
      .article-body {
        line-height: 1.8;
        font-size: 1.05rem;
        white-space: pre-wrap;
      }
    CSS
  end
end
