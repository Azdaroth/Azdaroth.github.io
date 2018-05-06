---
layout: post
title: "The Case for before_validation callback: complex state normalization"
date: 2018-05-27 20:00
comments: true
categories: [Ruby, Rails, ActiveRecord Architecture]
---

A few months ago I wrote a [blog post](https://karolgalanciak.com/blog/2017/10/29/the-case-against-exotic-usage-of-before-validate-callbacks/) about **ActiveRecord** `before_validation` callback and how it is used for  **wrong reasons** and concluded that in most cases this is not something we should be using routinely. However, I missed one **appropriate use case** for it which might be quite common in Rails apps, so this might be an excellent opportunity to get back to  **before_validation callback** and show its other side.

<!--more-->

## Anatomy Of The Problem

Imagine that we have a `Payment` model where we need to store `amount` and `currency`. However, for statistical purposes, we also want to store normalized amount in USD currency with exchange rate applied at the time of payment's creation. As this is a significant part of our domain, we want to add validation for `amount_in_usd` attribute. Our Payment model looks like this at the moment:

``` rb
class Payment < ApplicationRecord
  validates :amount, :currency, :amount_in_usd, presence :true
end
```

The question is: where do we get `amount_in_usd` from and how can we assign it?

## The Solution

One way of solving that problem would be a direct assignment when populating all the attributes. In that case, it would look a bit like this:

``` rb
Payment.new(currency: currency, amount: amount, amount_in_usd: CurrencyExchanger.exchange(amount, from: currency, to: "USD"))
```

The problem with that solution is that this logic would need to be repeated in every place where payment gets initialized. We could implement a factory class that would be reused in all scenarios to keep it DRY, but that's some extra overhead that is not popular in a Rails world. Also, this sounds like a responsibility of the Payment model itself as it is about managing its internal state.

Here, we can't solve this by overriding writers as I suggested [before](https://karolgalanciak.com/blog/2017/10/29/the-case-against-exotic-usage-of-before-validate-callbacks/) as `amount_in_usd` depends on two attributes: `currency` and `amount`, and we don't know in which sequence the attributes will be assigned.

And this is exactly the case where `before_validation` is useful: for complex state normalization where multiple attributes are involved. With that callback, a solution looks quite elegant and just simpler:

``` rb
class Payment < ApplicationRecord
  validates :amount, :currency, :amount_in_usd, presence :true

  before_validation :assign_amount_in_usd

  private

  def  assign_amount_in_usd
    if currency && amount
      CurrencyExchanger.exchange(amount, from: currency, to: "USD")
    end
  end
end
```

## Alternative Solution

In the first paragraph, I mentioned that this solution could work especially well in Rails apps. What I meant by that is the fact that usually, the "primitive" attributes coming from HTTP params are mass-assigned to the model. Of course in Ruby, everything is an object, but to keep things simpler, let's treat numeric types and strings as these primitives.

What would be a non-primitive value though? In our case, we have something that is widely used as a typical example of a value object: **Money** object that is composed of `amount` and `currency`.  If the attributes before the assignment were mapped to some more domain-oriented objects, we would have an even simpler solution for our problem:

``` rb
money = Money.new(amount, currency)
Payment.new(money: money)
```

and the model would look like this:

``` rb
class Payment < ApplicationRecord
  validates :amount, :currency, :amount_in_usd, presence :true

  def money=(money_object)
    self.amount = money_object.amount
    self.currency = money_object.currency
    self.amount_in_usd = CurrencyExchanger.exchange_money(money_object, to: "USD")
  end
end
```

It might look like extra overhead that is not necessary. However, value objects tend to simplify and DRY a lot of things in the code, so for more complex apps, using value objects will be worth that extra overhead.

## Wrapping Up

There are some cases where `before_validation` callback might be useful. However, in more complex apps, using value object might be an alternative worth looking into.
