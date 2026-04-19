class Articles::Index < LiveView
  def initialize(articles:)
    @articles = articles
  end

  def view_template
    render Layout.new(title: "Articles - CMS Admin") do
      div(class: "top-bar") do
        h1 { "Articles" }
        a(href: "/articles/new", class: "btn btn-primary") { "New Article" }
      end

      if @articles.empty?
        div(class: "card empty-state") do
          p { "No articles yet." }
          a(href: "/articles/new", class: "btn btn-primary") { "Create your first article" }
        end
      else
        @articles.each { |article| render Articles::Card.new(article: article) }
      end
    end
  end
end
