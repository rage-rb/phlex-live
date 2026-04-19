class Articles::Form < LiveView
  def initialize(article:)
    @article = article
    @errors = article.errors.full_messages
  end

  def view_template
    editing = @article.persisted?

    if editing
      action = "/articles/#{@article.id}"
      method = "patch"
    else
      action = "/articles"
      method = "post"
    end

    render Layout.new(title: "#{editing ? 'Edit' : 'New'} Article - CMS Admin") do
      h1 { editing ? "Edit Article" : "New Article" }

      if @errors.any?
        div(class: "error-list") do
          strong { "Please fix the following errors:" }
          ul do
            @errors.each { |e| li { e } }
          end
        end
      end

      div(class: "card") do
        form(method: "post", action: action) do
          input type: "hidden", name: "_method", value: method
          div(class: "form-group") do
            label(for: "title") { "Title" }
            input(type: "text", id: "title", name: "title", value: @article.title || "", placeholder: "Article title")
          end

          div(class: "form-group") do
            label(for: "body") { "Body" }
            textarea(id: "body", name: "body", placeholder: "Write your article content here...") { @article.body || "" }
          end

          div(class: "form-group") do
            label(for: "status") { "Status" }
            select(id: "status", name: "status") do
              %w[draft published].each do |s|
                if @article.status == s
                  option(value: s, selected: "selected") { s.capitalize }
                else
                  option(value: s) { s.capitalize }
                end
              end
            end
          end

          div(class: "actions") do
            button(type: "submit", class: "btn btn-primary") { editing ? "Update Article" : "Create Article" }
            a(href: editing ? "/articles/#{@article.id}" : "/articles", class: "btn btn-secondary") { "Cancel" }
          end
        end
      end
    end
  end
end
