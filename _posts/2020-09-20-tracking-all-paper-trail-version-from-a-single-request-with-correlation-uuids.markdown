---
layout: post
title: "Tracking All Paper Trail Version From A Single Request With Correlation UUIDs"
date: 2020-09-20 9:00
comments: true
categories: [Ruby, Rails, Ruby on Rails, Paper Trail, Audit Log, Correlation UUID]
---

If you've ever had a need to implement an **audit log** to track all the changes that get persisted for all or at least some models in your application, there is a good chance that you've encountered [PaperTrail gem](https://github.com/paper-trail-gem/paper_trail) that makes it trivial to **track all the changes** - it might be as easy as adding `has_paper_trail` to the desired models.

However, storing versions is just one thing. The other one is using them later, which sometimes might be far from obvious. For example, you see that some record was updated, but you don't exactly know why. Maybe you have `whodunnit` stored, but it still doesn't give you the entire picture as there might be multiple ways how a given record can be updated and you are trying to establish some **causality** between multiple actions as one update can lead to another one that can lead to yet another one. Not to mention that the persistence can be executed from the background jobs, which will mean that `whodunnit` will either be nil or be something else (if you, for example, decide to use the name of the job class for `paper_trail_user`). Merely using `created_at` won't be that useful for sure as it's not enough to group versions form the same context.

Fortunately, there is an easy solution to this problem, which is also quite simple to implement - it's adding a `correlation UUID`.

## What Is Correlation UUID?

Correlation UUID is a value in UUID format that is used for grouping *things* (events, logs...) that have the same origin (e.g., a specific action) that helps establish the causality (how exactly you ended up with something and what events lead to it). Thanks to that, you can easily figure out what happened during a specific request by assigning the same value of correlation UUID to all PaperTrailVersion records that got created. Furthermore, you can also track its side effects by reusing the same value in background jobs, e.g., in Sidekiq.

You might be wondering if this really has to be in UUID format, but the answer here is simple: no, it doesn't need to be. For example, you can use ULID, which could even be a better choice as it has the benefit of being lexicographically sortable. It just happens that UUID is the most popular approach and it's easy to generate.

##  How to implement Correlation UUID for PaperTrailVersions

The most straightforward approach would be assigning some global value unique per request (which implies the need for thread-safety) before saving the version. So what we need is an extra column (`correlation_uuid`) and something like `Thread.current` store but with values erased after each request. Fortunately, there is a gem that does exactly that: [request_store](https://github.com/steveklabnik/request_store).

Using a global is quite ugly, but it allows us to implement the desired feature in a simple way, and it doesn't necessarily make the design worse as `paper_trail` already uses a similar global for storing, e.g. `whodunnit` value.

Here is how an example UUID generator could look like:

``` rb
class RequestCorrelationUuidGenerator
  def self.uuid
    store[:correlation_uuid] ||= SecureRandom.uuid
  end

  def self.uuid=(value)
    store[:correlation_uuid] = value
  end

  def self.store
    RequestStore.store[:paper_trail] ||= {}
  end
  private_class_method :store
end
```

`paper_trail` stores global data in `RequestStore.store[:paper_trail]` so it's a reasonable idea to reuse it for storing our correlation UUID.

Now, that we have a generator, let's add a callback to the to PaperTrailVersion model:

``` rb
class Version < PaperTrail::Version
  before_create :ensure_correlation_uuid_assigned

  private

  def ensure_correlation_uuid_assigned
    self.correlation_uuid = RequestCorrelationUuidGenerator.uuid
  end
end
```

And that's it! That will be enough to group version coming from a single request. Now, if you find something suspicious, you can take the correlation UUID, find other versions with that value, order them by `created_at,` and the debugging should be way more pleasant. Just don't forget to add the index ;).

## Correlation UUID for further side-effects - how to use it in background jobs?

As I mentioned earlier, it might be quite valuable to pass the correlation UUID further to the background jobs, so that we can understand every step of the saga that originated from a specific action.

Of course, background jobs are not requests, but fortunately, it's not that difficult to reuse our `RequestCorrelationUuidGenerator` inside jobs.

Since Sidekiq is arguably the most popular solution for background jobs processing in Rails apps, I will show an example solution for Sidekiq. However, the idea itself should be possible to replicate for every other processor.

As a prerequisite to make it work with Sidekiq, we will need to introduce [request_store-sidekiq](https://github.com/madebylotus/request_store-sidekiq) gem. Since `request_store` clears the storage after each request, so that the values don't stick between them, we need something that will do the same thing, but after the job is processed. And that's exactly what this gem does.

The first problem that we need to solve is to make the correlation UUID somehow available in the job. One way to do this would be to make it an argument of the job, but that sounds painful to deal with. Ideally, we would have something that doesn't force us to change the signature of the `perform` method, and that injects the value without us doing it directly in any place. The second problem to solve would be to extract somehow the value of correlation UUID before the job gets executed and set that UUID for the global context (for a current Thread) using `RequestCorrelationUuidGenerator.uuid=` attribute writer.

Fortunately, Sidekiq has us covered as it allows us to add some extra behavior when enqueuing the job and around the execution of the job. We can do that using [middlewares](https://github.com/mperham/sidekiq/wiki/Middleware).

What we will need are two middlewares:
- a client middleware that will inject the correlation UUID to the job
- a server middleware that will set the correlation UUID

Here is an example implementation of the desired client middleware:

``` rb
class InjectCorrelationUuidMiddleware
  def call(_worker_class, job, _queue, _redis_pool)
    job["correlation_uuid"] = RequestCorrelationUuidGenerator.uuid
    yield
  end
end
```

Since `job` is a hash of a serialized job, we can put there pretty much anything we want. That way, we will make sure that the correlation UUID is stored in Redis.

And here is the server middleware:

``` rb
class SetCorrelationUuidMiddleware
  def call(_worker, job, _queue)
    PaperTrail::CorrelationUuid.uuid = job.fetch("correlation_uuid", RequestCorrelationUuidGenerator.uuid)
    yield
  end
end
```

The last thing we need to do is to actually inject these middlewares so that Sidekiq can make the proper use of them. We can put that in an initializer:

``` rb
Sidekiq.configure_client do |config|
  config.client_middleware do |chain|
    chain.add InjectCorrelationUuidMiddleware
  end
end

Sidekiq.configure_server do |config|
  config.client_middleware do |chain|
    chain.add InjectCorrelationUuidMiddleware
  end

  config.server_middleware do |chain|
    chain.add SetCorrelationUuidMiddleware
  end
end
```

To understand more about middlewares, it would definitely help to get through the [docs](https://github.com/mperham/sidekiq/wiki/Middleware). What is important to remember here is that jobs can also enqueue other jobs. That's why we need to add `SetCorrelationUuidMiddleware` twice - one for the client (e.g., for the request) and for the server (other jobs).

## Alternatives and similar problems

If you find yourself often wondering about the causality between the events, state transition, and trying to figure out how you exactly ended up in a given state, you might consider changing the implementation of your domain model and perhaps introduce CQRS and Event Sourcing. You might also want to check Sagas and Process Managers. Even though these are the concepts that are used rather in distributed systems, you might still find them useful if you have a complex logic that gets executed in the jobs that often enqueue other jobs.

## Wrapping Up

Having **correlation UUID** assigned to **PaperTrail Versions** is something that might significantly **help with debugging**. Fortunately, it's something that is not that difficult to implement.
