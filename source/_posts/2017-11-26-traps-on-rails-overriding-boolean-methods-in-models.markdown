---
layout: post
title: "Traps on Rails - Overriding boolean methods in models"
date: 2017-11-26 22:00
comments: true
categories: [Ruby, Ruby on Rails, Rails, Design, Quick Tips]
---

One very **useful** feature of **ActiveRecord** is automatically defining attribute readers and writers for all the columns for given tables. For the ones with **boolean** type, however, there is one more addition - defining an **alias** of the method with a question mark. Sometimes it might be useful to override this method and add some extra requirements for a given condition. However, this might not be such a good idea.

<!--more-->

## Anatomy of the problem

Imagine that you are developing some application, where users can be activated and deactivated from an admin panel. However, the application is not free, and every user that wants to access the application needs to buy a subscription. In that case, to check if the user is, in fact, active, you could override `User#active?` method and add some extra requirements regarding the subscription:

``` ruby app/models/users.rb
class User < ApplicationRecord
  def active?
    super && valid_subscription?
  end

  def valid_subscription?
    # somehow check if the subscription is valid
  end
end
```

We are taking advantage of the fact that ActiveRecord defines the aliases for boolean columns which are the original column names' ending with a question mark, so for `active` boolean column we can expect that `active?` method will be defined, and it will work the same as `active` method.

Ok, cool, we have out feature working and to check if a user is fully active, we call `User#active?` here and there. Our next requirement is exposing users in the API. Nothing too hard, we can add <a href="https://github.com/fotinakis/jsonapi-serializers">`jsonapi-serializers`</a> gem and implement fully JSONAPI-compliant serializers. It turns out that we need to expose if a user is active and not. Here is how our serializer could look like:

``` ruby app/serializers/user.rb
class UserSerializer
  include JSONAPI::Serializer

  attribute :active
  # other attributes
end
```

It sounds like we are done here. But the truth is there is a nasty bug here! The serializer returns the value returned by `User#active`, not by `User#active?`!


## What exactly went wrong here?

The most important thing that went work here was being lazy about the naming and not introducing proper domain concepts. Somehow ActiveRecord made it even easier - there was already a method called `active?` defined based on the `active` column name, so the only thing that was necessary in that case to make our first feature work was overriding it and adding some extra condition, because the idea of being "active" is kind of similar. But overriding boolean methods is never a good idea - it always implies that some concept is missing or is implicit in the code.

## A solution to the problem

A solution would be simply making this domain concept explicit. `User#active?` method doesn't check if the user is active is not, it rather checks if a user can access the application, so the better name for that method would be `User#can_access_application?`

It is quite possible that we might later need to add some extra features that are related to this feature, like checking if the user is active but cannot access the app or just simply checking the `active` flag itself. Our final model could look like this in the end:

``` ruby app/models/users.rb
class User < ApplicationRecord
  def can_access_application?
    active? && valid_subscription?
  end

  def cannot_access_application?
    !can_access_application?
  end

  # other methods
end
```

We should also update the serializer:

``` ruby app/serializers/user.rb
class UserSerializer
  include JSONAPI::Serializer

  attribute :active do
    object.active
  end

  attribute :can_access_application do
    object.can_access_application?
  end

  attribute :cannot_access_application do
    object.cannot_access_application?
  end
end
```

One could argue that this fix was not necessary and it was a developer's fault, and he or she should have checked the model if this method has not been overridden and adjust the serializer. That is somehow true, but if such code is deployed to production, it probably means that the reviewer of the code was not aware that there is a potential issue in the code and such things are really hard to spot - ActiveRecord adds those aliases for every boolean column so it might sound like a fair assumption that `User#active` and `User#active?` will return the same result.

However, the truth is that not only did we minimize the risk of having the name collisions by those changes, but we gained some extra flexibility, and it was quite straight-forward to differentiate between `User#active?`and `User#can_access_application?`. In a previous implementation, it was simply not possible with the question-mark methods.


## Wrapping up

Naming is one of <a href="https://martinfowler.com/bliki/TwoHardThings.html" target="_blank">two hard problems in computer science</a> and it's a good idea to always make all the domain concepts properly named and explicit, even if it means adding more code - just because something is not explicit, doesn't mean it doesn't exist. When it comes to **ActiveRecord** models, an extra caution is more than advisable - such models mix both persistence and domain concepts and it's quite easy to hurt yourself in such case. Not overriding boolean methods generated by ActiveRecord and properly naming things sounds like a good rule of thumb.
