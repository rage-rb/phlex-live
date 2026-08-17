class Articles::Show < LiveView
  def initialize(article:)
    @article = article

    Rage::Signal.on("article_changed:#{@article.id}") do |status|
      Notification.new(
        message: "The \"#{@article.title}\" article status has been updated to '#{status}'"
      ).append(target: "main")

      @article.status = status
      replace
    end
  end

  def view_template
    render Layout.new(title: "#{@article.title} - CMS Admin") do
      div(class: "top-bar") do
        h1 { @article.title }
        div(class: "actions") do
          span(class: "badge badge-#{@article.status}") { @article.status }
          a(href: "/articles/#{@article.id}/edit", class: "btn btn-secondary btn-sm") { "Edit" }
          form(method: "post", action: "/articles/#{@article.id}", style: "display:inline") do
            input type: "hidden", name: "_method", value: "delete"
            button(type: "submit", class: "btn btn-danger btn-sm") { "Delete" }
          end
        end
      end

      div(class: "card") do
        div(class: "article-body") { plain @article.body }
        div(class: "meta") do
          plain "Created #{@article.created_at.strftime('%b %d, %Y at %H:%M')} · Updated #{@article.updated_at.strftime('%b %d, %Y at %H:%M')}"
        end
      end

      div(style: "margin-top: 1rem") do
        a(href: "/articles", class: "btn btn-secondary") { "Back to articles" }
      end
    end
  end
end
