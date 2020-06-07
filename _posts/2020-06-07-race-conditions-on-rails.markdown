---
layout: post
title: "Race Conditions on Rails"
date: 2020-06-07 20:00
comments: true
categories: [Ruby, Rails, Ruby on Rails, Race Conditions, ActiveRecord]
---

Imagine that you are implementing a payment processing system for the e-commerce system and discover that multiple customers were **charged twice** for exactly the same order. Ouch... Sounds like a real **nightmare** to deal with! And the next day, you see that something is not right with the credits system in which users were able to pay using special credits instead of using credit card - somehow instead of getting charged $100 in total for two orders of $25 and $75, they were charged just 25$! And to make it even more epic, it turned out that the **uniqueness validation** you added didn't work at all, and now you have three users with the same email address!

Hopefully, such a grim reality is **not inevitable**. To avoid such nasty issues, we need to be careful about potential **race conditions** and understand the circumstances where they might happen and what kind of **protective measures** we could apply.

<!--more-->

## Race conditions - what are they?

Race conditions are undesirable situations caused when the concurrent execution of the code causes negative consequences comparing to the scenario of having them executed sequentially. If you are used to dealing with threads, race conditions could sound like a regular thing. However, race conditions are as likely to happen when you run multiple processes of the same application! It might seem counterintuitive at first glance, but keep in mind that in most cases, there are some shared components between processes. In Ruby on Rails application, it will most likely be a database.

Let's take a look at a couple of common race conditions scenarios and protective measures against them.

## Multi-threaded servers and mutable globals

Saying that global variables are not a good idea will be nothing extraordinary. However, the issues with globals get pretty bad when you operate in a multi-threaded environment. A notable example for Rails apps would be Puma web server. By default, every Puma instance will use up to 5 threads. That approach certainly has some great benefits.  On the other hand, you can easily expose yourself to race conditions with global variables if you are not careful.

Let's examine some antipattern: a global variable for the current user's IP. One of the "creative" ways of implementing this pattern would be having `User.current_ip` and `User.current_ip=` method for class-level attribute reader and writer:

``` rb
class User < ApplicationRecord
  @@current_ip = nil

  def self.current_ip
    @@current_ip
  end

  def self.current_ip=(ip)
    @@current_ip ||= ip
  end
end
```

Let's say that `User.current_ip` is set in `ApplicationController` for every controller action and is later persisted when performing any write action, just to know the person and their IP address behind all the changes.

The original idea of having a nice audit log sounded good, but if you ever decide to go with this kind of implementation, don't be surprised if the wrong IP addresses get persisted. But what's the actual problem?

Globals as class-level variables are shared by all threads within the same process. Imagine that we have a single Puma worker with 5 threads and we have 2 requests roughly at the same time:
User A decides to change their password. They typed a new one and clicked some `save` button. A hypothetical `UsersController#update` action is hit, and the proper IP is set.
Roughly at the same time, User B visits some page, and again, the IP address is set.
The change of the password gets persisted, along with `User.current_ip`

In such a case, it would look like as if the User B changed User's A address as it could be their IP address that would get stored for that change! That's a typical race condition that easily happens when using global variables that way.

Does it mean that it's not possible to use global variables without risk of race conditions?

