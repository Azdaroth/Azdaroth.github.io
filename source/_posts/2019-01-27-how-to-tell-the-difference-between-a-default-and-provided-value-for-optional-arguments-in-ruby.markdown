---
layout: post
title: "How to tell the difference between a default and a provided value for optional arguments in Ruby?"
date: 2019-01-27 19:00:00
comments: true
categories: [Ruby, Quick Tips]
---

It is sometimes required for the methods with optional arguments to be able to differentiate between its default value and the value passed from the caller. Passing `nil` might initially sound like a good idea since it represents "nothingness". However, it might turn out that `nil` is a legit value and there might be cases where it is desirable for the caller to pass `nil`. In such a case, we cannot use it as a default value if we want to implement a special logic for the case of not providing that value.

Fortunately, there is an easy way to deal with it: use a special constant:

``` rb
class SomeClass
  NO_VALUE_PROVIDED = Object.new
  private_constant :NO_VALUE_PROVIDED

  def call(argument: NO_VALUE_PROVIDED)
    if argument == NO_VALUE_PROVIDED
      handle_scenario_for_no_value_provided
    else
      do_something_with_argument(argument)
    end
  end
end
```

In `call` method, we allow to pass an optional argument with a default of `NO_VALUE_PROVIDED`, which is a private constant defined in that class that is an instance of `Object`.

By depending on the instance of `Object` that is initialized inside that class, we can avoid cases where the equality check returns `true` even if this is not an expected outcome, which could happen if we used strings or symbols. We could use some symbol that would be very unlikely to be passed from the caller, like `:__no_value_provided__,` but it arguably looks more like a workaround than a dedicated solution for the problem.

Also, a private constant ensures it is not used anywhere outside the class, which minimizes the chances that the passed argument would the same as our placeholder for no-value-provided scenario even more.
