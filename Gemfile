source "https://rubygems.org"

# ---------------------------------------------------------------------------
# Jekyll version: DO NOT upgrade to Jekyll 4 without also moving GitHub Pages
# to a GitHub Actions build.
#
# This site publishes through classic GitHub Pages (build_type: legacy, source
# branch master). GitHub builds it server-side with its OWN Jekyll 3.9.5 and
# ignores this Gemfile. The `github-pages` gem exists to mirror that server
# build locally, which is why Jekyll is pinned at 3.9.5 here.
#
# Putting Jekyll 4 in this file does not change what GitHub publishes. It only
# makes the local build stop matching the published one.
#
# Jekyll 4.4.1 was tested on 2026-09-08 and is clean: 155 pages, syntax
# highlighting intact (Rouge 4 reclassifies 11 tokens, all already styled),
# and it fixes the twitter:title meta tag. The move is a platform decision,
# not a dependency bump.
# ---------------------------------------------------------------------------
# Hello! This is where you manage which Jekyll version is used to run.
# When you want to use a different version, change it below, save the
# file and run `bundle install`. Run Jekyll with `bundle exec`, like so:
#
#     bundle exec jekyll serve
#
# This will help ensure the proper Jekyll version is running.
# Happy Jekylling!
# gem "jekyll", "~> 3"
# This is the default theme for new Jekyll sites. You may change this to anything you like.
gem "minima", "~> 2.5"
# If you want to use GitHub Pages, remove the "gem "jekyll"" above and
# uncomment the line below. To upgrade, run `bundle update github-pages`.
# gem "github-pages", group: :jekyll_plugins
# If you have any plugins, put them here!
group :jekyll_plugins do
  gem "jekyll-feed", "~> 0.12"
  gem "jekyll-compose"
  gem "jekyll-seo-tag"
  gem "github-pages"
  gem "jekyll-paginate-v2"
  gem "pygments.rb"
  gem "kramdown"
  gem "redcarpet"
  gem "jekyll-sitemap"
end

# Windows and JRuby does not include zoneinfo files, so bundle the tzinfo-data gem
# and associated library.
install_if -> { RUBY_PLATFORM =~ %r!mingw|mswin|java! } do
  gem "tzinfo", "~> 1.2"
  gem "tzinfo-data"
end

# Performance-booster for watching directories on Windows
gem "wdm", "~> 0.1.1", :install_if => Gem.win_platform?
gem "webrick"

# Ruby 3.4 moved these out of the default gems. Jekyll 3.9.x and several
# github-pages dependencies still `require` them without declaring them, so the
# build dies with `cannot load such file -- csv` unless they are listed here.
# Harmless on older Rubies, and irrelevant to the GitHub Pages server build.
gem "csv"
gem "logger"
gem "base64"
gem "bigdecimal"
gem "ostruct"
gem "mutex_m"
