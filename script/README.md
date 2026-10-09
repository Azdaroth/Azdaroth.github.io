# Website checks

Run with the Ruby version in `.ruby-version` and the installed bundle:

```sh
bundle exec ruby script/check.rb
```

This builds the site in a temporary directory and fails if an internal category
link has no generated destination. The temporary build is removed afterwards;
the local `_site` preview is left untouched. Add a category page under
`blog/categories/<slug>/index.html` whenever a post introduces a new category.
Category labels must match the page's `category` value, including capitalization.
