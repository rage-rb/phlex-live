class Articles::Card < LiveView
  def initialize(article:)
    @article = article
    @expanded = false
  end

  def view_template
    div(class: "card") do
      div(class: "card-header") do
        a(href: "/articles/#{@article.id}", class: "card-title") { @article.title }
        div(class: "actions") do
          span(class: "badge badge-#{@article.status}") { @article.status }
          button(**live_click(:toggle_status), class: "btn btn-sm btn-secondary") do
            @article.status == "draft" ? "Publish" : "Unpublish"
          end
          a(href: "/articles/#{@article.id}/edit", class: "btn btn-secondary btn-sm") { "Edit" }
          form(method: "post", action: "/articles/#{@article.id}", style: "display:inline") do
            input type: "hidden", name: "_method", value: "delete"
            button(type: "submit", class: "btn btn-danger btn-sm") { "Delete" }
          end
        end
      end
      div(class: "card-body") do
        plain(@expanded ? @article.body : @article.body.truncate(150))
      end
      if @article.body.length > 150
        button(**live_click(:toggle_details), class: "btn btn-sm btn-secondary") do
          @expanded ? "Show less" : "Show more"
        end
      end
      div(class: "meta") do
        plain "Updated #{@article.updated_at.strftime('%b %d, %Y at %H:%M')}"
      end
    end
  end

  # Persistent change: flips the status in the database, then re-renders.
  def toggle_status
    new_status = @article.status == "draft" ? "published" : "draft"
    @article.update!(status: new_status)
    replace
  end

  # Transient change: `@expanded` lives only in this component's memory, for as long
  # as the WebSocket connection is open — no database, no page reload. This is the
  # capability that the stateful (WebSocket) model unlocks over the stateless one.
  def toggle_details
    @expanded = !@expanded
    replace
  end
end
