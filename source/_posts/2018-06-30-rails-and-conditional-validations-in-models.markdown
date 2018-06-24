---
layout: post
title: "Rails And Conditional Validations In Models"
date: 2018-06-30 20:00
comments: true
categories: [Ruby, Rails, ActiveRecord, Design Patterns, Architecture]
---

Adding consents for accepting Terms of Service/Privacy Policies must have been a top popular feature in the majority of the applications due to enforcement of **GDPR** in May ;). From the technical aspects that GDPR requires, there is a proof of consent for processing the personal information. In that case, you need to have some actual attributes in the database that would confirm the fact that some user has indeed accepted Terms of Service/Privacy Policy.

That makes a significant impact on how we approach this kind of features. However, in the past, such things were quite often not stored in a database at all - it just took some UI **acceptance validation** or maybe a **validation of the virtual attribute** on the backend to be on the safe side.

Let's focus on the latter case and see what the possible solutions to that problems are. As **trivial** as this problem initially sounds, it will get **quite interesting** ;).

## Anatomy Of The Problem

We want to make sure a user accepts Terms of Service during the signup process and to be sure that it is indeed validated, even if JavaScript validation fails in UI, we want to validate that fact on the backend.

## Solution 1 - Just add a virtual attribute to the model and validate it

It is probably the most straightforward approach to that problem and most likely the least elegant. That's how we could implement it:

``` rb
# app/models/user.rb
class User < ApplicationRecord
  attr_accessor :terms_of_service_accepted

  validates :terms_of_service_accepted, acceptance: true
end
```

Well, it does work, no doubt about that. But currently, the validation will always be triggered, even during updates, which doesn't make much sense. We need to find a better solution.

## Solution 2 - Add a virtual attribute to the model and validate it only during the creation of a user

A minor improvement over the previous version, we make sure that the validation is not triggered by updates, but only when creating a user:

``` rb
# app/models/user.rb
class User < ApplicationRecord
  attr_accessor :terms_of_service_accepted

  validates :terms_of_service_accepted, acceptance: true, on: :create
end
```

Even if it solves the actual problem, there is a big issue about that - the validation will always be triggered during a creation, even when creating users from factories! What other options do we have?

## Solution 3 - Add a virtual attribute to the model and validate it only for a specific context

What is interesting in ActiveModel validations is that `on` option is not limited to `:create` or `:update` contexts - those are merely the ones that ActiveRecord sets by default depending on the persistence status of the model! We can provide a custom context for both `valid?` and `save` methods:

``` rb
user.valid?(:registration)
user.save(context: :registration)
```

In that case, we could replace `:create` context with `:registration` context for the acceptance validation:

``` rb
# app/models/user.rb
class User < ApplicationRecord
  attr_accessor :terms_of_service_accepted

  validates :terms_of_service_accepted, acceptance: true, on: :registration
end
```

However, this is still not ideal - a global model which is used in multiple contexts has some logic that only applies to just one use case, and what is even worse, it's for a UI concern.

Let's try to find a solution that doesn't add any unnecessary mess to a model.

## Solution 4 - Use form object

Using form object is probably the cleanest solution to our problem - we don't introduce any additional concerns to a model which should not be there, and we handle everything in a dedicated object. The are multiple ways how to implement a form object: we could create another ActiveModel model and take advantage of [ActiveModel Attributes](https://github.com/Azdaroth/active_model_attributes) to make it smoother. We could use [dry-validation](http://dry-rb.org/gems/dry-validation/basics/working-with-schemas/) gem for that. Or we could use my favorite tool for that purpose: [reform](https://github.com/trailblazer/reform) gem from [Trailblazer](http://trailblazer.to) stack.

Explaining the entire API of `reform` gem is way beyond the scope of this article, but the following implementation should be quite self-explanatory:

``` rb
# app/forms/user/registration_form.rb
require "reform/form/coercion"

class User::RegistrationForm < Reform::Form
  # other property declarations and validations

  property :terms_of_service_accepted, virtual: :true, type: Types::Form::Boolean

  validates :terms_of_service_accepted, acceptance: true
end
```

Besides handling other properties (most likely email, password and password confirmation), we are adding a virtual `terms_of_service_accepted` with explicit type and adding acceptance validation using ActiveModel validator.

Even though using form objects is the cleanest approach, it requires some extra overhead, especially with setup, and sometimes it might be painful to add that setup, especially when extending third party's logic, e.g. [devise_invitable](https://github.com/scambra/devise_invitable). In such case, we would need some heavy customization which could potentially break when updating a gem and we would also need extra test coverage for the custom solution. It might still be worth introducing a form object, but it would be a good idea to consider other potential solutions. What option do we have left?

## Solution 5 - Extend user's instance with a custom logic

Have you ever heard of DCI (Data Context Interaction) paradigm? If yes, you might have seen something like that:

``` rb
user = User.find(id)
user.extend(User::RegistrationContext)
```

What this code does is adding extra functionality from `User::RegistrationContext` module to user's singleton class. Effectively, it means that we are not adding any additional logic to all User class instances, but only to that particular instance. Sounds like exactly what we need! That way, we can solve our problem achieving all the other goals as well - ease of extending the logic without too much overhead and without making a mess in the model.

Here is how our implementation of `User::RegistrationContext` context module could look like:

``` rb
# app/models/user/registration_context.rb
module User::RegistrationContext
  def self.extended(model)
    class << model
      validates :terms_of_service_accepted, acceptance: true
    end
  end

  attr_accessor :terms_of_service_accepted
end
```

The interesting thing about this implementation is that there is some singletons' inception going on there - first, we are using `extend` itself on the model, and then, in `extended` module hook we are opening singleton class of the model and declaring validation there. However, this is necessary since `validates` method is not defined in the context of that module, and we need to do that in the context of the model.

Let's try our fancy solution in action:

``` rb
user = User.new
user.extend(User::RegistrationContext)
user.terms_of_service_accepted = "0"
user.valid?
=> false
user.errors.messages[:terms_of_service_accepted]
=> ["must be accepted"]
```

Perfect!

## Wrapping Up

There are multiple ways in Rails (or Ruby in general) to handle **conditional validation**, and thanks to the flexibility of the framework and the language, we can pick whatever seems best for our particular problem - from adding additional validations in a model with **extra ActiveModel context**, through using **form objects**, ending with arcane DCI-style object's extensions.


