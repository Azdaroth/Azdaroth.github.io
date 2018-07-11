---
layout: post
title: "Trolling In Ruby - Implementing JavaScript-like Maths With Implicit Conversion Hijacking"
date: 2018-07-29 20:00
comments: true
categories: [Ruby, Trolling]
---

If you've ever worked with **JavaScript**, especially in **pre-SPA/pre-frameworks** era with just **jQuery**, you probably had a chance to see an "exotic" maths in action that looks similar to this:

``` javascript
"3" + 4
// => "34"
```

That kind of behavior usually comes as a **big surprise** and due to that fact, JavaScript has gotten some **bad reputation** (even though there is a [rationale](https://karolgalanciak.com/blog/2017/01/22/javascript-the-surprising-parts/) behind it). If we tried that in **Ruby**, we would get an obvious `TypeError`:

``` ruby
"3" + 4
# => TypeError (no implicit conversion of Integer into String)
```

Would it be possible though to obtain the same result somehow in Ruby?

## Explicit Conversion vs. Implicit Conversion

The answer is yes! But before we get to the actual implementation of that concept, let's make sure that we understand some essential concepts in Ruby that will lead us there: **explicit conversion** and **implicit conversion**.

You've probably used methods like `to_s`, `to_i`, `to_d`, `to_a` etc. for *explicit* typecasting. That way, we can get the closest representation of a given object in a different type.

However, there is also a second type of conversion in Ruby, which is **implicit conversion**.  Those are the methods like `to_str`, `to_int`, `to_hash`, `to_ary`. In most cases, you should not use those methods unless you are implementing an object that kind of behaves like some type, so, e.g., all numeric objects could (and they actually do!) implement `to_int` method as they are kind of the same type. For the same reason, if we were implementing some type of collection, we could implement `to_ary` method that would just return the same result as `to_a`  which would be an instance of Array, but that we way put extra emphasis on the fact that this object behaves like an array.

We could also take advantage of implicit conversion to put some extra boundaries on the collaborating objects.  Implicit conversion is widely used in Ruby for that purpose. When you are adding a string to a string like this:

``` rb
"3" + "4"
```

Ruby under the hood calls "4".to_str to get the string representation of that object (which is already a string) to make `+` method more flexible, but at the same time, it makes sure that only string-like objects are permitted as arguments.

## Hijacking Implicit Conversion

Let's get back to the original problem which was: how to get the following result in Ruby?

``` ruby
"3" + 4
# => "34"
```
Based on what we've just learned about implicit conversion, we just need to make sure that integers become somehow string-like objects. Let's monkey patch `Integer` class and add `to_str` method that would be an alias to `to_s`:

```
class Integer
  def to_str
    to_s
  end
end
```

Let's try out crazy maths again:

``` ruby
"3" + 4
=> "34"
```

Try the same for JavaScript and compare the results, it should be exactly the same.

## Wrapping up

**Ruby** is an extremely **flexible** language which makes is it easy to do crazy things, just like it is the case with some operations in **JavaScript** ;).
