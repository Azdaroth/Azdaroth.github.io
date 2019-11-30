---
layout: post
title: "Do. Or do not. There is no try - Object#try considered harmful"
date: 2017-09-24 22:00
comments: true
categories: [Ruby, Rails, Design Patterns, Architecture]
---

<a href="https://apidock.com/rails/v4.2.7/Object/try" target="_blank">`Object#try`</a> is quite a commonly used method in **Rails applications** to cover cases where there is a possibility of dealing with a `nil` value or to provide **flexible interface** for handling cases where some kind of object doesn't necessarily implement given method. Thanks to `try`, we may avoid getting `NoMethodError`. So it seems like it's perfect, right? No `NoMethodError` exception, no problem?

Well, not really. There are some **severe problems** with using `Object#try`, and usually, it's quite easy to implement a solution that would be much better.

<!--more-->

## Object#try - how does it work?

The idea behind `Object#try` is simple: instead of raising `NoMethodError` exception when calling some method on `nil` or calling a method on non-`nil` object that is not implemented by this object, it just returns `nil`.

Imagine that you want to grab the email of the first user. To make sure it won't blow up when there are no users, you could write it the following way:

```
user.first.try(:email)
```

What if you implemented some generic service where you can pass many types of objects and, e.g., after saving the object it attempts to send a notification if the object happens to implement a proper method for that? With `Object#try` it could be done like this:

``` rb
class MyService
  def call(object)
    object.save!
    object.try(:send_success_notification, "saved from MyService")
  end
end
```

As you can see, it is also possible to provide `arguments` of the method.

What if you need to do some chaining of the methods where you can get `nil` at each intermediate step? No problem, you can use `Object#try`:

``` rb
payment.client.try(:addresses).try(:first).try(:country).try(:name)
```

## What is the problem then?

Apparently, `Object#try` is capable of handling multiple cases, so what is the problem with using it?

Well, there are many. The biggest issue with `Object#try` is that in many cases it `solves` problems that should never happen in the first place and that problem is `nil`. The another one is that the intention of using it is not clear. What does the following code try to say?

``` rb
payment.client.try(:address)
```

Is it a legit case that some payment might not have a client and indeed it could be `nil`? Or is added "just in case" if `client` happens to be `nil` to not blow up with `NoMethodError` exception? Or even worse, does `client` happen to be a polymorphic relationship where some models implement `addresses` method and the others don't? Or maybe there is a problem with data integrity, and for a few payments the client was deleted for some reason, and it's no longer there?

Just by looking at this code it is impossible to tell what's the intention of `Object#try`, there are just too many possibilities.

Fortunately, there are plenty of alternative solutions that you can apply to get rid of `Object#try` and make your code clear and expressive - thanks to that, it will be much more maintainable, more readable and less prone to bugs as the intention will no longer be ambiguous.

## Alternative solutions

Here are few "patterns" you could apply depending on the context where `Object#try` is used.

### Respecting Law of Demeter

