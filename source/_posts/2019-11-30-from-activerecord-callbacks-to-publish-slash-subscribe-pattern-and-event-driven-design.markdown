---
layout: post
title: "From ActiveRecord callbacks to Publish/Subscribe pattern and event-driven design"
date: 2019-11-30 8:00
comments: true
categories: ["Ruby", "Rails", "Wisper", "Design", "Architecture"]
---

Imagine that you are working on a large **legacy application** that also contains the dreaded **ActiveRecord callbacks** in the models handling most of the business logic. At some point, and under a certain level complexity, the mess caused by that choice might become hard to **keep under control**, the **risk of introducing bugs** will increase and the teams(s) working on the application will be way less productive. That will most likely lead to an attempt to find a better way of designing the application. The problem, though, might be that the scope of the application is so huge that introducing any meaningful changes to the application will take weeks, if not months.

Does it mean the application is doomed? Not necessarily. There are some ways how you could introduce meaningful changes under these circumstances with a minimum effort. The result will not be perfect, but it could be good enough for some time and might also be a transition between the old dirty way and a new clean design. The solution would be to move to **Publish/Subscribe pattern** and in general, to take advantage of **event-driven design**.

<!--more-->

## Advantages of Publish/Subscribe pattern

There are multiple advantages of pub/sub pattern (and some disadvantages as well! Like increased complexity). Still, I want to focus on the two of them that make the most difference in this context: Single Responsibility Principle and having a clearer idea about what is a primary purpose of a given use case and what are its side-effects (which also helps with cohesion and separation of concerns). Let's examine each of these advantages.

### ActiveRecord Models and Single Responsibility Principle

A typical example of usage of ActiveRecord callback could be something like this:

``` rb
class User < ApplicationRecord
  after_commit :notify_user_created, on: :create

  private

  def notify_user_created
    # call some service here
  end
end
```

The obvious thing here is that `User` model knows a lot of things. Firstly, it is aware of some important domain concepts, like sending a notification that the user has been created. The other thing is that it will also know what service to call and how to call it when the user is created. This, being on top of all the other responsibilities of ActiveRecord models, clearly violates the Single Responsibility Principle. And it only gets worse as the domain becomes more complex - more callbacks, even more responsibilities, and in the end, you end up sending five different notifications with some complex conditions for each of them when they are actually sendable.

### Side-effects Visibility

One thing that would be important to grasp would be a separation between the primary logic behind a given use case and its side-effects. When you create a user, it is rather apparent that the goal is to create a user. Maybe it also makes sense to create a Profile record for them. Or even a ProfilePhoto record if it is within a transactional boundary of creating a user (which means that having a User without ProfilePhoto might not make sense and should never be possible). How about sending notifications? E.g., an extra email sent to some superadmin that a new user has been registered? That doesn't sound so close to the actual use case as a user creation with its relationships. This would be closer to a side-effect of an operation.

In that case, if we can easily establish a strong boundary between the primary use case and its side-effects, why not to do in the code as well? And one of the most apparent ways how to express this would be to have clear isolation between these two things. It could be within the same application, or maybe it could even be separate applications - it shouldn't really matter that much when the logic is decoupled. However, what would be the way to let the other part of the application or a different application know that something has happened that might be important? In both of these cases, the answer is the same: event-driven system via publish/subscribe pattern.

## Doing Pub/Sub with Wisper gem

