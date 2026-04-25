# frozen_string_literal: true

# _plugins/redirect-from-old-urls.rb
# Generates redirect pages at old /posts/<slug>/ URLs pointing to new /en/posts/<slug>/ URLs
# This handles the URL migration when adding language prefix to post permalinks.

Jekyll::Hooks.register :site, :post_write do |site|
  site.posts.docs.each do |post|
    next unless post.data['lang'] == 'en'

    slug = post.data['slug']
    old_url = "/posts/#{slug}/"
    new_url = post.url

    next if old_url == new_url

    redirect_html = <<~HTML
      <!DOCTYPE html>
      <html lang="en">
      <head>
        <meta charset="utf-8">
        <meta http-equiv="refresh" content="0; url=#{new_url}">
        <link rel="canonical" href="#{new_url}">
        <title>Redirecting…</title>
      </head>
      <body>
        <p>Redirecting to <a href="#{new_url}">#{new_url}</a>…</p>
      </body>
      </html>
    HTML

    path = File.join(site.dest, old_url, 'index.html')
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, redirect_html)
  end
end
