---
layout: post
title: "The aesthetics of Ruby - Kernel#itself method"
date: 2017-12-24 22:00
comments: true
categories: [Ruby, Design, Quick Tips]
---

Recently I've had quite a popular problem to solve: count the occurences of the given item in a collection. There are few ways to solve this problem - starting from using `Enumerable#inject` or `Enumerable#each_with_object` with an empty hash as an accumulator value and writing a code looking like this:

``` ruby
collection.each_with_object({}) { |item, accum| accum[item] = accum[item].to_i + 1 }
```

through a bit smarter way and taking advantage of the default hash value:

``` ruby
collection.each_with_object(Hash.new(0)) { |item, accum| accum[item] = accum[item] + 1 }
```

All these solutions look quite nice; however, there is one that looks particularly beautiful.

<!--more-->


## The Aesthetics of Ruby

An interesting way of solving this problem is by using `Enumerable#group_by` - we can simply group elements by themselves and count the occurences of each item. Here is one way to implement it:

``` ruby
collection.group_by { |item| item }.map { |key, value| [key, value.count] }.to_h
```

However, it doesn't look that great, especially for Ruby standard. We could do better. Ruby 2.4 adapted a very useful core extension from ActiveSupport: <a href="https://ruby-doc.org/core-2.4.0/Hash.html#method-i-transform_values" target="_blank">`Hash#transform_values`</a>. Thanks to this addittion, we could rewrite to the following code:


``` ruby
collection.group_by { |item| item }.transform_values(&:count)
```

Looks much better, but `group_by { |item| item }` could still be improved. Is there something in Ruby that could help us in such case?

It turns out there is! One of the additions in Ruby 2.2 was <a href="https://ruby-doc.org/core-2.2.0/Object.html#method-i-itself" target="_blank">`Kernel#itself`</a>, which simply returns self. It might sound like an odd idea to introduce such method, but this is exactly something that we need:

``` ruby
collection.group_by(&:itself).transform_values(&:count)
```

This code looks just beautiful.

## Wrapping up

Ruby code is known for being particularly pleasant to read and I'm still happy that after several years I still feel immense joy when I discover interesting little things like <a href="https://ruby-doc.org/core-2.2.0/Object.html#method-i-itself" target="_blank">`Kernel#itself`</a> which add up to the overall aesthetics of the language.