<a href="https://en.wikipedia.org/wiki/Law_of_Demeter" target="_blank">Law of Demeter</a> is a handy rule (I wouldn't go that far to call it a "law" though) which helps avoid structural coupling. What it states is that hypothetical object A should be only interested in its own immediate surrounding and should not be aware of the internal structure of its collaborators or associations. In many cases, it means having only one "dot" in method calls. However, **Law of Demeter** is not really about the amount of "dots" (method calls), it's only about the coupling between objects, so chained operations and transformations are perfectly fine, e.g., the following example doesn't violate the law:

``` rb
input.to_s.strip.split(" ").map(&:capitalize).join(" ")
```

but the following one does:

``` rb
payment.client.address
```

Respecting **Law of Demeter** usually results in a clean and maintainable code, so unless you have a good reason to violate it, you should stick to the law and avoid tight coupling.

Let's get back to the example with `payment`, `client` and `address`. How could we refactor the following code?

``` rb
payment.client.try(:address)
```

The first thing would be to reduce structural coupling and implement `Payment#client_address` method:

``` rb
class Payment
  def client_address
    client.try(:address)
  end
end
```

It's much better now - instead of referring to the address via `payment.client.try(:address)` we can simply do `payment.client_address`, which is already an improvement as `Object#try` happens only in one place. Let's refactor it further.

We are left now with two options: either `client` being `nil` is a legit case or not. If it is, we can make the code look confident and explicitly return early, which clearly shows that having no `client` is a valid use case:

``` rb
class Payment
  def client_address
    return nil if client.nil?

    client.address
  end
end
```

If it never happens to be `nil`, we can skip the guard statement:

``` rb
class Payment
  def client_address
    client.address
  end
end
```

Such delegations are pretty generic; maybe Rails has some nice solution to this problem? The answer is "yes"! `ActiveSupport` offers a very nice solution to the exact issue: <a href="http://api.rubyonrails.org/classes/Module.html#method-i-delegate" target="_blank">`ActiveSupport#delegate`</a> macro. Thanks to that macro, you can define delegations and even handle `nil` in the exact way we did it.

The first example, where `nil` is a legit use case, could be rewritten the following way:

``` rb
class Payment
  delegate :address, to: :client, prefix: true, allow_nil: true
end
```

and the second one, if `nil` is never to be expected:

``` rb
class Payment
  delegate :address, to: :client, prefix: true
end
```

Much cleaner, less coupled and we've managed to achieve the final result of not using `Object#try`, but just in a much more elegant way.

However, it is still possible that we might not expect payment to have an empty client (e.g. payment for the transaction that is not completed yet) in some cases, e.g., when displaying data for the payments with completed transactions, but somehow we are getting dreaded `NoMethodEror` exception. It doesn't necessarily mean that we need to add `allow_nil: true` option in `delegate` macro and for sure it doesn't mean that we should use `Object#try`. The solution here would be:

### Operating on the scoped data

If we want to deal payments with completed transactions, which are guaranteed to have `client`, why not simply make sure that we are dealing with the right set of data? In Rails apps that would probably mean applying some ActiveRecord `scope` to `Payment`s collection, like `with_completed_transactions`:

``` rb
Payment.with_completed_transactions.find_each do |payment|
  do_something_with_address(payment.client_address)
end
```

Since we never plan to do anything with client's `address` for payments for not completed transactions, we don't need to explicitly handle `nil`s here.

Nevertheless, even if `client` were always required for creating a payment, it would still be possible that such code might result in `NoMethodError`. One example where that might happen would be a deleted by mistake associated `client` record. In that case, we would need to fix:

### Data integrity

Ensuring data integrity, especially with RDBMS like PostgreSQL, is quite simple - we just need to remember about adding the right constraints when creating new tables. Keep in mind that this needs to be handled on a database level, validations in models are never enough as they can easily be bypassed. To avoid the issue where `client` turns out to be `nil`, despite presence validation, we should add `NOT NULL` and `FOREIGN KEY` constraints when creating `payments` table, which will prevent us from not having a client assigned at all and also deleting the client record if it's still associated with some payment:

``` rb
create_table :payments do |t|
  t.references :client, index: true, foreign_key: true, null: false
end
```

And that's it! By remembering about those constraints, you can avoid a lot of unexpected use cases with `nil`s.

### Ensuring types via explicit conversion

I saw few times `Object#try` used in a quite exotic way which looked similar to this:

``` rb
params[:name].try(:upcase)
```

Well, this code clearly shows that some string is expected to be found under `name` key in `params`, so why not just ensure it is a string by applying explicit conversion using `to_s` method?

``` rb
params[:name].to_s.upcase
```

Much cleaner that way!

However, those two codes are not equivalent. The former one returns a string if `params[:name]` is a string, but if it is `nil`, it will return `nil`. The latter always returns a string. It is not entirely clear if `nil` is expected in such case (which is the obvious problem with `Object#try`), so we are left with two options:

* `nil` is the expected return value if `params[:name]` is `nil` - might not be the best idea as dealing with nils instead of strings might be quite inconvenient, however, in some cases, it might be necessary to have `nil`s. If that's the case, we can make it clear that we expect `params[:name]` to be `nil` by adding a guard statement:

``` rb
return if params[:name].nil?

params[:name].to_s.upcase
```

* a string is the expected return type - we don't need to bother with guard statements, and we can just keep the explicit conversion:

``` rb
params[:name].to_s.upcase
```

In more complex scenarios, it might be a better idea to use form objects and/or have a more robust types management, e.g. by using <a href="https://github.com/dry-rb/dry-types" target="_blank">dry-types</a>, but the idea would still be the same as for explicit conversions, it would just be better as far as the design goes.

### Using right methods

Dealing with nested hashes is quite a common use case, especially when building APIs and dealing with user-provided payload. Imagine you are dealing with JSONAPI-compliant API and want to grab client's name when updating. The expected payload might look like this:

``` rb
{
  data: {
    id: 1,
    type: "clients",
    attributes: {
      name: "some name"
    }
  }
}
```

However, since we never know if the API consumer provided a proper payload or not, it would make sense to assume that the structure won't be right.

One terrible way to handle it would be using... guess what? Obviously `Object#try`:

``` rb
params[:data].try(:[], :attributes).try(:[], :name)
```

It's certainly hard to say that this code looks pleasant. And the funny thing is that it is really easy to rewrite cleanly.

One solution would be applying explicit conversions on each intermediate step:

``` rb
params[:data].to_h[:attributes].to_h[:name]
```

That's better, but not really expressive. Ideally, we would use some dedicated method. One of those potentially dedicated methods is <a href="https://ruby-doc.org/core-2.2.0/Hash.html#method-i-fetch" target="_blank">`Hash#fetch`</a> which allows you to provide a value that should be returned if the given key is not present in the hash:

``` rb
params.fetch(:data).fetch(:attributes, {}).fetch(:name)
```

It looks even better but would be nice to have something even more dedicated for digging through nested hashes. Fortunately, since Ruby 2.3.0, we can take advantage of <a href="http://ruby-doc.org/core-2.3.0_preview1/Hash.html#method-i-dig" target="_blank">`Hash#dig`</a>, which was implemented for exactly this purpose - digging through nested hashes and not raising exceptions if some intermediate key turns out to not be there:

``` rb
params.dig(:data, :attributes, :name)
```

### Having Proper interfaces / Duck typing

Let's get back to the example that was mentioned in the beginning with sending a potential notification:

``` rb
class MyService
  def call(object)
    object.save!
    object.try(:send_success_notification, "saved from MyService")
  end
end
```

There are two possible solutions here:

* **Implementing two set of services** - one that sends notifications and one that doesn't:

``` rb
class MyServiceA
  def call(object)
    object.save!
  end
end

class MyServiceB
  def call(object)
    object.save!
    object.send_success_notification("saved from MyService")
  end
end
```

Thanks to this refactoring, the code is much cleaner, and we easily got rid of `Object#try`. However, now we need to know that for one type of objects we need to use `MyServiceA` and for another type `MyServiceB`. It might make sense, but might also be a problem. In such case the 2nd option would be better:

* **Duck typing**. Simply add `send_success_notification` method to all objects that are passed to `MyService` and if it's supposed to do nothing, just leave the method body empty:

``` rb
class MyService
  def call(object)
    object.save!
    object.send_success_notification("saved from MyService")
  end
end
```

The extra benefit of this option is that it helps to identify some common behaviors of the objects and to make them explicit. As you can see, in case of `Object#try` a lot of domain concepts might stay implicit and unclear. It doesn't mean they are not there; they are just not clearly identified. This is yet another important thing to keep in mind - `Object#try` also hurts your domain.

### Null Object Pattern

Let's reuse the example above with sending notifications after persisting some models and do a little modification - we will make `mailer` an argument of the method and call `send_success_notification` on it:

``` rb
class MyService
  def call(object, mailer: SomeMailer)
    object.save!
    mailer.send_success_notification(object, "saved from MyService")
  end
end
```

That's going to work great if we always want to send a notification. What if we don't want to do it? One terrible way to handle it would be passing `nil` as a mailer and take advantage of `Object#try`:

``` rb
class MyService
  def call(object, mailer: SomeMailer)
    object.save!
    mailer.try(:send_success_notification, object, "saved from MyService")
  end
end


Service.new.call(object, mailer: nil)
```

But you've probably already guessed this solution is a no-go. Fortunately, we can apply <a href="https://en.wikipedia.org/wiki/Null_Object_pattern" target="_blank">Null Object Pattern</a> and pass an instance of some `NullMailer` which implements `send_success_notification` method that simply does nothing:

``` rb
class NullMailer
  def send_success_notification(*)
  end
end

class MyService
  def call(object, mailer: SomeMailer)
    object.save!
    mailer.send_success_notification(object, "saved from MyService")
  end
end

MyService.new.call(object, mailer: NullMailer.new)
```

That's certainly better than using `Object#try`.

## What about `&.` a.k.a. lonely/safe navigation operator?

`&.`, lonely/safe navigation operator is a pretty new thing introduced in Ruby 2.3.0. It's quite similar to `Object#try`, but it's less ambiguous - if you call a method on the object different than `nil`, and this method is not implemented by that object, `NoMethodError` will still be raised which is not the case for `Object#try`. Check the following examples:

``` rb
User.first.try(:unknown_method) # assuming `user` is nil
=> nil

User.first&.unknown_method
=> nil

User.first.try(:unknown_method!) # assuming `user` is not nil
=> nil

User.first&.unknown_method
=> NoMethodError: undefined method `unknown_method' for #<User:0x007fb10c0fd498>
```

Does it mean safe navigation operator is fine and safe to use? Not really. It still comes with the same problems as `Object#try` does, it's merely one serious issue less.

Nevertheless, I think there is a case where the lonely operator is not that bad. Check the following example:

``` rb
Comment.create!(
  content: content,
  author: current_user,
  group_id: current_user&.group_id,
)
```

What we want to do is create a comment belonging to some `current_user` who might be an author and also assign a `group_id` from `current_user`, who might be nil.

The same code could be written as:

``` rb
Comment.create!(content: content, author: current_user) do |c|
  c.group_id = current_user&.group_id if current_user
end
```

or maybe as:

``` rb
comment_params = {
  content: content,
  author: current_user,
}

comment_params[:group_id] = current_user.group_id if current_user

Comment.create!(comment_params)
```

But I think neither of those alternatives is more readable than the first example with `&.` operator, so might be worth trading a bit of clarity for more readability.


## Wrapping Up

I believe there is not a single valid use case for `Object#try` due to the **ambiguity** of its intentions, **negative impact** on the **domain** model and simply for the fact that there are **many other ways** to solve the problems that `Object#try` "solves" in a clumsy way - starting from respecting Law of Demeter and delegations, through operating on properly scoped data, applying right database constraints, ensuring types using explicit conversions, using proper methods, having right interfaces, taking advantage of duck typing, ending with Null Object Pattern  or even using the safe navigation operator (`&.`) which is much safer to use and might be applied in limited cases.

{% img /images/object_try/yoda.jpeg 'yoda' 'yoda' %}

<p class="small-p center">
  Source: https://www.pbnsg.org/weight-management/2015/7/27/do-or-do-not-there-is-no-try-yoda
</p>

