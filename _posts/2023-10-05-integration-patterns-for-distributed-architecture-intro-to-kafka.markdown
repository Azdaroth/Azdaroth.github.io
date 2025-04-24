---
layout: post
title: "Integration Patterns for Distributed Architecture - Intro to Kafka"
date: 2023-10-05 10:00
comments: true
categories: [Architecture, Microservices, Distributed Systems, Kafka, Ruby, Rails]
canonical_url: https://www.smily.com/engineering/integration-patterns-for-distributed-architecture-intro-to-kafka
---

In the [last blog post](https://www.smily.com/engineering/integration-patterns-for-distributed-architecture), we covered a general overview of **integration patterns for distributed architecture**, and now it's time to get into further details.

Let's start with perhaps the most exciting piece of tech we use in **Smily** - **Apache Kafka**.

*I originally published this article on the [Smily Engineering Blog](https://www.smily.com/engineering/integration-patterns-for-distributed-architecture-intro-to-kafka).*

<!--more-->

## What is Kafka?

Generally speaking, [Apache Kafka](https://kafka.apache.org/) is an open-source distributed event streaming platform developed originally at LinkedIn. It is designed to handle data streams and provide a fault-tolerant, durable, and scalable framework for building real-time data pipelines and streaming applications.

In the [previous blog post](https://www.smily.com/engineering/integration-patterns-for-distributed-architecture), we learned that Kafka is a tool we can use to implement the publish/subscribe type of integration between services. Given that there is a variety of message brokers that we could use to achieve the same result, let's focus on what makes Kafka unique and its major advantages.

Let's take a look at the basic visualization of how Kafka works, and let's make sure we understand the key concepts.


![Image description](https://dev-to-uploads.s3.amazonaws.com/uploads/articles/igv438994cftftchstnk.jpg)

Everything starts on the **Producer's** side, responsible for **publishing events.** For example, if we use Kafka for activity tracking (as LinkedIn did when creating Kafka), we could send an event such as *page_visited* with some JSON payload containing a timestamp, user ID, and many other things that could be useful.

These events will get published to **topics,** which are essentially append-only logs where each event can be identified under a given **offset** (similar to an array's index).

**Topics** can be divided into multiple **partitions** to allow parallelization**,** and the **partition key** provided when publishing the message will determine to which partition exactly the event will be delivered to.

**Topics** are like categories - so events that are somehow similar should go into the same topic. This does not necessarily mean that, for example, each database table/application model would have a dedicated topic in Kafka. Actually, that could be a really poor design in many cases.

When designing *topics*, we need to remember the critical factor - that we deal with append-only logs. So all the events will be ordered in a given partition's topic. In many cases, we want to preserve the causality/sequence of the events. For example, we would expect *the payment_paid* event to be processed after *the payment_created *event.* But if we published these two events into separate topics, that might not necessarily be the case! The same thing could be for events such as *order_created* and *payment_paid* (for a given order) - there is a good chance that we want to keep the order of such events and have them in the same topic. And things related to a given order should be in the same partition (which will be determined by the provided **partition key**, which could be, for example, order ID). But probably, we don't care if we processed *customer_profile_picture_updated* before or after the payment got paid, so there is a good chance that we could use separate topics here.

Since we've already started discussing how things are processed, let's move to **consumers** organized within **consumer groups**. Consumers are responsible for processing events. Think of them as workers - some separate processes consuming from the **topics/partitions,** just like **Sidekiq** workers process jobs from queues. And **consumer groups** are like independent receivers. For example, you might have two applications requiring consuming payment-related events from Kafka - one for payment processing and the other for business intelligence. And these two would be two **consumer groups**. However, you can also have multiple **consumer groups in a single application.** For example, if you have a modular monolith, each module/Bounded Context could be a separate **consumer group** and consume things independently from all other modules.

What we need to keep in mind is that within the same **consumer group,**  a single consumer can consume from multiple partitions, but a given partition can have only one consumer assigned! This is the only way to ensure that the events will be processed in a given order (there are some ways to parallelize processing in a given partition and still preserve the order to a limited scope, but that's not available in Kafka.) But nothing is blocking us from having one consumer consuming from multiple partitions.

For example, if we have a single topic with five partitions, we could have just a single consumer (in a given consumer group), and that consumer would process all the messages from the partitions. However, if the consumer does not process messages fast enough resulting in a **lag** (the difference between the offset of the latest message published to the given partition and the last processed offset on the consumer side), we could increase the number of consumers up to five. That way, each consumer would be consuming from a single partition only.

And what if we added one more consumer? That will be essentially useless - you cannot have more than a single consumer within a single consumer group for a given partition so having more workers than partitions will result in workers that don't have anything to process. That's why having an appropriate number of partitions is critical, as this is how to parallelize processing and ensure it's fast enough.

What consumers do under the hood is go through messages one by one (usually by fetching a batch of events), execute the processing logic, and periodically store the **offset** of the latest processed event in a dedicated internal Kafka topic (this behavior is configurable, but it's more or less a standard use case for microservices integration). That's how the consumers can identify where they should start processing another batch of events.

And what happens if something crashes during the processing of the batch? This is dependent on the config, as we can have three delivery semantics:

- **at-most-once** the event will be processed either once (when everything goes fine) or *might* not be processed at all (when something goes wrong). However, there is still a chance that the event will be processed more than once due to how it works internally (committing offsets happening in fixed-time intervals). This is probably not a good config for the integration between microservices. Still, for frequent data reading from sensors, for example, it might be acceptable to lose some messages if we can achieve higher throughput.
- **at-least-once -** the event will be processed either once (when everything goes fine) or potentially more than once (when something goes wrong), as the offset is committed only after processing the messages. This would be the recommended semantics for the integration between microservices. However, in this scenario, we need to make sure that the processing is *idempotent* so that processing the same event twice will not result in having side effects executed twice as well (for example, we probably want to ensure that we won't charge a credit card twice).
- **exactly-once** somewhat arguable given that we are talking about distributed systems, yet you will quickly find that Kafka supports such semantics. Discussing **exactly-once** semantics would go way beyond the scope of Intro to Kafka. If you want to understand it a bit more, I recommend reading [this article from Confluent](https://www.confluent.io/blog/exactly-once-semantics-are-possible-heres-how-apache-kafka-does-it/).

And this is why we say that Kafka implements the **Dumb Broker/Smart Consumer** model - the broker is not responsible for delivering anything to consumers, it's up to consumers to handle consuming and be aware of the offset.

However, this is not everything that concerns the delivery semantics. We've just discussed the one between the broker and the consumer. What about the one between the Producer and the broker?

As you might expect, we also have **at-most-once/at-least-once** (and **exactly-once,** when the producer is configured to be idempotent, but the exact details go beyond the scope of this article) semantics with some interesting edge cases. Such as **at-least-once delivery**, but with some probability of a data loss!

In most production systems, we want to achieve high availability and ensure that the Kafka cluster will be operational, even if some broker goes down. That means we need to have multiple brokers (usually 3 or 5) and replication.

The semantics will be mainly determined based on the config of **Acks** (acknowledgments). We have three options here:

- Acks = 0 - it's essentially a "fire and forget" approach. The producer just publishes the event and doesn't care about any response from the broker. That way, we can achieve a higher throughput, but we also have a higher risk of data loss. This is the way to achieve **at-most-once semantics**.
- Acks = 1 - in that case, the producer expects to get a response from the broker that everything went fine. If there is no response, it will keep retrying until it receives the response or hits the retry limit. Given that this approach involves multiple attempts, it might turn out that the same event will be delivered more than once. This is the way to achieve **at-least-once semantics**. However, the replication is an independent step that happens after, so it might turn out that the brokers might go down between acknowledging the message and replicating it.
- Acks = All - similar to the previous case, yet the broker responds only after the replication has been performed. That does not necessarily mean that it has been performed to all the brokers! That depends on the separate configuration option about minimum in-sync replicas - and if you set it to 1, you might end up with a very different result than you would expect from Acks set as All.

There is a clear trade-off between durability, availability and latency. The production setup for microservices integration requires a careful analysis of the actual needs as well as getting familiar with more advanced concepts. Minimum in-sync replicas config is just a start, but there is more to it, for example, a leader election process and its impact on the potential data loss, especially [the unclean leader election](https://www.datadoghq.com/blog/kafka-at-datadog/#unclean-leader-elections-to-enable-or-not-to-enable).

## **Consequences of the design & some challenges**

Now that we've learned quite a lot about how Kafka works internally, let's think about some consequences of that design, both good and bad, and some other aspects worth considering when dealing with Kafka.

### **Retention**

The first one would be retention - since it's up to the consumer to manage their position in the log (offset), we have some interesting things to consider, especially as we don't have the behavior of a typical message queue where the event is gone after processing it.

It turns out that in Kafka, retention is what we set it to. And we can even set it to be indefinite as if it was a database!

We have two options: retention specified by time (e.g., to retain events for seven days), which is probably more popular, and the one based on total size.

### **Replaying events/skipping events**

Consumers in a given consumer group know where to start processing based on the offset they stored in Kafka for a given partition. And it also turns out that we can change the value of the stored offset ourselves!

Nothing prevents us from resetting the offset to the position from the previous day if we discover some potential bug and need to reprocess the events. Or maybe, for some reason, we want to skip processing some messages when a massive number of events got published that we don't care much about, and it will take hours to process them. At the same time, there are some other important events to be published in a moment that would ideally be processed immediately.

### **Dead-letter queue**

Here comes an interesting question: what happens on the consumer side if there is some error when processing the message, especially when it's not an issue the consumer can self-heal, perhaps due to some bug in the processing logic?

The retrying policy is on the consumer side to be defined, but there is one essential problem here - until the message gets processed, the consumer will not move on to the next one. Which means that the consumer might be stuck forever with that single message!

There is no [dead-letter queue](https://www.enterpriseintegrationpatterns.com/patterns/messaging/DeadLetterChannel.html) equivalent available out-of-box in Kafka (remember - it's a dumb broker/smart consumer model), so it's up to the consumer to handle exceptions correctly.

Fortunately, we have [some options](https://karafka.io/docs/Dead-Letter-Queue/) for the Ruby on Rails application that make it straightforward to handle such cases, which I'll get back to in a moment.

### **Log compaction**

Imagine that what you publish to Kafka are projections of the models that get updated very often, and you have a very long retention configured for the topics. That will mean a lot of data will be stored in Kafka. However, there is a good chance that it would be enough to keep just the most recent projection of the model (as we typically do when using a database).

By default, if a given model is published 100 times after the updates to Kafka, we will have 100 events stored there, which is not optimal for storage. Fortunately, we can enable **log compaction**!

Thanks to that feature of Kafka, as long as we send the same **message key** for a given model with every update (which should be straightforward; we can use the model name and its ID, for example, *"Rental-123"*) and enable **log compaction,** we can be sure that the previous messages with that **message key** will be dropped (or rather compacted).

### **Slow consumers**

This is something that is rarely thought about when starting to use Kafka until the first time you experience the issue.

Kafka (the broker) somehow needs to be able to distinguish between consumers that "alive" and actively processing messages and the ones that are no longer processing anything - especially that only one consumer within a single consumer group can consume from a given partition. But this is also important when something goes wrong or even during the deployments.

It is based on the heartbeats - the broker expects to "hear" from the consumer within a given time interval, and if it doesn't "hear" from it, the consumer will be considered inactive and "kicked out". If processing events from the batch takes longer than this expected time interval, you are guaranteed to experience a huge problem and potentially stuck consumers.

Fortunately, as with everything else in Kafka, this is configurable, yet the awareness of the potential issue is essential.

In reality, slow consumers are more complex than that, and there are multiple configuration options involved here. And if you know what you do, you can even have [long-running jobs with Kafka](https://karafka.io/docs/Pro-Long-Running-Jobs/), but I wanted to focus on a problem that is overlooked too often.

### **Monitoring**

Overall, Kafka is a complex tool, and there are a lot of things that can go wrong for various reasons. Given that it's possible to run into a problem where a consumer is stuck for hours with some message, solid monitoring is essential when running Kafka in production.

What exactly we should monitor when using Kafka deserves a separate article (you can expect it in the near future), but for now, the takeaway would be that it's critical to set it up.

### **Production setup**

Just use some managed service, such as [Amazon Managed Streaming for Apache Kafka (MSK)](https://aws.amazon.com/msk/). Running Kafka in production might be quite a challenge to get it right, especially when considering high availability and durability. Configuring Kafka and using it optimally is already a challenge; don't add an even bigger one unless you know what you do.

## **Why Kafka?**

After reading all of this, you might wonder if it's a good idea ever to use Kafka because it seems like everything can go wrong!

Don't worry, your Sidekiq/Redis combo probably has been regularly losing jobs unless you configured it for [minimum reasonable durability](https://karolgalanciak.com/blog/2019/08/18/durable-sidekiq-jobs-how-to-maximize-reliability-of-sidekiq-and-redis/).

Joking aside, the essential idea is that you need to understand the tools you use. Even such a popular combination as Sidekiq/Redis can cause some unexpected problems unless you are aware of them and you know what to do to prevent them from happening in the first place.

The same thing is in Kafka - as long as you understand how it works, at least on the fundamental level, and have appropriate monitoring in place, most likely, you will be fine.

But before that, you must ensure that Kafka is exactly what you need.

Consider Kafka if at least one of the following scenarios apply:

- you need strict ordering of the events
- you do stream processing
- you build data pipelines
- you process a considerable amount of data/huge number of events
- you need the actual retention of the events
- you are sure that what you need is something that implements a dumb broker/smart consumer model
- the tooling/framework available for Kafka will allow you to get the job done significantly easier, even if you could use some alternative

If you need just a standard message queue, probably using [RabbitMQ](https://www.rabbitmq.com/) or Amazon [SNS](https://aws.amazon.com/sns/)/[SQS](https://aws.amazon.com/sqs/) would be a better idea as it would simply be a simpler solution to the problem.

There are also some alternatives to Kafka that would be appropriate for the scenarios mentioned above. One example would be [Apache Pulsar](https://pulsar.apache.org/), which could be a superior choice in some scenarios. Yet, it's a less popular tool, so fewer tools and integrations are available.

## **Kafka with Ruby on Rails**

Let's see now Kafka in action.

The good news is that we have many tools available that we could add to our Ruby on Rails applications to make them work with Kafka. And there is even better news - one of these tools is a clear winner - [Karafka](https://karafka.io/).

Not only does it provide a straightforward way to implement Kafka producers and consumers, but it also provides many extras that often allow to bypass "traditional" Kafka limitations. Here is a couple of examples:

- [Dead Letter Queue](https://karafka.io/docs/Dead-Letter-Queue) - we've discussed the scenario where the processing can be blocked due to some error, so it's already apparent how useful this feature could be.
- [Active Job Adapter](https://karafka.io/docs/Active-Job/) and support for [long-running jobs](https://karafka.io/docs/Pro-Long-Running-Jobs/) - Kafka is often discouraged as a tool for background jobs processing, especially for long-running ones. With Karafka, this is simple as well.
- [Complex routing patterns](https://karafka.io/docs/Pro-Routing-Patterns/) - via regular expression
- [Virtual partitions](https://karafka.io/docs/Pro-Virtual-Partitions/) - remember the part about consumers and partitions and that partitions are the parallelization unit, and there can be only one consumer in a given consumer group for a given partition? Clearly, we cannot have more than one consumer for a partition. However, we can have further parallelization within a single partition while preserving the order of the messages in most cases, thanks to virtual partitions!
- [Web UI](https://karafka.io/docs/Web-UI-Getting-Started/) - essential for debugging. If you cannot imagine using Sidekiq without Web UI, you can only imagine how useful it could be for Kafka given the overall complexity.

Let's see what building a minimal producer and consumer would take. As this is a simple proof of concept, we don't really need two separate applications. A single one will be enough.

Assuming that you have Kafka already set up, you can start by adding the *karafka* gem to the *Gemfile:*

```

gem "karafka"

```

Right afterward, you can run the following command:

```

bundle exec karafka install

```

It's going to create *karafka.rb* config file, *app/consumers/application_consumer.rb* (a base class for all consumers), and *app/consumers/example_consumer.rb* (well, as the name indicated, an example consumer).

The *karafka.rb* config file should look more or less like this:

``` rb

# frozen_string_literal: true

class KarafkaApp < Karafka::App
  setup do |config|
    config.kafka = { 'bootstrap.servers': '127.0.0.1:9092' }
    config.client_id = 'example_app'
    # Recreate consumers with each batch. This will allow Rails code reload to work in the
    # development mode. Otherwise Karafka process would not be aware of code changes
    config.consumer_persistence = !Rails.env.development?
  end

  # Comment out this part if you are not using instrumentation and/or you are not
  # interested in logging events for certain environments. Since instrumentation
  # notifications add extra boilerplate, if you want to achieve max performance,
  # listen to only what you really need for given environment.
  Karafka.monitor.subscribe(Karafka::Instrumentation::LoggerListener.new)
  # Karafka.monitor.subscribe(Karafka::Instrumentation::ProctitleListener.new)

  # This logger prints the producer development info using the Karafka logger.
  # It is similar to the consumer logger listener but producer oriented.
  Karafka.producer.monitor.subscribe(
    WaterDrop::Instrumentation::LoggerListener.new(
      # Log producer operations using the Karafka logger
      Karafka.logger,
      # If you set this to true, logs will contain each message details
      # Please note, that this can be extensive
      log_messages: false
    )
  )

  routes.draw do
    # Uncomment this if you use Karafka with ActiveJob
    # You need to define the topic per each queue name you use
    # active_job_topic :default
    topic :example do
      # Uncomment this if you want Karafka to manage your topics configuration
      # Managing topics configuration via routing will allow you to ensure config consistency
      # across multiple environments
      #
      # config(partitions: 2, 'cleanup.policy': 'compact')
      consumer ExampleConsumer
    end
  end
end

```

The key part for us will be the *routes.draw do* block - it declares that the application will consume from the *example* topic (its all partitions) via *ExampleConsumer.*

Our *ExampleConsumer* will probably look like this:

``` rb


# frozen_string_literal: true

# Example consumer that prints messages payloads
class ExampleConsumer < ApplicationConsumer
  def consume
    messages.each { |message| puts message.payload }
  end

  # Run anything upon partition being revoked
  # def revoked
  # end

  # Define here any teardown things you want when Karafka server stops
  # def shutdown
  # end
end


```

So it only prints out the payload of each message in the batch. And *ApplicationConsumer* is merely a base class that inherits from *Karafka::BaseConsumer.*

Let's see our consumer in action now!

Start the *karafka server* process:

```

bundle exec karafka server

```

And from *rails console,* let's publish some event to *example* topic:

``` rb

3.2.2 :001 > Karafka.producer.produce_sync(topic: "example", payload: { "Karafka is awesome" => "true" }.to_json)

[c3e48c35d33d] Sync producing of a message to 'example' topic took 17.234999895095825 ms

```

And in *karafka server* output we should see something like this:

```

[b3d1d38425a2] Polled 1 messages in 277.64600002765656ms

[076ac2fd7b7b] Consume job for ExampleConsumer on example/0 started

{"Karafka is awesome"=>"true"}

[076ac2fd7b7b] Consume job for ExampleConsumer on example/0 finished in 0.18400001525878906ms

```

And that's it! That's enough to set up a communication via Kafka using Karafka!

## **Wrapping up**

We've just covered some **key aspects** of  **Kafka** - what it is, how it works, some good reasons to use it, and a simple demonstration of [the karafka framework](http://github.com/karafka/karafka) that makes Kafka straightforward with Ruby (on Rails) applications.

Stay tuned for the upcoming article that will get into more detail on **how we use Kafka at Smily**.
