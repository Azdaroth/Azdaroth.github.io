---
layout: post
title: "Rails Quick Tips: Temporarily Disabling Touching with ActiveRecord.no_touching"
date: 2018-02-25 20:00
comments: true
categories: [Rails, Database, ActiveRecord, Quick Tips]
---

**Touching** **ActiveRecord models** is quite a common thing in most of the **Rails applications**, especially useful for cache invalidation. By default, it updates `updated_at` timestamp with the current time, Here's a typical example of using [touch](https://apidock.com/rails/ActiveRecord/Persistence/touch) in a model:

``` ruby
# app/models/photo.rb
class Photo < ApplicationRecord
  belongs_to :user, touch: true
end
```

Whenever a new photo is created, or the existing one is updated/destroyed, the `updated_at` attribute of the associated user will be updated with the current time. In the majority of the cases, this is the desired behavior (it's one of those rare ActiveRecord callbacks that is not that bad ;)). However, it might happen that you may not want `touch` to be executed for some reason. Is there any built-in solution that could solve that problem?

<!--more-->

## Anatomy Of The Problem

Temporarily disabling `touch`ing can useful either for performance reasons (when updating a large number of records) or simply to prevent `after_touch` or `after_commit` from being executed multiple times. The latter might indicate that there is a deeper problem in the design as putting any important logic causing side-effects beyond the record's internal state in those **ActiveRecord callbacks** can easily go south (especially if you trigger email notifications), but the reality is that a lot of Rails applications use those callbacks in such cases.

## The Solution

Fortunately, a heavy refactoring or a rewrite is not necessary. Instead, we can take advantage of [ActiveRecord.no_touching](http://api.rubyonrails.org/classes/ActiveRecord/NoTouching/ClassMethods.html) which temporarily disables touching inside the block.

Imagine that you need to update all photos belonging to some user and `touch` this user only after all photos are updated. Here's how it could be handled:

``` ruby
user = User.find(user_id)

ActiveRecord::Base.transaction do
  User.no_touching do
    user.photos.find_each do |photo|
      # user won't be `touch`ed
      photo.update!(some_attributes)
    end
  end

  user.touch
end
```

If for some reason disabling touching is necessary for all models, you could just call it on `ActiveRecord::Base`:

``` ruby
user = User.find(user_id)

ActiveRecord::Base.transaction do
  ActiveRecord::Base.no_touching do
    user.photos.find_each do |photo|
      # no model will be `touch`ed
      photo.update!(some_attributes)
    end
  end

  user.touch
end
```

And that's it!

## Summary

[`ActiveRecord.no_touching`](http://api.rubyonrails.org/classes/ActiveRecord/NoTouching/ClassMethods.html) is certainly a quick solution to a potentially tricky issue. However, it is also a dirty hack that indicates a potential problem with the design of the application that should be addressed sooner than later.
