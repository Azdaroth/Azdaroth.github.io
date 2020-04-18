---
layout: post
title: "Refactoring Tips: Trade Conditionals For Type Delegation"
date: 2016-01-06 23:20
comments: true
categories: [Ruby on Rails, Rails, Ruby, Refactoring, Design Patterns, Architecture]
---

<p>Having some kind of <code>type</code> attribute in your models is a pretty common thing, especially in applications with more complex domain. How do you handle such cases? Is it with multiple conditionals / <code>case</code> statements in every method dealing with the type attribute? If you've been struggling with organizing and maintaing code for such use cases then say hello to your new friend: type delegation.</p>

<!--more-->

<h2>Type attribute - common approach</h2>

<p>Imagine you have some <code>Subscription</code> model with <code>type</code> and <code>charged_at</code> columns. Let's assume that the possible values for <code>type</code> column are <code>daily</code>, <code>weekly</code>, <code>monthly</code> and <code>yearly</code>. Now let's add couple of methods: next charge date, subscription price and maybe eligible discount which is going to depend on the subscription type as well. To make it a bit more complex let's assume that for <code>yearly</code> subscription the user needs to select some kind of <code>bonus</code>. The common approach to this problem would be the following:</p>

``` ruby
class Subscription < ActiveRecord::Base
  validate :bonus_id, presence: true, if: -> subscription { subscription.eligible_for_bonus? }

  def next_charge_at
    charged_at.advance(days: subscription_days)
  end

  def price
    base_daily_price * subscription_days - discount
  end

  def discount
    case type
    when "daily"
      0
    when "weekly"
      100
    when "monthly"
      500
    when "yearly"
      10000
    end
  end

  private

  def base_daily_price
    100
  end

  def subscription_days
    case type
    when "daily"
      1
    when "weekly"
      7
    when "monthly"
      30
    when "yearly"
      365
    end
  end

  def eligible_for_bonus?
    return true if type == "yearly"
    false
  end
end
```

<p>This class is quite short, but already suffers from the conditionals in many places and as the logic grows, the <code>case</code> and <code>if</code> statements are going to be in even more places, which will be a maintenance nightmare. Are there any ways we could make it better?</p>

<p>The simplest one would be probably using a hash instead of <code>case</code> or <code>if</code> statements. Here's one example for <code>discount</code>:</p>

``` ruby
class Subscription < ActiveRecord::Base
  TYPES_DISCOUNTS_MAPPING = {
    daily: 0,
    weekly: 100,
    monthly: 500,
    yearly: 10000
  }.freeze

  def discount
    TYPES_DISCOUNTS_MAPPING.fetch(type.to_sym)
  end
end
```

<p>It looks better than conditionals, but the idea is still the same. It may also grow too complex when you don't return a simple value based on the type, but perform some computations which would mean having lambdas as a return value per type.</p>

<p>For a real change we could introduce more object-oriented techniques. How about polymorphism and delegation? Every type of subscription looks like a separate concept, maybe we could encapsulate logic related to each type in the separate classes implementing the same interface? That way we would reduce the number of conditionals in all possible cases to just one - in the method where we actually return the type class for given subscription type. Let's see how it works in practice:</p>

``` ruby
class Subscription < ActiveRecord::Base
  TYPES_CLASSES_MAPPING = {
    daily: DailySubscription,
    weekly: WeeklySubscription,
    monthly: MonthlySubscription,
    yearly: YearlySubscription
  }.freeze

  validate :bonus_id, presence: true, if: -> subscription { subscription.eligible_for_bonus? }

  delegate :discount, :subscription_days, :eligible_for_bonus?, to: :type_class

  def next_charge_at
    charged_at.advance(days: subscription_days)
  end

  def price
    base_daily_price * subscription_days - discount
  end

  private

  def type_class
    TYPES_CLASSES_MAPPING.fetch(type.to_sym).new
  end

  def base_daily_price
    100
  end

  class DailySubscription
    def discount
      0
    end

    def subscription_days
      1
    end

    def eligible_for_bonus?
      false
    end
  end

  class WeeklySubscription
    def discount
      100
    end

    def subscription_days
      7
    end

    def eligible_for_bonus?
      false
    end
  end

  class MonthlySubscription
    def discount
      500
    end

    def subscription_days
      30
    end

    def eligible_for_bonus?
      false
    end
  end

  class YearlySubscription
    def discount
      10000
    end

    def subscription_days
      365
    end

    def eligible_for_bonus?
      true
    end
  end
end
```

<p>Now each type is a separate domain concept and it's really simple to extend any logic based on the type: we would just need to add a method to every class without worrying about ugly conditionals and simply delegate the method call to <code>type_object</code> using <code>delegate</code> macro from ActiveSupport.</p>

<p>You may be wondering whether it actually improved design as there's more code and classes. The answer is still yes: the object-orientation is all about interaction between many objects and identifying domain concepts almost always result in larger, but more explicit and easier to maintain codebase.</p>

<h2>Wrapping up</h2>

<p>Type delegation is a simple technique aimed for eliminating conditional logic in different methods that depend on some <code>type</code> attribute and making code much easier to maintain and extend.</p>
