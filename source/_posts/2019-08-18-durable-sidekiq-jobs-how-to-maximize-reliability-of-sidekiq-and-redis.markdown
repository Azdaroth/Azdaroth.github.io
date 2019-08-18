---
layout: post
title: "Durable Sidekiq jobs: how to maximize reliability of Sidekiq and Redis"
date: 2019-08-18 20:00
comments: true
categories: ["Redis", "Sidekiq"]
---

**Sidekiq** is one of the most popular (if not the most popular one) background job framework in Ruby world, which is not a big surprise: it allows to achieve a decent throughput, is stable and well-maintained, has some great features (including also all the gems extending its built-in functionality) and is easy to get started with. It seems like you could simply install **Redis**, add **Sidekiq** to your application and you are good to go!

That would work if you didn't have any **business-critical background jobs** where **reliability** doesn't matter that much. However, if you cannot afford to **lose jobs** every now and then, there are some things that are absolutely critical to review in your configuration and infrastructure.

## How can you lose a Sidekiq job?

There are multiple scenarios of how you can lose a Sidekiq job without preventive measures. Some of them are quite obvious; some of them are not.

One obvious way would be having Redis down and trying to enqueue a job. This one is pretty intuitive as there is no way of pushing something to Redis if there is no connection to Redis in the first place. From the less obvious scenarios, what is going to happen when Redis crashes while processing a job, due to, e.g., Out Of Memory exception? In "standard" Sidekiq (although not in Sidekiq Pro), processing a job means that the data is dequeued from Redis and if the worker is interrupted and killed, the job will be lost.

To make the matter worse, there are even more ways how to lose jobs. Imagine that Redis has been working just fine so far, there are some jobs enqueued to be processed in the future, nothing is getting processed at the moment and... the server gets restarted. Depending on your setup and how much data is stored in memory before it gets "persisted", it might turn out that all (or at least some of them) the enqueued jobs are lost!

As terrible as it sounds, there are some relatively quick fixes to these problems. Even though it might be still possible to lose jobs under [extreme circumstances](https://subscription.packtpub.com/book/big_data_and_business_intelligence/9781783280216/1/ch01lvl1sec16/dealing-with-aof-corruption-intermediate), these solutions will significantly minimize the likelihood of critical problems.

## Sidekiq Pro and its reliability features

The very first thing that would be worth doing would be buying a license for [Sidekiq Pro](https://sidekiq.org/products/pro.html) which is a low hanging-fruit, and you can quickly add it to your applications.

Sidekiq Pro, unlike "standard" Sidekiq, offers extra server reliability by using [Redis's RPOPLPUSH](https://redis.io/commands/rpoplpush). Thanks to that, the job is not entirely removed from Redis once it starts being processed. Rather, it is atomically moved to "processing list" and is removed from there only after it's processed. In that sense, we can be confident that if the job ended up in Redis, it would almost certainly be processed by Sidekiq workers, even if there will be multiple Out Of Memory exceptions and the Sidekiq processes will be killed multiple times. Enabling it is as easy as enabling `super_fetch` in Sidekiq config. If you want to learn more about Sidekiq Pro Reliability Server, you can check [the docs](https://github.com/mperham/sidekiq/wiki/Pro-Reliability-Server).

What is more, Sidekiq Pro also brings some [client reliability features](https://github.com/mperham/sidekiq/wiki/Pro-Reliability-Client), although they are more limited. The scenario where it's supposed to help is when Redis is down. When calling `MyJob.perform_async`, we usually assume that things will just work. Sadly, it might sometimes happen that Redis will be down or there will be some network issue, and we will see a nasty 500 error. Sidekiq Pro tries to mitigate this problem by keeping the jobs locally and enqueuing them once the connection with Redis is reestablished. However, the queue where the jobs are stored is an in-memory one, and there is a limitation on how many jobs are stored there, so this solution is not perfect. If you don't find this solution reliable enough for your needs, you can establish a process for recovery from Redis outages, like storing the jobs in the database when rescuing from exceptions and enqueuing them later once Redis is back.

The only issue with Sidekiq Pro is that it's not that cheap. If you don't require strong guarantees and reliability, "standard" Sidekiq will probably be enough, but for processing business-critical jobs, Sidekiq Pro will be a great addition.

## Redis and its persistence modes

Another scenario that can cause jobs to be lost is a crash or a restart of Redis process. To understand the potential consequences of these scenarios, we need to take a look at the persistence modes that are available.

Redis offers two strategies that can be used as standalone modes or be combined:

1. **RDB** (**Redis Database Backup**) - when using that mode, Redis will periodically create snapshots allowing point-in-time recovery. What it means is that if the snapshots are created every 5 minutes, you can lose the jobs from the maximum last 5 minutes. And in case of recovery, you might get some jobs that have been already processed within the last 5 minutes.
2. **AOF** (**Append Only File**) - when using that mode, Redis will log all the operations using `fsync`. It can happen for every write operation, every 1 second or not at all.

As you might have guessed, using `AOF` is necessary for reasonable durability. However, the exact config (i.e., whether `fsync` should happen every second or on every write) is highly dependent on the throughput and acceptable performance in your applications, since those operations add extra overhead. If the performance is good enough with `fsync` on every write, by all means go for that. But if the throughput suffers significantly, you might consider going with `fsync` every second and establishing a process of what to do if Redis goes down and some jobs are lost. This is again highly dependent on your applications and needs but usually logging jobs and what exactly gets enqueued is a good idea, including the name of the worker's class, its arguments, and timestamps. That way, you can predict which jobs might have been lost and enqueue them manually. You risk that some jobs might be processed more than once, so idempotency of the jobs would greatly help.

What about RDB? It would still be a good idea to have it enabled - [Redis's docs](https://redis.io/topics/persistence#ok-so-what-should-i-use) recommend it in case there is a bug in the AOF engine, which sounds scary, but it's worth keeping in mind that durability is not the primary focus of Redis.

## Wrapping Up

Even though getting started with **Sidekiq** is not rocket science, and it might initially seem like everything is fine, it won't be enough for an application processing business-critical backgrounds jobs. If you want to make sure you won't be **losing jobs**, you should consider buying **Sidekiq Pro** license and make sure **Redis** persistence is configured optimally (ideally, **AOF** persistence with **fsync** on every write).
