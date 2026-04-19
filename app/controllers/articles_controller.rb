class ArticlesController < ApplicationController
  def index
    articles = Article.order(id: :desc)
    render phlex: Articles::Index, articles: articles
  end

  def show
    article = Article.find(params[:id])
    render phlex: Articles::Show, article: article
  end

  def new
    render phlex: Articles::Form, article: Article.new
  end

  def create
    article = Article.new(title: params[:title], body: params[:body], status: params[:status])

    if article.save
      redirect_to "/articles/#{article.id}"
    else
      render phlex: Articles::Form, article: article
    end
  end

  def edit
    article = Article.find(params[:id])
    render phlex: Articles::Form, article: article
  end

  def update
    article = Article.find(params[:id])

    if article.update(title: params[:title], body: params[:body], status: params[:status])
      redirect_to "/articles/#{article.id}"
    else
      render phlex: Articles::Form, article: article
    end
  end

  def destroy
    article = Article.find(params[:id])
    article.destroy

    redirect_to "/articles"
  end
end
