---
layout: post
title: "The Case Against Exotic Usage of :before_validate Callbacks"
date: 2017-10-29 22:00
comments: true
categories: [Ruby, Rails, ActiveRecord Architecture]
---

It's nothing new that **ActiveRecord callbacks** are abused in many projects and used for the wrong reasons for many use cases where they can be **easily avoided** in favour of a much better alternative, like service objects. There is one callback though that is special and quite often used for pretty **exotic reasons** that have nothing to do with the process when it gets executed - it's the `before_validate` callback.

<!--more-->

## Data Formatting

Data formatting is something pretty common in the majority of the applications, especially stripping strings. Imagine that you need to strip some `URL` so that any potential spaces won't cause any issues. How would you approach that?

One way would be to use `before_validate` callback, especially if you have some format validations:

``` ruby app/models/my_model.rb
class MyModel
  before_validate :strip_url

  private

  def strip_url
    self.url = url.to_s.strip
  end
end
```

It definitely gets the job done. However, how would you test it? You would need to call `valid?` method on the model to check that... `URL` is stripped? Sounds quite funny and is even better when you look at the potential spec:

``` ruby spec/models/my_model_spec.rb
require "rails_helper"

RSpec.describe MyModel, type: :model do
  it "strips URL before validation" do
    model = MyModel.new(url: "  http://rubyonrails.org")

    model.valid?

    expect(model.url).to eq "http://rubyonrails.org"
  end
end
```

Really unlikely that this would be the result of **TDD** ;). What's the alternative then?

How about just using attribute writer for that? So something like this:

``` ruby app/models/my_model.rb
class MyModel
  def url=(val)
    super(val.to_s.strip)
  end
end
```

And here is a potential spec for this feature:

``` ruby spec/models/my_model_spec.rb
require "rails_helper"

RSpec.describe MyModel, type: :model do
  it "strips URL" do
    model = MyModel.new(url: "  http://rubyonrails.org")

    expect(model.url).to eq "http://rubyonrails.org"
  end
end
```

Both the implementation and spec are much simpler and just more natural - data formatting has nothing to do with the validation, there is no need to use a callback related to validation to handle such use case.

## Populating attributes and relationships

Another popular scenario is assigning attributes and relationships. Imagine you are creating a comment with a `content`, an author who will be `current_user` and also want to do some denormalization for performance reasons and directly assign `group` to this comment to which `current_user` belongs to. Here is how it is sometimes handled with `before_validate` callback:

``` ruby
Comment.create!(
  content: content,
  author: current_user,
)
```

``` ruby app/models/my_model.rb
class MyModel
  before_validate :assign_group

  private

  def assign_group
    self.group = current_user.group
  end
end
```

It's quite similar to the previous use case with data formatting - to write a test for this feature, we would need again to call `valid?` which doesn't make much sense, validation has nothing to do with populating attributes or relationships. There is much simpler and much more explicit way to handle it:

``` ruby
Comment.create!(
  content: content,
  author: current_user,
  group: current_user.group,
)
```

There is no magic here - just a simple assignment, which is easy to test and understand.

## Wrapping up

Maybe there are some scenarios where `before_validate` callback is the best possible choice (I'm yet to find them though), but I'm pretty sure data formatting or populating attributes/associations are not valid use cases to use it for.
