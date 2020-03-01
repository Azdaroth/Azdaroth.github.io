---
layout: post
title: "A Secret Weapon For Your Rails Apps - RPC with RabbitMQ and Hutch"
date: 2020-03-01 20:01
comments: true
categories: [Ruby, Rails, Ruby on Rails, RabbitMQ, RPC, Architecture]
---

**Communication** between two or more applications is often everyday stuff, and it might seem that there is not too much to add there as this subject has been covered pretty well in the last years. Thanks to that, **multiple patterns** and **standards** have emerged. You no longer need to think about how the response format should look like for your **REST API** (go with JSONAPI and stick to the conventions) or figure out the **authentication/authorization protocol** (go with **OAuth** and the security headaches won't bother you).

However, things like format or authentication are most often the concerns that you need to solve if your **API is exposed publicly**. What if you don't need a publicly available API, but merely something that will be available for your own **(micro)services** and nothing beyond that single ecosystem? In such a case, you might go with a bit less popular, yet a more suitable approach - **RPC with RabbitMQ**.

<!--more-->

## RabbitMQ and messages

If you are not familiar with RabbitMQ, I would highly recommend reading [one of my articles](https://karolgalanciak.com/blog/2019/06/23/messages-on-rails-part-3-rabbitmq/) about it as it covers most of the fundamentals of how RabbitMq works and what would be some of its use cases. If you are not familiar with async events and used mostly to synchronous communication with HTTP REST/GrapghQL APIs, you might want to check my introductory article about [messages on Rails](https://karolgalanciak.com/blog/2019/02/24/messages-on-rails-part-1-introduction-to-kafka-and-rabbitmq/) and why it might be a superior approach for communication between applications.

## Why RPC

Now that you already know something about RabbitMQ, let's go through the benefits of using Remote Procedure Calls (and some cons as well).

One of them is no public exposure of endpoints like it's the case with most HTTP APIs (there are some ways though to "hide" your endpoints so that they are private, but that's not the usual way of approaching the problem). RabbitMQ is a separate process through which the entire communication happens, so unless you have a username/password to it, you won't be able to access it anyhow, which solves the problem of authentication. You might argue that this is similar somehow to HTTP Basic auth, but the difference here is that you don't need to implement anything extra in your application to handle the authentication.

You don't even need to implement any extra controller to handle RPC calls! On the receiver side, it would rather be similar to adding a Sidekiq job returning something, so simplifying the entire flow is another benefit.

There are also some performance benefits when it comes to RPC calls, although they might be a bit more contextual or more of a micro-optimization. When it comes to RPC calls, you don't need to perform any SSL handshakes, so you save a bit of time on that extra overhead. The request won't also need to go through the entire overhead of what happens in Rails controllers. Furthermore, RPC calls can be used for "priority" requests, which might be necessary if every second counts for the request time - sometimes you might run into a scenario that there will be way more requests coming through your app than it usually is, some of there requests will be long-running ones, and there will be not enough Unicorn/Puma/whatever-else workers/threads to handle all these requests! If you have some critical requests that cannot wait, even if a scenario like that rarely happens ever, you might want to have some way to prioritize calls and bypass the loadbalancer and make sure that some specific request will be handled possibly soon. And this is something you can easily achieve with RPC calls.

As you might expect, there will be some cons of using introducing RPC calls to your ecosystem. The biggest one is RabbitMQ itself - it's another piece of tech that you would need to learn and host somewhere, establish monitoring, and make sure it works smoothly. Another one will be some infra/glue-code that will be required to set everything up.

Fortunately, there is [hutch gem](https://github.com/gocardless/hutch), which maybe doesn't support RPC out-of-box, but it's possible to perform RPC calls using it. And it is especially great if you are using Hutch already for processing async messages as adding support for RPC won't require too much overhead!

## RPC in Rails apps with Hutch

Hutch is a pretty well-documented gem, so I would recommend getting familiar with its [Readme](https://github.com/gocardless/hutch) to learn a bit more about it.

To make RPC work with Hutch, we need to do something non-standard on both the client's and server's side. It would also be essential to understand what we are actually trying to do, especially that Hutch is supposed to be used for async messaging.

In async messaging, the client publishes some event, and that's it, it doesn't expect any response. It's quite similar on the server-side - it will do something with this message and perform another async action; maybe it will publish another event or maybe won't do anything after performing some app-specific operation.

In RPC, we want to do something similar - a client will publish some message, and the server is going to process it. The difference here is that the server is expected to return something, and we expect it to happen synchronously.

The reality is that there is no such a straight-forward way of handling the request-response cycle in bare RabbitMQ. However, RabbiMQ allows you to specify the queue to which you want to respond to so that the server can publish a message to that queue and the client can wait for a response expecting it to be published to that queue. That means that we will need another queue to handle the synchronous nature of the call.

What is more, RabbitMQ even has a built-in feature called "Direct Reply-to", which is `amq.rabbitmq.reply-to` pseudo-queue. Thanks to that, we can avoid creating a special queue for every request (and the entire overhead of managing them, like deleting the temporary queue after we are done with the call)!

### RPC with Hutch - building a client

Let's start with the more challenging part - the RPC client. The challenge comes in three different forms here:

We will need to implement the waiting-for-the-response logic.
As we are using the non-unique queue (which can be used by multiple clients at the same time), we will need to make sure that the response we consume will indeed be for the message that we sent, not some other one.
Using Hutch interface to make sure that we indeed reuse to the max everything that we also use for async messaging. For example, we want to make sure that we reuse exactly the same topic exchange as for a standard, asynchronous flow.

The first problem can be solved with some out-of-box Ruby toolset that comes in handy when dealing with threads - a ConditionVariable and Mutex. The second one requires some research on how to play with Hutch and Bunny (which is a RabbitMQ client used by Hutch) gems. The conclusion of that research would be that `Bunny::Consumer` class is something that will definitely help to consume a response. And for the last one, reading the code of the gem and understanding it is the only solution.

Here is a very simplified version of a class that could serve as a generic RPC client:

``` rb
class RpcClient
  attr_reader :broker, :connection, :lock, :condition, :consumer, :response
  private        :broker, :connection, :lock, :condition, :consumer, :response

  def initialize
    @broker = Hutch::Broker.new
    @connection = broker.open_connection
    @lock = Mutex.new
    @condition = ConditionVariable.new
    @consumer = Bunny::Consumer.new(channel, "amq.rabbitmq.reply-to", SecureRandom.uuid)
    consumer.on_delivery do |_, _, received_payload|
      handle_delivery(received_payload)
    end
    channel.basic_consume_with(consumer)
  end

  def call(routing_key, json_payload)
    lock.synchronize do
      options = {
        routing_key: routing_key,
        reply_to: "amq.rabbitmq.reply-to",
        persistence: false
      }
      topic_exchange.publish(json_payload, options)
      condition.wait(lock)
    end

    JSON.parse(response)
  end

  private

  def channel
    @channel ||= connection.create_channel
  end

  def topic_exchange
    @topic_exchange ||= channel.topic(Hutch::Config.mq_exchange, durable: true)
  end

  def handle_delivery(payload)
    @response = payload
    lock.synchronize { condition.signal }
  end
end
```

A lot is going on here, but let's focus on some key details: from the input perspective, we only need two different arguments for a generic RPC Client: a routing key and the event's payload, which is really not that different from publishing an async message. Although the difference can be easily noticed when checking the code for handling the response.

First, we need to establish an actual connection. We can reuse `Hutch::Broker` instance for that and `open_connection` method - Hutch knows how to use Bunny components, and it will use the same config as for publishing async messages, so that's perfect for us. Next, we need to add some boilerplate code so that we can reuse the same topic exchange as if we were sending a message via `Hutch.publish`. Now, that we have a connection established, and a channel created, we can declare a new Bunny Consumer and define how it should behave when the response arrives. The code might look a bit confusing if you are not used to working with low-level Ruby primitives for working with threads, but the entire logic comes down to the following flow: we want to publish a message to a declared topic exchange (using a proper routing key and also specifying `reply_to` queue) and make sure that the execution of the Ruby code will stop at some point - this is where we need `condition.wait(lock)` inside `lock.synchronize` block. However, when the response arrives, we want to resume the execution of the code, which is done via `lock.synchronize { condition.signal }`. And once we have JSON response, we want to parse it and return a hash.

That's what it takes to implement a simple RPC Client, which is not far from being a production-ready, although it misses some essential points. One of them would be handling timeouts (currently, it will be waiting indefinitely for the response from the server). Another one would be closing connections after receiving a response.

### RPC with Hutch - building a server (consumer)

Now that we've finished building the most complex piece of the puzzle, let's finish the missing part that is going to be pretty straight-forward - building a server.

Our simplest possible Hutch consumer could look like this:

``` rb
class ExampleConsumer
  include Hutch::Consumer
  consume "example.routing.key"

  def process(message)
    do_something_fancy_with_the_message_and_finish_here(message)
  end
```

That would totally work for async messaging as we don't need to return any response, and we might not necessarily need to publish another event either. But how do we send the response back to the client?

What we need to do at this point is merely publish another event. However, we can't do it via `Hutch.publish`, due to two reasons that we went through before: we need to publish the message using a specific routing key (remember the `reply_to`?), and also, we need to preserve the correlation ID so that the consumer can identify the response that was supposed to be delivered to only that consumer - remember that multiple RPC calls can be performed at the same time and based on our implementation of the client that uses "amq.rabbitmq.reply-to", all the responses will be published to the same queue as well. The correlation ID is the only thing that will allow consumers to distinguish the messages and who the expected receiver is.

After going through Hutch's code, it will turn out that the `message` object is almost everything that we need here. Publishing the response could look like this:

``` rb
message.delivery_info.channel.default_exchange.publish(
  { success: true, other_response_payload_attribute: "value" }.to_json,
  routing_key: message.properties.reply_to,
  correlation_id: message.properties.correlation_id
)
```

And that's it what it takes to build the server part for RPC calls with Hutch!

## Wrapping Up

RPC with RabbitMQ can be a great alternative to HTTP APIs for communication between applications where you don't need to expose your API endpoints publicly. If you already use Hutch gem for async messages, this approach will require very little extra overhead to get started once you get to know some of its internals. And even if you don't, there are still multiple benefits of RPC that you might want to consider.
