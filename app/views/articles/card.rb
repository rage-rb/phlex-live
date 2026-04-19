class Articles::Card < Phlex::HTML
  def initialize(article:)
    @article = article
  end

  def view_template
    div(class: "card") do
      div(class: "card-header") do
        a(href: "/articles/#{@article.id}", class: "card-title") { @article.title }
        div(class: "actions") do
          span(class: "badge badge-#{@article.status}") { @article.status }
          a(href: "/articles/#{@article.id}/edit", class: "btn btn-secondary btn-sm") { "Edit" }
          form(method: "post", action: "/articles/#{@article.id}", style: "display:inline") do
            input type: "hidden", name: "_method", value: "delete"
            button(type: "submit", class: "btn btn-danger btn-sm") { "Delete" }
          end
        end
      end
      div(class: "card-body") do
        plain @article.body.truncate(150)
      end
      div(class: "meta") do
        plain "Updated #{@article.updated_at.strftime('%b %d, %Y at %H:%M')}"
      end
    end
  end
end
