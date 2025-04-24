---
layout: post
title: "Integration patterns for distributed architecture"
date: 2023-09-08 10:00
comments: true
categories: [Architecture, Microservices, Distributed Systems, Integration]
canonical_url: https://www.smily.com/engineering/integration-patterns-for-distributed-architecture
---

**Distributed architectures** have been growing in popularity for quite a while for some good reasons. The rise of **cloud services** making the deployments simpler, as well as the ever-growing complexity of the applications, resulted in a **shift away from monolithic** architecture for many technical ecosystems. Microservices have emerged as an alternative solution offering **greater modularity, scalability, reliability, agility, and ease of collaboration between multiple teams**. Nevertheless, these benefits **don't come for free**. The price to pay could be significant due to many factors, and one of them is dealing with some challenges that don't necessarily happen when working on a monolith. One of such challenges is establishing the best way of **integration and communication between services**.

Let's examine the **four primary ways** services can be integrated and how they all play their part in our architecture in Smily (formerly BookingSync). This article aims to provide a general overview of these patterns, and we will cover them in more detail in the upcoming blog posts.

*I originally published this article on the [Smily Engineering Blog](https://www.smily.com/engineering/integration-patterns-for-distributed-architecture).*

<!--more-->

##  Four Primary Ways of Integration of Microservices

Are there really four ways of integration/communication in distributed architecture? Isn't it just HTTP API and async events?

It turns out that there are some other ways. One is often considered an anti-pattern, and the other is a bit questionable as a standalone communication pattern as it usually requires some extra one to be involved, but it's still worth mentioning it.

### Shared database


![Image description](https://dev-to-uploads.s3.amazonaws.com/uploads/articles/zxpqq7rly1scqofqax6i.jpg)

Using a shared database is probably the simplest way to establish interaction ("communication" might be an overstatement in that case). You might have two or more applications using the same database without extra overhead, such as building extra APIs or publishing events, so it sounds very appealing, at least at the beginning.

That's why using a shared database is often considered an anti-pattern - as it can easily lead to a poor design with extremely tight coupling and limited scalability. Just think about using a shared PostgreSQL database - coupling to the same schema is just the beginning of potential problems. Deadlocks can also become a headache at some point. And what about a massive number of connections and a significant load on the database cluster causing performance degradation? However, is it truly an anti-pattern?

Let's think about the definition of the "anti-pattern". It's usually defined as something that might initially look like a good idea but is a wrong choice in the end. If we introduce tight coupling and have limited scalability, it could be indeed an anti-pattern.

But at the same time, it might not be a problem at all. Or maybe these trade-offs are perfectly justified. It really all comes down to a trade-off analysis and making deliberate decisions.

Imagine that you have a single monolithic Ruby on Rails application. And at some point, you want to introduce some Business Intelligence that might require heavy reporting. It could turn out that due to some technological choices and the type of analysis of the data you will perform, a new service will be required. For example, a new Python app as Python is often a preferred solution in that domain. This app will need access to the data from the original monolithic solution that will only involve a periodic reading of the data.

Which pattern would be more appropriate?

1. Building a dedicated REST/GraphQL API for the new service to fetch the data

2. Introducing Kafka to the system and doing Change Data Capture to let the new app consume the stream of the events

3. Connecting to the database of a monolithic application

Given the complexity and time needed to implement the first and second options, the shared database will probably be the best choice. And it's not that the dedicated API or doing CDC over Kafka are wrong solutions - having them could be highly beneficial for multiple reasons, and they would also work in this particular case, but they are not the right solutions to this problem. And the shared database is not perfect either. Although there are ways to improve it, for example, connecting to the read-only replica instead of the master to avoid excessive load that could cause performance degradation for the primary monolith.

There are also other cases where using a shared database might be an interesting option, for example, as a temporary mean of communication between services when breaking down a monolith into multiple applications.

Claiming that a shared database is anti-pattern is simply harmful as it might be a good choice for specific use cases. Just because it will be a bad one for many of them, it doesn't mean it needs to be crossed out entirely. Architecture is ultimately about trade-offs and supporting the key non-functional requirements, so making well-informed decisions is essential.

This pattern has such a bad reputation, even though it's fine in a couple of use cases, that in the near future, we will most likely publish a separate article covering this integration pattern in more detail.

And how do we use this pattern in Smily?

There are two distinct use cases:

1. Business Intelligence. We have a dedicated service responsible for data preparation and storing the data in the PostgreSQL database, and we use [AWS Quicksight](https://aws.amazon.com/quicksight/) as a Business Intelligence tool that reads the data from the read-only replica.

2. Avoiding processing a massive amount of data by all microservices that need it and just letting a single application do it, letting other ones read from its database. This use case is fairly complex, and deciding how to architect it that way deserves a separate article. Yet, to keep it simple for now, it's one of the cases where there was no perfect solution, and it was about picking the one that is the lesser evil. Especially when comparing the cost of the potential solutions - processing massive amount of data is not cheap, especially when considering the price of required AWS EC2 instances and the price for storage on AWS EBS volumes.


## File transfer


![Image description](https://dev-to-uploads.s3.amazonaws.com/uploads/articles/i5yg95wi0z2nqjbj363d.jpg)

This is not the typical pattern you think of when integrating the microservices. Especially since the first thought it brings is probably the old-school FTP. It's essentially about exporting the data to the file and letting the consumer take care of it. It's not necessarily a standalone pattern, as it requires some other communication pattern (such as synchronous HTTP API). Yet, it's pretty handy when moving a large volume of data, so let's discuss it separately.

Imagine the following use case - there is a need to export gigabytes of data periodically for multiple consumers. Fetching some data is perfectly normal for almost every HTTP API, and you could use pagination when many records are involved. Still, this may not be the most efficient solution if we are talking about gigabytes of data.

Fortunately, there is a simple alternative - export the data to a CSV file (e.g., via [postgres-copy gem](https://github.com/diogob/postgres-copy) ), upload the file to some cloud storage, such as AWS S3, and return the links in the API.

And this is exactly how we use this pattern in Smily in one of our public APIs! The results are partitioned by day, and a single response contains a few hundred links to AWS S3 containing CSV files that are periodically uploaded in the background jobs, which massively limits the traffic in our API (although some Sidekiq workers take care of exporting the data) and simplifies the entire process for the API consumers as they can get everything just in a single request and processing the files can be easily parallelized, thanks to partitioning by day.

## Synchronous Request-Response


![Image description](https://dev-to-uploads.s3.amazonaws.com/uploads/articles/bhiu5xjk4cyqunl7c20h.jpg)

It is probably the most common communication pattern in distributed architectures. And for some good reasons. At least if we consider the typical use case, HTTP API, like REST API. We cannot forget here about RPCs (Remote Procedure Calls), which have some great benefits, and even though it might be a less popular integration pattern, it can be a  superior choice compared to REST or GraphQL API.

RPC definitely deserves a separate article as it comes with different flavors ([gRPC](https://grpc.io) has been growing in popularity for quite a while, but even [RabbitMQ](https://www.rabbitmq.com), which is a message broker for typically asynchronous messaging makes it relatively straightforward to implement RPC. And there is [SOAP](https://en.wikipedia.org/wiki/SOAP), but at this point is pretty much dead), and we are going to cover it in more detail in the future.

And for now, let's focus on typical HTTP APIs and some of their significant benefits:
- HTTP APIs are ubiquitous, both REST and GraphQL, so most of the experienced developers are familiar with the concepts and the expected problems and patterns to handle them (such as retrying failed requests, timeouts, circuit breakers, idempotency keys)

- No extra tech is required to establish the communication, such as message brokers, so there is no additional overhead of managing new infrastructure, establishing extra monitoring, etc.

- Multiple standards are available (for example, [JSONAPI](https://jsonapi.org) or the GrapQL itself), so there is no need to reinvent the wheel for the payload structure

- Simple to reason about thanks to synchronous nature - the feedback is immediately available

- Flexibility of authentication and authorization and well-known standards for that ([JSON Web Tokens](https://jwt.io), [OAuth](https://oauth.net/2/))

 As great as it sounds, this integration pattern can be a wrong choice for many cases and reasons:

- Complex/high-latency operations are involved - if generating a response takes minutes or even hours, synchronous communication is definitely not an efficient solution. Even though you could, to some extent, design it so that you don't need to introduce asynchronous events, e.g., by having an endpoint where you could enqueue the operation to be processed and then periodically check the completion status, it doesn't mean that it's the best way to solve this problem.

- Increased coupling - using HTTP APIs leads to a way tighter coupling than async messaging, as you need to know quite a lot about the service you are calling. Also, when one service is down, the failure can propagate to the other services.

- Scalability - the synchronous nature of communication involves way more overhead than the async one.

- Fetching huge volumes of data - even though it's possible to do this via REST API, as demonstrated in the previous section about file transfers, it might be a highly suboptimal choice for many use cases, often leading to reinventing Kafka over REST API (once we cover Kafka in more detail, that phrase will become clearer). Imagine that you operate on millions of records, and somehow, you have already managed to fetch these records via API. For the subsequent GET calls, you only want to get the records that have changed since the last request. Usually, this is implemented by storing timestamps and providing these timestamps to filter out the records that have been updated since that time in the subsequent calls, which is, to some extent operating with timestamp-based offsets. It might sound like a decent solution on a small scale, but for a massive volume of data that is updated often, and when you want to get this data as quickly as possible and by multiple other services, it quickly becomes ugly. It requires handling a massive number of requests, which only increases with a growing number of endpoints where this happens, and the same thing is performed each time for every service that cannot be cached easily, as the response would depend on the timestamps. And even when using some fixed timestamps with the same fixed value, storing all the cache would be another challenge. Just because it might be doable via REST API, it doesn't mean it's the best way to do it.

- Not suitable for complex workflows - it can become quite awkward when you implement sagas with REST API and deal with compensating transactions upon failures and generally error handling.

It turns out that the synchronous request-response communication style is not necessarily a clear winner for most cases, but again, architecture is about the trade-offs.

And how do we use it in Smily?

To start with, we have two public APIs:
- [The primary general-purpose one] (https://developers.bookingsync.com/) that we use quite heavily for internal applications as well

- [A more specialized one](http://channel-api.developers.bookingsync.com/)

On top of that, we have some private APIs, for example, as backends for Ember single-page apps or for typical inter-service communication.

And, of course, we use so many APIs as consumers, both REST APIs and GraphQL APIs, so in general, HTTP APIs are abundant in our ecosystem.

## Asynchronous Events

To a limited extent, we've covered this already as contrasting integration pattern to synchronous request-response communication style.

When thinking about async messages or events, [RabbitMQ][https://www.rabbitmq.com] or [Kafka](https://kafka.apache.org) might be the things that come into your mind as typical examples. We will get into these in a moment, but let's start with some not-so-obvious pattern - [webhooks](https://zapier.com/blog/what-are-webhooks/).

### Webhooks

Yes, webhooks are also asynchronous messages, and they can be great as both additions to HTTP APIs or as a standalone pattern, that lets you benefit from the push flow instead of pulling the data from the API. That way, you can receive messages easily, even from third-party applications, so it's possible to have async events without involving any extra broker.

To benefit from the webhooks, you need to expose an HTTP endpoint (so it involves some extent HTTP API) to which a message will be delivered, typically in JSON, XML, or form-encoded format, often secured by an extra signature, so that we can tell if whoever is sending the given webhook is a legit sender.

A simple type of webhook could look something like this:

```
POST https://my-awesome-app.com/api/webhooks?event=booking_created&id=1&signature=123
```

And that's how we can get notified that a booking (notice the `event` param with `booking_created` value) with an ID of `1` has just been created. And there is also a signature for security purposes that hopefully would look a bit more secure in a real-world case.

In Smily, webhooks are an integral part of our [primary public API](https://developers.bookingsync.com) and are highly recommended for building a possibly robust integration. You can find documentation about them [here](https://developers.bookingsync.com/guides/webhook-subscriptions/).

### Message brokers

Now, let's focus on the more classic case where a middleman called a "message broker" connects producers of the messages with their consumers, allowing the implementation of the publish/subscribe model (or point-to-point messaging where the message is delivered to a single specific consumer instead of multiple subscribers). Thanks to that, you can publish a single event, and the message broker will ensure it's consumable by all the appropriate subscribers based on the defined config and routing, which depend on the specific message broker.

The differences between message brokers can be pretty significant, and perhaps the most meaningful one is what kind of model they implement, as we have two different types of models:

- Smart broker/dumb consumer - the message broker is responsible directly for delivering the message to the consumer so that the consumer just waits to process events. Notable example: [RabbitMQ](https://www.rabbitmq.com)

- Dumb broker/smart consumer - the messages are available in the broker, but it is up to consumers to deal with these messages. Notable example: [Kafka](https://kafka.apache.org)

It might already sound complex when choosing the message broker when you are sure you need async messaging. There is bad news, though: it only gets more complex from this point.

The sneaky issue is that most of the problems, at least defined in a generic way, can be solved using any of these combinations. Sometimes it might require a bit more effort for some use cases or introducing some extra third-party tool, but in general, you should be able to achieve the result by picking any of these.

The topic is so broad and complex that we will publish a couple of follow-up articles to cover the differences, among many other things, but to at least have a simple overview now, let's cover two brokers: RabbitMQ and Kafka.

#### RabbitMQ


![Image description](https://dev-to-uploads.s3.amazonaws.com/uploads/articles/81fcanljadmprgotkgz7.jpg)

RabbitMQ is essentially about publishing messages to queues from which consumers can read and process them. It might sound a bit like using Redis and Sidekiq, where jobs are pushed to the queues, and Sidekiq workers take them and handle the processing. Still, there is one essential difference - when using RabbitMQ, producers don't directly push to the queues, they push messages to the exchanges, ultimately responsible for delivering messages to the proper queues that are bound based on the routing keys. The consumers within a single consumer group can subscribe to the same queue competing for the messages (for parallelization), and once the message gets processed, it's gone from the broker.

This design has a profound impact on what RabbitMQ is capable of. Exchanges make it possible to implement a publish/subscribe model with multiple consumer groups and the killer feature of RabbitMQ - smart routing based on the routing key (which is an extra attribute of the message), including wildcard matches.

For example, you can publish messages with the following routing keys:

- "rentals.eu.france.paris"
- "rentals.eu.france.nevache"

Suppose you want the consumer to process messages concerning only Nevache (so the ones with "rentals.eu.france.nevache"). In that case, it's pretty straightforward  - use "rentals.eu.france.nevache" as a binding key. However, what if you want to process all messages regarding rentals? Or all rentals from France? You can use wildcard matching! In this case, "rentals.*" and "rentals.eu.france.*" would be the appropriate binding keys to make it work, and the exchange will be smart enough to deliver the desired messages to the queues (which works only for a *topic* exchange, but don't worry about it at this point - we are going to cover all types of exchanges in the upcoming article).

Also, what is interesting about RabbitMQ is that you can implement RPC, thanks to the callback queues.

On top of that, we have priority queues and dead-letter exchanges.

#### Kafka


![Image description](https://dev-to-uploads.s3.amazonaws.com/uploads/articles/vbt7o5k8xrcw49ilbzmv.jpg)

Kafka is a distributed streaming platform that takes a different approach from RabbitMQ. Kafka essentially stores all the messages in an append-only log. Producers publish messages to the topics that can be split into multiple partitions, and each partition represents a separate append-only log in which events are ordered. And every message in the partition has its own index (offset) based on which we can identify its position in the log.

The consumers read data from partitions periodically, and once they are done with a batch of events, they persist the current offset and move on to another batch. What is important is that within one consumer group, a single partition can have only a single consumer (as this is the only way to guarantee strict ordering).

This design is what makes Kafka so powerful. What is more, you can even replay events - regardless of whether it's the consumer that has already processed the message (just update the current offset to the earlier one) or a new one from a new consumer group that can start processing things from the beginning so there is even no need to republish the events to make them available for processing.

And as far as the retention goes, there is a lot of flexibility. You can define it based on the storage size or time. For example, you can configure it to store messages for 3 days, and everything beyond that will be automatically removed. Or you can configure it to retain messages forever (well, approximately, there is infinite retention but you can keep messages for hundreds of years).

Performance and ability to scale is another strong point of Kafka. If it's good enough for activity tracking at LinkedIn, it's not something you might need to worry for quite a while, at least if the consumers are not bottlenecks and the number of partitions is optimal.

Activity tracking, log/events aggregation, anomaly detection, and (nearly) real-time data processing are quite typical use cases for Kafka as well, thanks to the ease of integrating it with so many other tools like [Apache Flink](https://flink.apache.org).

#### RabbitMQ vs. Kafka

Choosing between RabbitMQ and Kafka is not a simple decision. Nevertheless, let's summarize it with some general hints and guidelines.

Use RabbitMQ when you:
- need complex routing
- don't need to retain messages or replay them
- need priority queues
- need to support RPC calls
- need a "simple" broker to get the job done

Use Kafka when you:
- need to handle an extreme throughput of messages
- need strict ordering of the messages
- need to retain messages for an extended time or replay them
- do the actual stream processing

Although in reality it's a bit more complex than that. A lot depends on the overall ecosystem, throughput, available tools or even... your monitoring practices.

To give you an example, in my experience, the integration via RabbitMQ generally works very smoothly and requires very little attention. With Kafka, it's a bit different story - if you don't have good monitoring practices, I wouldn't even consider it as a possible option. For example, suppose a message cannot be processed due to some error. In that case, processing from a given partition will be blocked until the issue is addressed, so you'd better have proper monitoring to tell you about this if you cannot avoid it in the first place (or use a third-party tool that implements a dead-letter queue). When it takes too long to process messages, you might also expect odd things to happen, like constantly reprocessing the same batch and never finishing. So again, monitoring is critical here.

On the other hand, it's still possible to have the strict ordering of the messages in RabbitMQ - at least if you don't have multiple consumers competing for the messages from a single queue. But that will have an impact on the scalability and performance.

Ultimately, the final choice requires carefully evaluating the trade-offs and a deep understanding of the ecosystem where the broker will be used.

And the final question: which one do we use in Smily? We use both, for different use cases. And for both of them, we've developed custom gems that massively simplify using both Kafka and RabbitMQ.

For RabbitMQ, we use [hermes-rb](http://github.com/BookingSync/hermes-rb) which has been available for quite a while, and for Kafka, we use something that is not yet publicly available, but it will be very soon. And both will be covered in upcoming articles, including more details on how and why we use them.

## Conclusions

In this article, we've covered **four primary integration patterns** for the distributed architecture: **shared database**, **file transfer**, **synchronous request-response**, and **asynchronous events**. We've also discussed the differences between **Kafka** and **RabbitMQ** and briefly mentioned how we apply these patterns in Smily.

Stay tuned for the upcoming articles as they will go much deeper, especially about asynchronous events.
