---
layout: post
title: "The Story of a Critical Issue With Kafka"
date: 2021-10-10 08:00
comments: true
categories: [Kafka, Ruby on Rails, Ruby, Rails]
---

Recently, I've had an unfortunate opportunity to deal with a very unexpected issue with Kafka that had quite terrible consequences. The exact origin of the issue is yet to be discovered; nevertheless, the process leading to the final solution to the problem and the fix itself were interesting enough that I decided to write a quick blog post about it as it might be potentially valuable to someone who also encounters a similar problem.

<!--more-->

## How the issue was diagnosed

Suddenly, after one of the deployments (nothing related to any change around Kafka or [`karafka`](http://github.com/karafka/karafka)/[ruby-kafka](http://github.com/zendesk/ruby-kafka/) gems that we use in the app) we've started to receive a massive number of error traces in Datadog APM (precisely, `Kafka::ConnectionError: Connection error Errno::ETIMEDOUT: Connection timed out` inside `kafka.request.join_group` span) and the number of API calls drastically decreased as well (expressed by `api.calls{*}` metric from `ruby-kafka` integration with Datadog APM). It turned that no consumer was able to join the consumer group for this particular application. What was even more strange, the config for this application and its Karafka consumers was the same as for other applications, so there must have been something about this consumer group.

But to verify this, we had to check if it was possible to join this consumer group from a different application, e.g., from the Rails console. There is no simple API for doing such a thing, so the only thing left to me was to study the code of [ruby-kafka](http://github.com/zendesk/ruby-kafka/) and figure out how to connect all the dots. That was quite an effort, but I eventually came up with something looking like this:

``` rb
seed_brokers = ENV["KAFKA_SEED_BROKERS"]
client_id = "the_name_of_the_consumer_group"
client = Kafka::Client.new(seed_brokers: seed_brokers, client_id: client_id)
group_id = "the_name_of_the_consumer_group"
consumer = client.consumer(group_id: group_id)
cluster = client.consumer(group_id: group_id).instance_variable_get("@cluster")
cg = Kafka::ConsumerGroup.new(cluster: cluster, logger: Rails.logger, group_id: group_id, session_timeout: 10, rebalance_timeout: 10, retention_time: -1, instrumenter: instrumenter = Kafka::Instrumenter.new(client_id: client_id), assignment_strategy: nil)
cg.subscribe("some_example_topic")
cg.join
```

It's super hacky and dirty (especially using `instance_variable_get`), but it did the job. The result was that it was possible to join all the consumer groups from the different applications except this problematic one! That meant the issue was not with the application but something on the Kafka cluster side. As the cluster is not a self-hosted one but an AWS MSK service, we had limited capabilities to debug the problem. However, we needed the fix as soon as possible.

Well, if the problem is just with one consumer group, why not create the new one? And manually set the offset for every topic/partition just like in the original consumer group so that we don't need to reprocess all the events?

## How the issue was addressed

It turned out that it's a straightforward thing to do, and the offsets are the only thing we care about. That way, it made hardly a difference for the application if it uses the original consumer group or the new one.

To get the offsets for all topics and partitions, I ran the following command:

```
kafka-consumer-groups.sh --describe --group the_name_of_the_consumer_group --bootstrap-server KAFKA_SERVER_URI
```

The output followed this pattern:

```
GROUP                                TOPIC          PARTITION  CURRENT-OFFSET  LOG-END-OFFSET  LAG             CONSUMER-ID     HOST            CLIENT-ID
the_name_of_the_consumer_group       topic_name     1          123             124             1               -               -               -
the_name_of_the_consumer_group       topic_name     2          100             200             100             -               -               -

// more topic/partitions
```

What I had to do in the next step was to extract TOPIC/PARTITION/CURRENT-OFFSET values and prepare commands that will set the offsets for the new consumer group, let's call it `the_name_of_the_consumer_group_2`. Easily doable with few lines of Ruby.

To set the offset for a given topic/partition for the new consumer group, it turned out that it needed to be done in 2 steps:

-  Reset the offset (set to beginning):

```
kafka-consumer-groups.sh --bootstrap-server KAFKA_SERVER_URI --group the_name_of_the_consumer_group_2 --reset-offsets --to-earliest --topic TOPIC_WITH_PARTITIONS --execute
```

The expected format of `TOPIC_WITH_PARTITIONS` is e.g. `topic_name:1`.

- Shift offset (from 0) by a given value:

```
kafka-consumer-groups.sh --bootstrap-server KAFKA_SERVER_URI --group the_name_of_the_consumer_group_2 --reset-offsets --shift-by OFFSET --topic TOPIC_WITH_PARTITIONS --execute
```

To prepare the script with interpolated `TOPIC_WITH_PARTITIONS` and `OFFSET` values, I performed the following steps:

-  Assign output to the `config` variable (excluding the headers):


``` rb
config = "the_name_of_the_consumer_group       topic_name     1          123             124             1               -               -               -
the_name_of_the_consumer_group       topic_name     2          100             200             100             -               -               -"
```

- Build the commands:

``` rb
commands = config.split("\n").map do |line|
  topic = [line.split(/\s+/)[1], line.split(/\s+/)[2]].join(":")
  offset = line.split(/\s+/)[3]

  "kafka-consumer-groups.sh --bootstrap-server KAFKA_SERVER_URI --group the_name_of_the_consumer_group_2 --reset-offsets --to-earliest --topic #{topic} --execute ; kafka-consumer-groups.sh --bootstrap-server KAFKA_SERVER_URI --group the_name_of_the_consumer_group_2 --reset-offsets --shift-by #{offset} --topic #{topic} --execute"
end
```

I executed these commands, changed the name of the consumer group in the application form `the_name_of_the_consumer_group` to `the_name_of_the_consumer_group_2`, and everything was fine again!


## Wrapping up

When using any complex piece of tech like Kafka, it's essential to not only have proper monitoring established but also have a good understanding of how it works. That knowledge will definitely pay off if some unexpected issue happens.
