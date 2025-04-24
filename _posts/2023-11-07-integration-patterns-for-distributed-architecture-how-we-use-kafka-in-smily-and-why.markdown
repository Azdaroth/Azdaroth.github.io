---
layout: post
title: "Integration Patterns for Distributed Architecture - Kafka at Smily"
date: 2023-11-07 10:00
comments: true
categories: [Architecture, Microservices, Distributed Systems, Kafka, Ruby, Rails]
canonical_url: https://www.smily.com/engineering/integration-patterns-for-distributed-architecture-how-we-use-kafka-in-smily-and-why
---

In the [last blog post](https://www.smily.com/engineering/integration-patterns-for-distributed-architecture-intro-to-kafka), we covered some fundamental concepts about Kafka. This time, let's discuss how we use Kafka in Smily, how we got where we are now, what the decision drivers were, and how the overall architecture has evolved over time.

*I originally published this article on the [Smily Engineering Blog](https://www.smily.com/engineering/integration-patterns-for-distributed-architecture-how-we-use-kafka-in-smily-and-why).*

<!--more-->

## A short story of Smily Architecture

Like most of the technological startups, Smily (or rather BookingSync at that time) started as a single monolithic application. Yet, almost ten years ago (yes, this is correct, in early 2014), the ecosystem began to grow significantly. Not only did the new ideas appear in the roadmap that were distinct enough to be separate applications (communicating with the existing application - let's call it "*Core*"), but we were also looking into opening our ecosystem to external partners interested in building an integration with us.

Being a company in its still early stage meant looking for the simplest solution to the problem. Under those circumstances, the natural way was to go with HTTP API, which resulted in the release of [API v3](https://developers.bookingsync.com/reference/) - the API that is still in use at the time of writing this article by our own applications and external Partners.

There were multiple advantages of doing so back then:

1. Synchronous communication is easy to reason about and debug, as we explained in [the first part of this series](https://www.smily.com/engineering/integration-patterns-for-distributed-architecture).
2. Familiarity - HTTP APIs are ubiquitous. Most experienced developers can get into such a project and quickly understand what happens under the hood and figure out how to work with such an ecosystem.
3. Dogfooding - using the same API that we expose to Partners for our applications meant killing two birds with one stone. It also helps with being knowledgeable and opinionated about API usage. We could propose to our partners the exact patterns, solutions, and tools we used for our apps. For example, the [synced gem](https://github.com/BookingSync/synced) for data synchronization.
4. Authentication/Authorization flexibility (thanks to [OAuth](https://oauth.net/2/)) without reinventing the wheel.

## Core-centric Model

All these points lead to the architectural model ("Core-centric Model") that could be visualized in the following way:


![CorE Centric Model](https://dev-to-uploads.s3.amazonaws.com/uploads/articles/8t1ypn3zgtos0a86jwkq.jpg)


This model was built upon two fundamental Ruby gems:

1. [API v3 Client gem](http://github.com/BookingSync/bookingsync-api)

2. [Synced](http://github.com/BookingSync/synced), a tool for keeping local models synced with their equivalent API v3 Resources (based on long-polling and periodically fetching the records in subsequent queries updated since the timestamp of the previous synchronization)

On top of HTTP API v3, we also introduced webhooks as an extra addition based on the publish/subscribe pattern, which was mostly a way to implement the Event Notification Pattern so that consumer apps don't need to wait potentially a long time for the next polling interval to act (which happens for some Partner Apps to be every hour or even less often!).

## The beginning of the problems

This architecture was sufficient and worked quite fine in the beginning, and only occasionally did it cause any more significant issues. At some point, though, problems started to happen on both Core (significant database load caused by the massive traffic in API v3 requiring a considerable number of pumas to handle it) and consumer apps (taking too much time to synchronize resources, OOMs in Siekiq workers, introducing various workarounds in the *synced* gem for large batches and various edge cases) clearly showing that this model might not be a good choice anymore.

The list of the suboptimal things in this architectural model could get pretty long, but these were some vital points:

1. Things like Authentication/Authorization flexibility are great when you need to expose API outside the internal ecosystem. For the internal apps, this is often unnecessary overhead.
2. The overhead of the HTTP protocol for internal traffic might also be unnecessary.
3. Scalability problems
    1. long-running requests
    2. batch processing from all paginated records requiring a lot of memory to process
    3. constantly high traffic in API v3 and a significant load on the Core database
    4. requests being slow or redundant (e.g., polling scheduled every 5 minutes, which could result in unnecessary requests because nothing was returned, or too many items were returned requiring pagination through multiple pages if the polling interval was too long)
    5. every application performing pretty much the same type of request, so if 10 apps needed the same resource, the same serialization on Core in the API would happen over and over again for each of them. Caching responses wasn't an option as each application was sending a different timestamp when using [updated_since flow](https://developers.bookingsync.com/guides/updated-since-flow/)
4. Reinventing the wheel with *synced* - [updated_since flow](https://developers.bookingsync.com/guides/updated-since-flow/) and storing the timestamp of the last synchronization of the data on the consumers’ side and using that as an offset in the API for a given endpoint is pretty much redoing Dumb Broker/Smart Consumer model (just like in Kafka) over the HTTP REST API in a very underoptimized way.
5. It gets pretty expensive to scale for that model when you consider resources to cover so many [pumas](https://github.com/puma/puma) and Sidekiq workers

That was the right time to rethink the entire architecture model. At the same time, given that we were a relatively small team back then, we wanted to avoid any significant re-rewrites and re-use what we had as much as possible.

In the end, the list of the requirements that we were expecting from the new architecture was the following:

- A replacement for long polling via [synced](https://github.com/BookingSync/synced)/API v3, using the same HTTP resources as we had available API v3
- Significantly smaller utilization of resources (CPU, memory) on the consumers' side
- Getting rid of a large percentage of API v3 traffic
- Decreasing database load, both in the Core application and consumers' applications
- Ability to react to changes to the resources on the consumers’ side almost right away after they happen (e.g., doing something on the `rental_created` event a few seconds after it happened)
- If using any message broker, retaining events for an arbitrarily long time (ideally indefinitely)
- Ability to replay events, especially when a new consumer joins the ecosystem (e.g. when a new internal app is introduced that requires gigabytes of data from previous years)
- Ideally, a few seconds of latency between a change on Core and the time it takes for the consumers to start processing the change, as some use cases were very time-sensitive.

## Introducing Kafka

Under these circumstances, Kafka was a natural choice, especially since it fulfilled all the requirements we had and the way we were using [synced](https://github.com/BookingSync/synced) and timestamp-based offsets with [updated_since flow](https://developers.bookingsync.com/guides/updated-since-flow/) was close to the dumb broker/smart consumer model implemented by Kafka. It was also straightforward to adapt all the components used for the serialization of resources to JSON in API v3 and do the same thing when publishing to Kafka upon every change of the resource (that would bump the `updated_at` timestamp).

Thanks to this change, our system turned into the following model:


![Core Centric Model with Kafka](https://dev-to-uploads.s3.amazonaws.com/uploads/articles/7qo950z0x0wuqedtg2gn.jpg)

It could be argued that this model was still a Core-centric one - the difference was that an extra layer (Kafka) was introduced to decouple consumer apps from the Core application. Nevertheless, it turned out to be a great success, and this change has brought considerable benefits in solving problems we used to have with the model based on *synced*/API v3*.*

Also, given how simple it was to introduce Kafka publishers in other applications (especially when comparing how much it would take to build HTTP API), it was pretty straightforward to turn that model into the following one:


![Kafka Event Lake](https://dev-to-uploads.s3.amazonaws.com/uploads/articles/pyo48jejvv2fvfv93kcq.jpg)


Thanks to that, Kafka could become a [data lake/event lake](https://aws.amazon.com/what-is/data-lake/) for the entire ecosystem if there was a need for that, and also, it will allow in the future to separate bigger applications (like Core) into smaller (micro)services.

## How did we get here?

You might be wondering at that point - how we made this happen so that we could so quickly change from using HTTP-based long-polling to Kafka, especially since one of the requirements was to keep using API v3 resources?

We developed our own framework on top of [karafka](http://karafka.io/) that made it trivial to introduce new producers and consumers, thanks to the powerful declarative DSL in the gem and adapting something that could be compared to [Change Data Capture (CDC)](https://www.confluent.io/learn/change-data-capture) pattern, but not at the database level but rather on the model level.

And given that this is almost the end of this blog post, you probably already know what the next part of this series will be about :).

For that special occasion, we will release our framework publicly (after removing some internal dependencies and reworking the entire documentation, as it's heavily based on the details of our ecosystem), so stay tuned, as this is going to be an opportunity to learn about a complete framework allowing integration of Ruby on Rails application via Kafka in a very simple way.

## Conclusion

In this blog post, we covered our old architecture model used to integrate our applications, what problems we experienced with it, and why we decided to switch to Kafka.

Stay tuned for the next part of this series which is going to introduce our framework for doing CDC on the domain level.
