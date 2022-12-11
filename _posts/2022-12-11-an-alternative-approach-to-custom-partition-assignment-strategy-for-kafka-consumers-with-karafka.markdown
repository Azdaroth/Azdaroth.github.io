---
layout: post
title: "An alternative approach to custom partition assignment strategy for Kafka consumers with Karafka"
date: 2022-12-11 12:00
comments: true
categories: [Ruby, Ruby on Rails, Kafka, Karafka]
---

Recently, in [BookingSync](http://bookingsync.com/), we were performing a migration from [Karafka](http://github.com/karafka/karafka) 1.4 to 2.0, which we use for communication with [Kafka](https://kafka.apache.org). One of the great features available in version 1.4 was a **custom partition assignment strategy** for **consumers**. It was particularly useful for us as we've had some topics that had a **way higher throughput** than the other ones, so just a **round-robin strategy** with even distribution of topics for consumers was not a suitable choice as we needed **dedicated consumers** for these specific topics/partitions. Unfortunately, **custom partition assignment strategy for consumers** is no longer available in **Karafka 2.0**. Nevertheless, we managed to perform the migration and replaced the custom partition assignment strategy with a more straightforward and robust solution.

<!--more-->

## Anatomy of the problem


Most of our Kafka topics didn't have a very high throughput of the messages, so just using a default round-robin strategy for partition assignment was perfectly fine. However, two topics (with several partitions) had a significantly larger throughput than the other topics. To avoid issues with a huge lag, we took advantage of the custom partition assignment strategy that was available in Karafka 1.4 and implemented the following strategy:

1. Use a fixed number of consumers for a high-throughput topic A so that each partition has its own consumer. Effectively, it's still a round-robin strategy but applied to a smaller scope so that we could assign ten consumers to ten partitions
2. Use a fixed number of consumers for a high-throughput topic B so that each partition has its own consumer, the same thing as in point 1.
3. Assign remaining consumers using a round-robin strategy to the rest of the topics/partitions.

This solution was exactly what we needed to solve our problem with a huge lag. Unfortunately, the custom partition assignment strategy is no longer supported in Karafa 2.0 (because internally, Karafka 2.0 uses [librdkafka](https://github.com/edenhill/librdkafka), which doesn't support it, Karafka 1.4 used [ruby-kafka](https://github.com/zendesk/ruby-kafka) under the hood), so we had to find some alternative solution.

It turned out that there was even a better, more flexible, and more straightforward solution that would work with both Karafka 1.4 and 2.0.

## The solution

One thing that is easy to spot in the original solution is the fact that we were still using a round-robin strategy; it was just "partitioned" into three independent scenarios. That also implies that we might not need a custom partition assignment strategy at all; we just need to find a way to achieve this kind of partitioning in some alternative way. And we can do that by using three different processes that consume from different topics.

Apparently, there is no out-of-box way to limit the topics to some specific ones, but there is a simple workaround for this - use ENV variables and pass them when running the actual process.

Here is what our example routing might look like:

``` rb
class KarafkaApp < Karafka::App
  setup do |config|
    # ...
  end

  routes.draw do
    consumer_group :group_name do
      if ENV.fetch("ENABLE_EXAMPLE_TOPIC", "false") == "true"
        topic :example do
          consumer ExampleConsumer
        end
      end

      if ENV.fetch("ENABLE_EXAMPLE_TOPIC2", "false") == "true"
        topic :example2 do
          consumer ExampleConsumer2
        end
      end

      if ENV.fetch("ENABLE_EXAMPLE_TOPIC3", "false") == "true"
        topic :example3 do
          consumer ExampleConsumer3
        end
      end
    end
  end
end
```

And then, we could run three different processes the following way:

1. `ENABLE_EXAMPLE_TOPIC=true bundle exec karafka server`
2. `ENABLE_EXAMPLE_TOPIC2=true bundle exec karafka server`
3. `ENABLE_EXAMPLE_TOPIC3=true bundle exec karafka server`


As a bonus, it turns out that this solution provides more flexibility in at least two aspects:

1. More flexiblity for deployments - since there are three separate types of processes/pods, we can apply different configurations, such as cpu/memory limits.
2. we can fine-tune the config of the consumers themselves, e.g., by setting different values for `session.timeout.ms`, `heartbeat.interval.ms` or `max.partition.fetch.bytes` (via ENV variables as well) if we experience rebalancing of the consumers too often due to increased time of processing batches for the high-throughput topics.

## Conclusions

Thanks to some creative ideas for using multiple types of processes with different **ENV variables**, the lack of a **custom partition assignment strategy for consumers** should not be a blocker for migrating to [Karafka](http://github.com/karafka/karafka) 2.0. Being a **more flexible solution** that is also **easier to implement** is also a significant advantage compared to the **custom partition assignment strategy**.