Pub/sub is a common pattern, and you could either roll your own implementation quickly or use some battle-tested gem that comes with some extra nice stuff. One of the gems that are quite minimal and do exactly the job we need is [wisper](https://github.com/krisleech/wisper). It comes with a couple of nice features you might want to explore, but for now, let's focus on only one them: **global** pub/sub.

This might initially sound like a bad idea (don't get discouraged by the word "global"), but remember: our intention is to refactor some existing mess out of ActiveRecord models, and if some domain logic is in the callbacks already, and you have multiple endpoints for executing operations on the same entities (e.g., multiple API versions), you will have a hard time of making it clear from the start. And also, ActiveRecord callbacks have already a "global" scope, so it's not like we are moving things in a worse direction.

What we want to do is to publish some event from the model and subscribe some listeners to that event in some config file, like an initializer.

Let's do something very basic: when a user gets created, we are going to publish `user_created` event and subscribe to it some listener, e.g., `User::NewRewRegistrationNotifier` , that will respond to `call` method taking one argument: `event`.

The first thing we are going to do will be publishing an event from the model when the record gets created. This sounds like something that can be done via `after_commit on :create` callback. We already need [wisper](https://github.com/krisleech/wisper) at this point, so adding it to the `Gemfile` would be a good idea.

For broadcasting the event, we will need to include `Wisper::Publisher` module and use `broadcast` method. The first argument will be the event name, and the second one will be an instance of `UserCreatedEvent` event. We could do something more minimalistic like passing a hash of attributes, but it's usually a good idea to not use primitives like that (unless you are serializing data and passing it to some other process for example) and use some more domain-specific objects where you can potentially add some behavior. This is how it could look like:

``` rb
class User < ApplicationRecord
  include Wisper::Publisher

  after_commit :publish_user_created, on: :create

  private

  def publish_user_created
    broadcast(:user_created, UserCreatedEvent.new(user_id: id, email: email, fullname: fullname))
  end

  class UserCreatedEvent
    attr_reader :user_id, :email, :fullname

    def initialize(user_id:, email:, fullname:)
      @user_id = user_id
      @email = email
      @fullname = fullname
    end
  end
end
```

Cool, so the publishing part is done. What about acting on this event?

For that, we will need to define some global subscriptions in the initializer, for example, `config/initializers/wisper.rb`. What we want to do is subscribe `User::NewRewRegistrationNotifier` to `:user_created` event and invoke our event handler by calling `call` method on it:

``` rb
# check https://github.com/krisleech/wisper/wiki/Global-listeners-and-Spring to understand why we use `Rails.application.config.to_prepare` or why we need `Wisper.clear`
Rails.application.config.to_prepare do
  Wisper.clear if Rails.env.development? || Rails.env.test?

  Wisper.subscribe(User::NewRewRegistrationNotifier, on: :user_created, with: :call)
end
```

And this is how the notifier could be implemented:

``` rb
class User::NewRewRegistrationNotifier
  def self.call(event)
    somehow_deliver_email_about_new_user_being_registered(event.email, event.fullname)
  end
end
```

And that's it! We've managed to do some refactoring out of callbacks using a pub-sub pattern. As a nice side-effect of that design, `User::NewRegistrationEventHandler` is way more reusable. It's not aware that it's called from a callback from a model. It could be the case that `event` would be coming from, e.g., RabbitMQ consumer and the event itself would be published from a different application, and we wouldn't need to adjust anything. That makes it was easier to break from a monolith into microservices if you ever need to as events make it easy to separate between what is necessary as far as a given use case goes and its side-effects.

## Publishing more "interesting" events

Let's say that we would like to have more "interesting" domain events in the application. Instead of subscribing only to `user_updated` event (which would be broadcasted from `after_commit on: :update` callback), we would like to subscribe to `user_suspended` event when the user gets suspended for some reason and send some notification. The config part could like this:

``` rb
Rails.application.config.to_prepare do
  Wisper.clear if Rails.env.development? || Rails.env.test?

  Wisper.subscribe(User::NewRewRegistrationNotifier, on: :user_created, with: :call)
  Wisper.subscribe(User::SuspendedNotifier, on: :user_suspended, with: :call)
end
```

What we know is that suspending a user is technically an update if we think about this from the ActiveRecord/CRUD perspective. A cool thing about ActiveRecord models is that it includes a dirty-tracking interface, so we can easily check what has changed during an update and have some sort of "activator attribute", e.g., `suspended` boolean attribute. We could assume that if the value of this attribute changes to `true`, it means that the user has been suspended.

Let's implement an "event splitter" that will subscribe to `user_updated` event and figure out based on the changeset if the user has been suspended or not and publish `user_suspended` if it's the case. Let's start with the user model:

``` rb
class User < ApplicationRecord
  include Wisper::Publisher

  after_commit :publish_user_created, on: :create
  after_commit :publish_user_updated, on: :update

  private

  def publish_user_created
    broadcast(:user_created, UserCreatedEvent.new(user_id: id, email: email, fullname: fullname))
  end

  def publish_user_updated
    broadcast(:user_updated, UserUpdatedEvent.new(user_id: id, changeset: previous_changes))
  end

  class UserCreatedEvent
    attr_reader :user_id, :email, :fullname

    def initialize(user_id:, email:, fullname:)
      @user_id = user_id
      @email = email
      @fullname = fullname
    end
  end

  class UserUpdatedEvent
    attr_reader :user_id, :changeset

    def initialize(user_id:, changeset:)
      @user_id = user_id
      @changeset = changeset
    end
  end
end
```

To split the event, we need a `changeset` that will be derived from dirty-tracking. For `after_commit` callbacks, we can get this data from `previous_changes` hash.

Now, let's add one extra subscription to Wisper:

``` rb
Rails.application.config.to_prepare do
  Wisper.clear if Rails.env.development? || Rails.env.test?

  Wisper.subscribe(User::NewRewRegistrationNotifier, on: :user_created, with: :call)
  Wisper.subscribe(User::EventSplitter.new, on: :user_updated, with: :call)
  Wisper.subscribe(User::SuspendedNotifier, on: :user_suspended, with: :call)
end
```

And this is how our `User::EventSplitter` could look like:

``` rb
class User::EventSplitter
  include Wisper::Publisher

  def call(event)
    if event.changeset.key?("suspended") && event.changeset["suspended"][1] == true
      broadcast(:user_suspended, UserSuspendedEvent.new(user_id: event.user_id))
    end
  end

  class UserSuspendedEvent
    attr_reader :user_id

    def initialize(user_id:)
      @user_id = user_id
    end
  end
end
```

Notice that `call` is an instance method this time, mostly to comply with `Wisper::Publisher` and make it easy to call `broadcast` method coming from this module without the extra hassle of making it a class method at all cost.

And our final class, `User::SuspendedNotifier`:

``` rb
class User::SuspendedNotifier
  def self.call(event)
    deliver_user_suspended_notification_somehow(event.user_id)
  end
end
```

And that's it!

## Pub-Sub As A Step Forward, Why Doing This Is Not All Sunshine And Rainbows And How the Ideal World Could Look Like

So, have we come all this way to learn that this pattern is not that great?

Not really. This is definitely a step forward comparing to keeping all the logic in some callbacks here and there. However, this is far from perfect. And you might even argue that we've made things way more complicated than they need to be! In both cases, calling `user.save` will trigger some potentially unexpected side effects as saving a user is not "just" saving a user. If you had all the logic in the callbacks, you would have only one place to check what is going on around the persistence of the users. With this event-based thing, now there are multiple places to check, and the logic is more "hidden".

However, this could be considered a step forward, especially if you get used to thinking about the separation of primary logic and its side-effects. With the event-based design, you can quickly check the potential side-effects in the Wisper subscriptions. Want to know what happens when you create a user? Just check what subscribes to `user_created` event, which seems to be more readable than checking the callbacks in the model. Another great advantage of that approach is that models will have way more limited responsibilities. No more executing tons of use cases around persistence, using dirty tracking to decide whether something should be executed or not, etc., models will be just publishing the events, and something else is going to decide what to do about it.

Also, by using events, we make it easier to have more definite boundaries between contexts in your domain. For example, sending notifications could happen in a dedicated application consuming events via RabbitMQ, and the "primary" application would publish the events to Rabbit in one of the Wisper listeners. With that kind of design, it would be easy to move the notifiers into a new application, and we would only need to add some extra layer that would take the serialized event from the queue, turn the serialized payload it into a proper event, like `UserSuspendedEvent`, and then just execute `User::SuspendedNotifier`. There would be no change in the business logic or in the layers that are close to the business logic. It would be only about the "infrastructure" layer.

On the other hand, there is one huge issue with what we did - the CRUD mindset and using `save` method from ActiveRecord as the interface. This is particularly visible in the case of suspending the user. Technically, it is an update, but it doesn't mean we should treat it just like this. We implemented an event splitter that somehow tries to isolate and cover the mess, but this comes down to the problem of using ActiveRecord as an interface for everything around the domain, instead of using it for what it is supposed to be used: persistence, like inserting stuff to "users" table, not persisting five other unrelated objects after performing some operations on them in the callbacks.

It's worth remembering that all these things we did were supposed to be a refactoring away from having the logic in ActiveRecord callbacks, especially under the circumstances where you might have multiple endpoints where stuff gets persisted (e.g. multiple API version/endpoints), so we couldn't just rewrite a big part of the application in a single step.

But now that we know an obvious problem with the still improved approach, how does the perfect version of it could look like?

Well, now that we know that suspending a user is an important concept in the domain, we could start by introducing a service: `User::Suspend`. The responsibility of that class would be limited: suspend the user and broadcast the event. This is how it could look like in a perfect world:

``` rb
class User::Suspend
  attr_reader :user_repository, :event_bus
  private     :user_repository, :event_bus

  def initialize(user_repository:, event_bus:)
    @user_repository = user_repository
    @event_bus = event_bus
  end

  def call(suspend_user_command)
    user_id = suspend_user_command.user_id
    user = user_repository.find(user_id)
    user.suspend # this is merely an in-memory operation on the User entity, it does not execute any persistence and does not communicate with DB!
    user_repository.save(user)
    event_bus.publish(UserSuspendedEvent.new(user_id: user_id))
  end
end
```

Ok, maybe the perfect world is a bit too far away from what we usually have in the Rails apps, especially with repositories, event buses, and entities not coupled to the database ;).

But notice one interesting thing: instead of doing fancy `event_bus.publish(UserSuspendedEvent.new(user_id: user_id))`, we could replace it with: `broadcast(:user_suspended, UserSuspendedEvent.new(user_id: user_id))`. And our desired side-effect would be executed in the same way! Things are decoupled enough that changing things in one place won't result in the necessity of changing multiple other classes. Even if our original Wisper-based solution of replacing callbacks in ActiveRecord models was not perfect, it made it easier for further refactoring/rewriting.

## Wrapping up

Thanks to [Wisper](https://github.com/krisleech/wisper) gem, we've implemented a minimum **pub-sub** replacement of executing logic in **ActiveRecord callbacks**. Even though the solution is not perfect, it opens the way for further rewriting of the application thanks to decoupling the primary use case from its **side-effects**, and we've demonstrated how this could be the first step towards a way better design of the application.
