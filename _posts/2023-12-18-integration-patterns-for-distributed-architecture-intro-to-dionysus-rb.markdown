---
layout: post
title: "Integration Patterns for Distributed Architecture - Intro to dionysus-rb"
date: 2023-12-18 10:00
comments: true
categories: [Architecture, Microservices, Distributed Systems, Ruby, Rails, Kafka]
canonical_url: https://www.smily.com/engineering/integration-patterns-for-distributed-architecture-intro-to-dionysus-rb
---

[In the previous blog post](https://www.smily.com/engineering/integration-patterns-for-distributed-architecture-how-we-use-kafka-in-smily-and-why), I promised we would introduce something special this time. So here we go - meet almighty [Dionysus](http://github.com/BookingSync/dionysus-rb), who knows how to make the most of Kafka.

*I originally published this article on the [Smily Engineering Blog](https://www.smily.com/engineering/integration-patterns-for-distributed-architecture-intro-to-dionysus-rb).*

<!--more-->

## Change Data Capture

Change Data Capture is a popular pattern for establishing communication between microservices - it allows to turn all inserts/updates/deletes for all rows in any table into individual events that other services could consume, which would not only provide a way to notify the other service about the change but also to transfer the data.

Thanks to tools like [Debezium](http://debezium.io), this is relatively straightforward to implement if you use Kafka. However, this approach has one serious problem - coupling to the database schema of the upstream service.

Individual tables and their columns often don't reflect the domain correctly in the upstream service, especially for relational databases. And for downstream microservices, it would be even worse. Not only your domain model might be composed of multiple entities (think of Domain-Driven Design Aggregates), but some attributes' values might be a result of a computation depending on more than a single entity, or it might be desired to publish some entity/aggregate change if there is a change in some dependency. For example, you might want to publish an event that some Account got updated when the new Rental is created to propagate the change of a potential `rentals_count` attribute.

Such an approach is quite natural when building HTTP APIs as it's simple to expose resources that don't directly map to database schema. Yet, with the CDC, this might be challenging. A potential workaround would be creating dedicated database tables that would store the data in the expected format and refresh them based on dependencies in the domain (so updating `rentals_count` in an appropriate row for a given Account after a new Rental is created if considering the example above), which would be pretty similar to materialized views. Nevertheless, it's still more like a workaround to comply with some constraints - in that case, it would be CDC operating on database rows.

A more natural approach would be CDC on the domain-model level. Something that would be close to defining serializers for REST APIs.

Meet almighty Dionysus, who knows how to make the most of karafka to achieve the result.

## Dionysus-rb

Dionysus is quite a complex gem with multiple features, and some of them could use a separate blog post, which is something that we are likely to publish in the near future. Yet, the gem's documentation would be your best friend for now. Keep in mind, though, that this has been a private gem for a long time, so at the time of writing this article, some parts of the documentation might not be super clear.

Let's now implement a simple producer and consumer to demonstrate the gem's capabilities. Before releasing anything to production, read all the docs first. The following example is supposed to show the simplest possible scenario only, which is far from something that would be production-grade.

## Example App

Let's start with the producer.

### Producer

First, generate a new application:

```
rails new dionysus_producer
```

and add `dionysus-rb` to the Gemfile:

```
gem "dionysus-rb"
```

Let's create the database as well:

```
rails db:migrate
```

And now, we can create a `karafka.rb` file with the following content:

``` rb

Dionysus.initialize_application!(
  environment: ENV["RAILS_ENV"],
  seed_brokers: ["127.0.0.1:9092"],  # assuming that this is where the kafka is running
  client_id: "dionysus_producer",
  logger: Rails.logger
)
```

For a simple demo, let's assume that we will have a User model on both the producer and consumer side with a `name` attribute to keep things simple.

Let's generate the model:

```
rails generate model User name:string
rails db:migrate
```

And let's make this model publishable:

``` rb
class User < ApplicationRecord
  include Dionysus::Producer::Outbox::ActiveRecordPublishable
end
```

We will also use a transactional outbox pattern to ensure maximum durability so that we don't lose messages. For the sake of optimization, we will also publish messages after the commit.

In the production setup, you should also run an outbox worker as a separate process so that it can pick up any messages that failed for some reason, but again, to keep things simple, we are not going to do this for this demonstration.

Let's generate the outbox model:

```
rails generate model DionysusOutbox
```

And use the following migration:

``` rb
class CreateDionysusOutbox < ActiveRecord::Migration[7.0]
  def change
    create_table(:dionysus_outboxes) do |t|
      t.string "resource_class", null: false
      t.string "resource_id", null: false
      t.string "event_name", null: false
      t.string "topic", null: false
      t.string "partition_key"
      t.datetime "published_at"
      t.datetime "failed_at"
      t.datetime "retry_at"
      t.string "error_class"
      t.string "error_message"
      t.integer "attempts", null: false, default: 0
      t.datetime "created_at", precision: 6, null: false
      t.datetime "updated_at", precision: 6, null: false

      # some of these indexes are not needed, but they are here for convenience when checking stuff in console or when using a tartarus for archiving
      t.index ["topic", "created_at"], name: "index_dionysus_outboxes_publishing_idx", where: "published_at IS NULL"
      t.index ["resource_class", "event_name"], name: "index_dionysus_outboxes_on_resource_class_and_event"
      t.index ["resource_class", "resource_id"], name: "index_dionysus_outboxes_on_resource_class_and_resource_id"
      t.index ["topic"], name: "index_dionysus_outboxes_on_topic"
      t.index ["created_at"], name: "index_dionysus_outboxes_on_created_at"
      t.index ["resource_class", "created_at"], name: "index_dionysus_outboxes_on_resource_class_and_created_at"
      t.index ["resource_class", "published_at"], name: "index_dionysus_outboxes_on_resource_class_and_published_at"
      t.index ["published_at"], name: "index_dionysus_outboxes_on_published_at"
    end
  end
end
```

And run the migration:

```
rails db:migrate
```

And include the outbox module in the model:

``` rb
class DionysusOutbox < ApplicationRecord
  include Dionysus::Producer::Outbox::Model
end
```

We can move on now to more Kafka-related things - topics. Or rather a single topic - to publish users. Let's wrap it in the `dionysus_demo` namespace so the actual Kafka topic name will be `dionysus_demo_users`.

We will also need to define two serializers:
the primary one that infers other serializers based on the model  class (`DionysusDemoSerializer`)
the actual serializer for the model (`UserSerializer`)

Knowing all these things, let's create `dionysus.rb` initializer:

``` rb
Rails.application.config.to_prepare do
  Karafka::App.setup do |config|
    config.producer = ::WaterDrop::Producer.new do |producer_config|
      producer_config.kafka = {
        'bootstrap. servers': 'localhost:9092', # this needs to be a comma-separated list of brokers
        'request.required. acks': 1,
        "client.id": "dionysus_producer"
      }
      producer_config.id = "dionysus_producer"
      producer_config.deliver = true
    end
  end

  Dionysus::Producer.configure do |config|
    config.database_connection_provider = ActiveRecord::Base
    config.transaction_provider = ActiveRecord::Base
    config.outbox_model = DionysusOutbox
    config.default_partition_key = :id # we don't care about the partition key at this time, but we need to provide something
    config.transactional_outbox_enabled = true
    config.publish_after_commit = true
  end

  Dionysus::Producer.declare do
    namespace :dionysus_demo do
      serializer DionysusDemoSerializer

      topic :users do
        publish User
      end
    end
  end
end
```

And let's create the serializers mentioned above:

``` rb
class DionysusDemoSerializer < Dionysus::Producer::Serializer
  def infer_serializer
    "#{model_klass}Serializer".constantize
  end
end
```

The only method we care about at this stage is `infer_serializer`. The implementation will be pretty simple to infer the `UserSerializer` class from the' User' model.

And the second serializer:

```
class UserSerializer < Dionysus::Producer::ModelSerializer
  attributes :name, :id, :created_at, :updated_at
end
```

Now, let's run the Rails console and see how everything is working:

``` rb
User.create!(name: "Dionysus")

DionysusOutbox.last
```
The outbox should look like this:
``` rb
#<DionysusOutbox:0x0000000112e2b400
 id: 1,
 resource_class: "User",
 resource_id: "1",
 event_name: "user_created",
 topic: "dionysus_demo_users",
 partition_key: "[FILTERED]",
 published_at: Fri, 08 Dec 2023 13:59:45.541653000 UTC +00:00,
 failed_at: nil,
 retry_at: nil,
 error_class: nil,
 error_message: nil,
 attempts: 0,
 created_at: Fri, 08 Dec 2023 13:59:45.481140000 UTC +00:00,
 updated_at: Fri, 08 Dec 2023 13:59:45.481140000 UTC +00:00>
```

Having some timestamp in `published_at` means the record was published successfully to Kafka. So we are done as far as the producer goes!

Let's add a consumer that will be able to consume these messages.

### Consumer

First, generate a new application:

```
rails new dionysus_producer
```

and add `dionysus-rb` to the Gemfile:

```
gem "dionysus-rb"
```

Let's create the database as well:

```
bundle exec rake db:migrate
```

And now, we can create a `karafka.rb` file with the following content:

``` rb
Dionysus.initialize_application!(
  environment: ENV["RAILS_ENV"],
  seed_brokers: ["127.0.0.1:9092"],  # assuming that this is where the kafka is running
  client_id: "dionysus_producer",
  logger: Rails.logger
)
```

As the consumer is going to consume events related to the User, let's create a model for it:

```
rails generate model User name:string synced_id:bigint synced_created_at:datetime synced_updated_at:datetime synced_data:jsonb
```

`synced_id` is the reference to the primary key on the producer side,  and `synced_created_at`/`synced_updated_at` are timestamps from the producer, and `synced_data` is a JSON containing all the attributes that were published.

Let's run the migration:

```
rails db:migrate
```

We will need  to do two more things:
declare which topic we want to consume from - we need topic `users` under the `dionysus_demo` namespace
infer the User model for User-related models - we will do this via `model_factory`

Let's create the `dionysus.rb` initializer:

``` rb
Rails.application.config.to_prepare do
  Dionysus::Consumer.declare do
    namespace :dionysus_demo do
      topic :users
    end

    Dionysus::Consumer.configure do |config|
      config.transaction_provider = ActiveRecord::Base
      config.model_factory = DionysusModelFactory
    end
  end

  Dionysus.initialize_application!(
    environment: ENV["RAILS_ENV"],
    seed_brokers: ["127.0.0.1:9092"],
    client_id: "dionysus_consumer",
    logger: Rails.logger
  )
end
```

And define the `DionysusModelFactory`:

``` rb
class DionysusModelFactory
  def self.for_model(model_name)
    model_name.classify.constantize rescue nil
  end
end
```

So, from the "User" string, we will infer the `User` class.

We can now run the `karafka server`:

```
bundle exec karafka server
```

And let's check the end result in the console:

``` rb
User.last
```

That should give us a similar result  to this:

``` rb
#<User:0x0000000110a420e8
 id: 1,
 name: "Dionysus",
 synced_id: 1,
 synced_created_at: Fri, 08 Dec 2023 14:02:36.280000000 UTC +00:00,
 synced_updated_at: Fri, 08 Dec 2023 14:02:36.280000000 UTC +00:00,
 synced_data: {"name"=>"Dionysus", "synced_id"=>8, "synced_created_at"=>"2023-12-08T14:02:36.280Z", "synced_updated_at"=>"2023-12-08T14:02:36.280Z"},
 created_at: Fri, 08 Dec 2023 14:02:42.171312000 UTC +00:00,
 updated_at: Fri, 08 Dec 2023 14:02:42.171312000 UTC +00:00>
```

It's that simple to use Dionysus and implement CDC on the domain model level!

## Conclusions

This blog post introduced dionysus-rb - a robust framework built on top of karafka, allowing CDC (Change Data Capture)/logical replication on the domain model level. This time, it covered only a tiny portion of what Dionysus is capable of, so stay tuned for the upcoming blog posts.
