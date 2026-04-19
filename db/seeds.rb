Article.find_or_create_by!(title: "Getting Started with Rage") do |a|
  a.body = "Rage is a Ruby web framework compatible with the Rails API that runs on a fiber-based server. It's designed to be fast and lightweight, perfect for building modern web applications.\n\nKey features include fiber-based concurrency, Rails-compatible API, and excellent performance out of the box."
  a.status = "published"
end

Article.find_or_create_by!(title: "Building Views with Phlex") do |a|
  a.body = "Phlex is a framework for building views in pure Ruby. Instead of using template files like ERB, you write Ruby classes that generate HTML.\n\nThis approach gives you the full power of Ruby in your views - inheritance, composition, and all the object-oriented patterns you already know."
  a.status = "published"
end

Article.find_or_create_by!(title: "Draft: Performance Benchmarks") do |a|
  a.body = "This article will cover performance benchmarks comparing Rage with other Ruby web frameworks. Stay tuned for results."
  a.status = "draft"
end
