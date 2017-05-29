---
layout: post
title: "Ruby Memoization: ||= vs. defined? syntax"
date: 2017-05-28 22:00
comments: true
categories: [Ruby, Quick Tips]
---

In the majority of the **Rails applications** or even **Ruby gems** you can find a lot of use cases where you need to **memoize** a result of some computation for performance benefits and to not compute it again if this result has already been computed. Seems like doing the assignment to some instance variable with `||=` operator is the most commonly used solution for this purpose, e.g. `@result ||= do_some_heavy_computation`. However, there are some cases where it might not produce the expected outome and you should actually use `defined?` operator instead.

<!--more-->

## What Is `||=` operator?

Let's get back to the example from the introduction: `@result ||= do_some_heavy_computation`. What is this `||=` operator and how does it work? <del>It's nothing more than a **syntactic shortcut** and it's an equivalent of @result || @result = do_some_heavy_computation</del> Edit: It's very close to `@result || @result = do_some_heavy_computation`, but <a href="http://www.rubyinside.com/what-rubys-double-pipe-or-equals-really-does-5488.html" target="_blank">not exactly the same</a> which translates to: "return the value of `@result` if the value is truthy or assign the result of `do_some_heavy_computation` to `@result`". Clearly, the shortcut version looks more appealing. Keep in mind though that it's not really about already assigning some value to the instance variable, but rather if the value of it is truthy or not. How do we check then if the instance variable has already been set knowing that referring to undefined instance variable will simply result in `nil` without any exceptions?

## What Is `defined?` operator?

We can do that by using `defined?` opeator, which returns `nil` if its argument is not defined or, if it is defined, the description of that argument. Thanks to that behaviour, we can easily check if some instance variable has already been set or not:

``` ruby
defined?(@result) // => nil

@result = nil
defined?(@result) // => "instance-variable"
```

## Memoization gotcha

Ok, we now understand the difference between `||=` and `defined?` operators, why should we bother in the context of memoization?

Imagine that you have a following method in some object:

``` ruby
def heavy_computation_result
  @result ||= do_some_heavy_computation
end
```

and you are calling `heavy_computation_result` method multiple times to reuse the result of the computation. Certainly, this computation is heavy (as the name suggests) and ideally it should be computed only once for the performance reasons. What if this computation returns `nil` or `false`?

<del>As @result ||= do_some_heavy_computation is nothing more than a shortcut of @result || @result = do_some_heavy_computation expression</del> Edit: As `@result ||= do_some_heavy_computation` works in a <a href="http://www.rubyinside.com/what-rubys-double-pipe-or-equals-really-does-5488.html" target="_blank">pretty similar way</a> to  `@result || @result = do_some_heavy_computation` expression, the left side will be falsey in such case and the computation will be performed every time you call `heavy_computation_result` method making this syntax useless here!

For the **proper memoization**, this method should be rewritten using `defined?` operator:

``` ruby
def heavy_computation_result
  return @result if defined?(@result)
  @result = do_some_heavy_computation
end
```

## Wrapping Up

Even though `||=` operator is commonly used for memoization, it isn't necessarily the best solution to this problem. It is certainly quite convenient to use, nevertheless, when there is a possiblity of having **falsey values** such as `false` and `nil`, it is much safer to use `defined?` operator instead.