Well, if the global is indeed the only way (hint: usually, it isn't), you could still use a thread-local variable, which is still a global variable, but visible only within a current thread. It exposes hash-like methods for reading and setting values, which makes it quite convenient to use:

``` rb
class User < ApplicationRecord
  def self.current_ip
    Thread.current[:current_ip]
  end

  def self.current_ip=(ip)
    Thread.current[:current_ip] = ip
  end
end
```

That way, you can still use globals and protect yourself from race conditions (although it won't protect you from the ugly code).

## Lack of database constraints

Let's look at the typical example: a signup process. We ask users to provide email, password, and password confirmation and let them sign up by clicking a `sign up` button. We don't want to have multiple user records with the same email, so we add a uniqueness validation:

``` rb
class User < ApplicationRecord
  validates :email, uniqueness: true
end
```
Any idea what is going to happen is some user clicks the button quickly three times in a row? There is a good chance that three records will be created, and the uniqueness validation won't provide any benefit!

One critical thing to understand here is that a uniqueness validation doesn't ensure uniqueness at all - it's rather for displaying a helpful validation error in the absence of race conditions. When clicking the button three times quickly in a row, we are quite likely to have the following scenario:

Request 1 - check if a user exists, and proceed as no user with that email is found.
Request 2 - check if a user exists, and proceed as no user with that email is found.
Request 3 - check if a user exists, and proceed as no user with that email is found.
Request 1 - arrive at the code that inserts data into the database. A new user record gets created.
Request 2 - arrive at the code that inserts data into the database. A new user record gets created.
Request 3 - arrive at the code that inserts data into the database. A new user record gets created.

The only way to protect ourselves against this kind of race condition in all scenarios would be adding a unique index on the database level. Or you could prevent concurrent execution of that code with an advisory lock (which covered later in the article).

There is one more variation of this problem, that can also be caused by a race condition, but this time a lack of proper database constraint would be an issue. Imagine that Traveller A wants to book a stay between 3rd of June 2021 and 10th of June 2021, and Traveller B wants to book a stay between 2nd od June 2021 and 7th of June 2021, and they create a reservation, roughly at the same time - making a validation that checks if the dates are available useless as far as data integrity goes.

The solution is again handling it on the database level. For this particular example, we could take advantage of `tsrange` in PostgreSQL. A typical example of  ensuring uniqueness for a datetime range would look like this:

``` sql
ALTER TABLE reservations ADD CONSTRAINT no_overlapping_reservations EXCLUDE  USING gist(property_id WITH =, tsrange(start_at, end_at, '[)') WITH &&);
```

## Pessimistic locking

Let's get back to the example from the introduction to the article. Imagine that in your e-commerce system, you can either pay with a credit card or credits that can be added to the user. Some hypothetical user has 100 credits - just enough to pay for two orders, with a total price of $25 and $75. Interestingly enough, this user knows something about software development and wants to check if the system can handle some nasty edge-cases and decides to do a little experiment: pay for these two orders roughly at the same time and check what happens. It turns out that both orders are marked as paid, and there are still 75 credits available!

Sounds pretty bad, huh? Let's take a look at the code then:

``` rb
def charge_user_for_order(user_id, order_id)
  user = User.find(user_id)
  order = Order.find(order_id)
  ActiveRecord::Base.transaction do
    user.credits -= order.price
    user.save!
    order.paid!
  end
end
```

Well, we have some method that finds a user and order, subtracts credits from the user, persists that change, and marks the order as paid. It's pretty much what we expected, what could go wrong?

The problem here is the result of `-=` operation. We might expect it to be 0 after paying for both orders, but with concurrent execution of the code, it's quite likely that the following scenario will happen:

Request A: load User and Order
Request B: load User and Order
Request A: set user's credits to 100 - 75 and persist the change
Request B: set user's credits to 100 - 25 and persist the change

And that's exactly how we can end up with having both orders paid and 75 credits available.

Fortunately, it's quite easy to avoid it: we would just need to acquire a row-level lock using ActiveRecord's Pessimistic Locking feature and its `lock!` method, which makes it one extra line in our `charge_user_for_order` method:

``` rb
def charge_user_for_order(user_id, order_id)
  user = User.find(user_id)
  order = Order.find(order_id)
  ActiveRecord::Base.transaction do
    user.lock! # do not forget about this!
    user.credits -= order.price
    user.save!
    order.paid!
  end
end
```

What happens under the hood is that ActiveRecord will perform `SELECT FOR UPDATE` query, which will prevent any modification of that record within any other transaction (or will wait until concurrent transaction finishes) as long as it's also locked in that transaction. Also, it internally reloads the record (with `reload` method). That way can be sure we operate on the most recent data.

## Advisory lock

It often happens that we need to prevent concurrent execution of the code, but it's not the database table or a database row that we need to have locked. Instead, we need something like Ruby `Mutex` that would be applicable to multiple processes, not to just threads within the same process, so that the same code would be executed sequentially.

Fortunately, PostgresSQL offers a great feature for precisely this purpose - [advisory locks](https://www.postgresql.org/docs/12/explicit-locking.html#ADVISORY-LOCKS). What is more, there is [with_advisory_lock](https://github.com/ClosureTree/with_advisory_lock) gem that simplifies using advisory locks.

So what would be the case where advisory locks would be useful? Imagine a situation where you need to fetch some file from Amazon S3, modify its content, and upload it back after the modification. To be more precise, we have some Sidekiq workers that handle this logic in the background, and the code looks like this:

```  ruby
class S3Worker
  include Sidekiq::Worker

  def perform(*args)
    fetch_file
    modify_file
    upload_file
  end
end
```

What's going to happen if this code is executed concurrently by 5 workers? Depending on when the file fetching and uploading happens, we can get very different results, but we will surely have a huge inconsistency in the end. And the result would be very different comparing to having the jobs executed one by one.

It sounds like a significant potential issue, but fortunately, advisory locks can easily prevent the concurrent execution of the workers. That's how the code could look like with a little help coming from [with_advisory_lock](https://github.com/ClosureTree/with_advisory_lock) gem:

```  ruby
class S3Worker
  include Sidekiq::Worker

  def perform(*args)
    ActiveRecord::Base.with_advisory_lock("S3Worker-Lock") do
      fetch_file
      modify_file
      upload_file
     end
  end
end
```

Once a lock with `S3Worker-Lock` gets acquired, every process trying to acquire the same lock will need to wait until the existing one is released. And that's how we can ensure the sequential execution of the jobs, despite the concurrency coming from having multiple processes.

What is also interesting is that we could replace pessimistic locks with advisory locks, which might make sense in some circumstances. One example could be a high frequency of updates of the same row within the different transactions that take a considerable amount of time, and waiting until each of them finishes might not be an option, which would be especially desired if the different updates have nothing in common.

This could even be the case for our previous example with credits. This is how we could rewrite the code to use an advisory lock instead of a row-level lock:

``` rb
def charge_user_for_order(user_id, order_id)
  ActiveRecord::Base.transaction do
    ActiveRecord::Base.with_advisory_lock("charge_user_for_order_#{user_id}_#{order_id}") do
      user = User.find(user_id)
      order = Order.find(order_id)
      user.credits -= order.price
      user.save!
      order.paid!
    end
  end
end
```

As long as we don't modify the same attributes in any other transactions, we should be fine without using pessimistic locking. But if the same attributes of either `user` or `order` were getting modified elsewhere as well, we might get some deadlocks.

There is one crucial thing to keep in mind when using an advisory lock instead of pessimistic locking - watch out when you materialize the record as there is no `reload`ing of the record in the code! This could result in the same problem that we initially wanted to fix with pessimistic locking. For example, an advisory lock is pretty much useless here:

``` rb
def charge_user_for_order(user_id, order_id)
  user = User.find(user_id)
  order = Order.find(order_id)
  ActiveRecord::Base.transaction do
    ActiveRecord::Base.with_advisory_lock("charge_user_for_order_#{user_id}_#{order_id}") do
      user.credits -= order.price
      user.save!
      order.paid!
    end
  end
end
```

Both `order` and `user` are materialized before acquiring the advisory lock, so even if we block the concurrent execution of the code, we could end up with executing further logic on the outdated records. That's why we need to wrap the execution of the entire logic inside the advisory lock, not just a small part of it.

## Redlock

What if you don't use PostgreSQL but still need a distributed lock/mutex for the use case like with S3 operations? If you use Redis, that shouldn't be a problem. You could use some solution implementing [Redlock](https://redis.io/topics/distlock) - an algorithm implementing a distributed lock.

It turns that there is a solid gem: [redlock-rb](https://github.com/leandromoreira/redlock-rb), which makes it easy to use in the Rails apps as we don't need to figure it out on our own. However, it is not a replacement for an advisory lock, as it needs to be used a bit differently. Check the following example out:

``` rb
redlock = Redlock::Client.new(["redis://localhost:6379"])
expiration_time_in_milliseconds = 60_000

first_lock = lock_manager.lock("S3Worker-Lock", expiration_time_in_milliseconds)
# => immediately returns a hash containing data about the lock
second_lock = lock_manager.lock("S3Worker-Lock", expiration_time_in_milliseconds)
# => immediately returns `false`
```

If we used an advisory lock (at least via `with_advisory_lock` method, there is also `with_advisory_lock_result` method, which works a bit differently), the second job would be waiting until the first lock is released and then execute the logic. With Redlock, the second job would return immediately without executing the logic. That could actually be the desired behavior, as maybe there is no need to execute the same thing twice. Still, if we wanted to have the same behavior as in the original example, we would need to take care of it on our own, e.g., by retrying the job later.

## Optimistic locking

When our system allows multiple users to operate on the same records, we might run into critical problems. For example, we might want to make sure that every time someone makes a decision, it is done based on the latest data. One use case would be making a refund to the customer so that we grant that person some special credits that can be used later for the purchases. If multiple people can do that and roughly at the same time they see that there is some refund to be made, we might have an unfortunate scenario where the credits are given twice. In such a case, what would be desired is not allowing the second operation to happen, which comes down to optimistic locking.

It turns out that this is a pretty simple thing to achieve in Rails - it requires merely adding `lock_version` column to the model's table, and that's it, you don't even need to add any extra config! ActiveRecord is going to take care of incrementing it on every update. That way, ActiveRecord will prevent an update of the record if the `lock_version` for that particular record has changed by raising `ActiveRecord::StaleObjectError`:

``` rb
user_1_a = User.find(1)

user_1_b = User.find(1)

user_1_a.credits += 100
user_1_a.save!
# works just fine

user_1_b.credits += 100
user_1_b.save!
# raises ActiveRecord::StaleObjectError
```

## Wrapping up

**Race conditions**, even outside of multi-threaded code, can have pretty terrible consequences if they are not prevented before they happen. Fortunately, by understanding just several possible scenarios and strategies on how to mitigate them, we can easily avoid these kinds of issues.
