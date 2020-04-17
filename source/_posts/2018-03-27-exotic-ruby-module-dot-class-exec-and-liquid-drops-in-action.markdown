---
layout: post
title: "Exotic Ruby: Module.class_exec, custom JSON And Liquid Drops In Action"
date: 2018-03-27 21:30
comments: true
categories: [Ruby, Design, Liquid, Metaprogramming]
---

Ruby has quite a lot of **"exotic" features** that are not used that often, but when you need to utilize some **metaprogramming magic**, you can easily take advantage of them. One of such features is [Object.instance_exec](http://ruby-doc.org/core-2.4.3/BasicObject.html#method-i-instance_exec) which you might be familiar with if you've ever built some more advanced DSL.

The great thing about `Object#instance_exec` is that it allows to execute code **within the context of a given object** but it also gives possibility to **pass arguments from the current context**. Thanks to that, we can build some nice DSLs and other features like this:

``` rb
role_filter = ->(role) { where(role: role) }
role = "admin"
User.all.instance_exec(role, &role_filter) # same as User.all.where(role: "admin")
```

An interesting thing is that there is a **class** equivalent of `Object#instance_exec` - [Module.class_exec](http://ruby-doc.org/core-2.4.3/Module.html#method-i-class_exec). It would be easy to figure out some theoretical example how it can be used but what could be the real-world use case where this is the best approach to solve the problem?

<!--more-->

## Anatomy Of The Problem

Imagine that you can have some custom JSON on every instance of some model and this JSON can have very different attributes on every instance depending on various conditions, like some category this model belongs to. To make it more complex, let's assume that the schema is customizable by the user so we can never really predict what kind of attributes are going to end up there.

Our feature to implement is to provide some wrapper class for this custom JSON so that we don't need to operate on hashes but we can have some objects where we can access these attributes by invoking methods on this object.

Using [OpenStructs](http://ruby-doc.org/stdlib-2.4.3/libdoc/ostruct/rdoc/OpenStruct.html) sounds like the quickest solution to the problem but this is not going to be that easy in our case - we will need to expose this class to be used with [Liquid](https://github.com/Shopify/liquid) templates, so that means we will need to inherit from [Liquid::Drop](https://github.com/Shopify/liquid/blob/4-0-stable/lib/liquid/drop.rb).

How about creating some `Wrapper` class that would take the `payload` as an argument and use [Object#define_singleton_method](http://ruby-doc.org/core-2.4.3/Object.html#method-i-define_singleton_method) in the constructor to define custom methods based on the keys and values in that payload? Defining singleton methods sounds like the right solution to the problem as indeed each instance might need different methods. Let's try that:

``` rb
# app/drops/wrapper.rb
class Wrapper < Liquid::Drop
  def initialize(payload)
    @payload = payload

    payload.each do |key, value|
      define_singleton_method key do
        value
      end
    end
  end
end
```

Looks like it might be the answer to the problem:

``` ruby
payload =  { ruby: "is freakin' awesome!" }
wrapper = Wrapper.new(payload)
wrapper.ruby
# => "is freakin' awesome!"
```

There is a huge problem with this solution though. These singleton methods are not going to be included in `Wrapper.public_instance_methods` array:

``` rb
Wrapper.public_instance_methods.include?(:ruby)
# => false
```

It might not be a big issue in some cases, but it won't work with [Liquid](https://github.com/Shopify/liquid) [Drop](https://github.com/Shopify/liquid/blob/4-0-stable/lib/liquid/drop.rb#L64-L76), which explicitly checks for `public_instance_methods`.

Do we have any alternative that would be the most robust solution to this problem?

## The Solution

The answer is yes! Although, the solution is going to be more tricky than the previous one.

First, we will need to take advantage of using the constructor of `Class` itself and create anonymous classes inheriting from `Liquid::Drop`. The next step would be defining the required methods based on `payload`. But how can we do that if `payload` is not available in the context of this class? We will need to make it available somehow and execute the code within the context of this class.

Fortunately, Ruby has got our back, and we can take advantage of [Module.class_exec](http://ruby-doc.org/core-2.4.3/Module.html#method-i-class_exec) method which does exactly what we need here.

Here is a potential implementation:

``` rb
payload =  { ruby: "is freakin' awesome!" }
magic_drop_class = Class.new(Liquid::Drop)
magic_drop_class.class_exec(payload) do |payload|
  payload.each do |key, value|
    define_method key do
      value
    end
  end
end
example = magic_drop_class.new
example.ruby
# => "is freakin' awesome!"
```

And what about `public_instance_methods`?

``` ruby
magic_drop_class.public_instance_methods.include?(:ruby)
# => true
```

That means we've managed to achieve our goal!

## Wrapping Up

Ruby is widely known for **being powerful** and allowing to easily do all kinds of things to objects, including **modifying them on fly** and **executing the code within their context**.  Thanks to that and uncommon methods like [Module.class_exec](http://ruby-doc.org/core-2.4.3/Module.html#method-i-class_exec), we can solve some **tricky and rare problems** with a very **elegant solutions**.
