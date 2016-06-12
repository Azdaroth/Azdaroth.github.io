---
layout: post
title: "Scaling Up Rails Applications With PostgreSQL Table Partitioning - Part 2"
date: 2016-06-12 22:45
comments: true
categories: [PostgreSQL, databases, Ruby, Ruby on Rails, scaling, performance, architecture]
---

<p>In the previous <a href="https://karolgalanciak.com/blog/2016/06/05/scaling-up-rails-applications-with-postgresql-table-partitioning-part-1/" target="_blank">blog post</a> we learned some basics about <strong>table partitioning</strong>: how it works and what kind of problems it solves. So far we've been discussing mostly basic concepts with raw <strong>SQL</strong> examples. But the essential question in our case would be: how to make it work inside <strong>Rails application</strong> then? Let's see what we can do about it.</p>

<!--more-->

<h2>Partitioning tables with <code>partitioned</code> gem</h2>

<p>It turns out there's no built-in support for table partitioning in ActiveRecord. Fortunately, there's a gem that makes it pretty straight-forward to apply this concept to your models: <a href="https://github.com/fiksu/partitioned" target="_blank">partitioned</a>. Not only does it have several strategies for partitioning (e.g. by foreign key or by yearly / weekly / monthly and you can easily create custom ones by subclassing base class and defining proper methods) making it easy to perform <strong>CRUD</strong> operations when dealing with multiple tables, but it also provides some methods to create and destroy infrastructure (separate schema for partitioned tables) and some helper methods for generating tables based on partitioning criteria, even with indexes and constraints! Let's get back to example from previous the blog post with orders. Firstly, add <code>partitioned</code> gem to the Gemfile. Unfortunately, there are some issues with compatibility with Rails 4.2 at the time I was experimenting with it, so it might be necessary to use some forks. The following combination should work with Rails 4.2.6:</p>

```
gem 'activerecord-redshift-adapter',  git: "git@github.com:arp/activerecord-redshift-adapter.git", branch: "rails4-compatibility"
gem 'partitioned', git: "git@github.com:dkhofer/partitioned.git", branch: "rails-4-2"
```

<p>and of course run <code>bundle install</code>. Now we can generate model:</p>

```
rails generate model Order
```

<p>Firstly, let's set up the partitioned Order model. To handle partitioning strategy for separate tables for every year based on <code>created_at</code> column, we could define the following base class:</p>

``` ruby app/models/partitioned_by_created_at_yearly.rb
class PartitionedByCreatedAtYearly < Partitioned::ByYearlyTimeField
  self.abstract_class = true

  def self.partition_time_field
    :created_at
  end

  partitioned do |partition|
    partition.index :id, unique: true
  end
end
```

<p>This class inherits from <code>Partitioned::ByYearlyTimeField</code> to handle exactly the strategy we need for orders. We set this class to be an abstract one to make it clear it's not related to any table in the database. We also need to provide <code>partition_time_field</code>, in our case it's <code>created_at</code> column. In <code>partitioned</code> block we can define some extra constraints and indexes that will be used when creating children tables. The next thing would be to make it a parent class for <code>Order</code> model:</p>

``` ruby app/models/order.rb
class Order < PartitionedByCreatedAtYearly
end
```

<h2>Creating migration for partitioned tables</h2>

<p>Let's get back to our migration. What we want to do is to create <code>orders</code> table, a schema for children partitioned tables of orders and the tables themselves for the next several years. We could do it the following way:</p>


``` sql
class CreateOrders < ActiveRecord::Migration
  def up
    create_table :orders do |t|

      t.timestamps null: false
    end

    Order.create_infrastructure
    dates = Order.partition_generate_range(Date.today, Date.today + 5.year)
    Order.create_new_partition_tables(dates)
  end

  def down
    Order.delete_infrastructure
    drop_table :orders
  end
end

```

<p>The gem also provides excellent helper method <code>partition_generate_range</code> to help with setting up new partition tables. That way we will generate tables handling orders from 2016 to 2021. Now you can simply run <code>rake db:migrate</code>.</p>

<h2>CRUD operations on partitioned tables</h2>

<p>So far we've managed to set up the database for handling table partitioning. But the essential question is: can our app handle management of these tables? Will it insert / update / delete records to and from proper tables? Let's play with some operations to find out:</p>

```
> Order.create
   (0.1ms)  BEGIN
  SQL (11.7ms)  INSERT INTO "orders_partitions"."p2016" ("created_at", "updated_at") VALUES ($1, $2) RETURNING "id"  [["created_at", "2016-06-03 17:21:36.221268"], ["updated_at", "2016-06-03 17:21:36.221268"]]
   (5.9ms)  COMMIT
> Order.create(created_at: 1.year.from_now)
   (0.1ms)  BEGIN
  SQL (0.8ms)  INSERT INTO "orders_partitions"."p2017" ("created_at", "updated_at") VALUES ($1, $2) RETURNING "id"  [["created_at", "2017-06-03 17:25:05.413114"], ["updated_at", "2016-06-03 17:25:05.414208"]]
   (121.4ms)  COMMIT
 => #<Order id: 2, created_at: "2017-06-03 17:25:05", updated_at: "2016-06-03 17:25:05">
> Order.create(created_at: 2.years.from_now)
   (0.1ms)  BEGIN
  SQL (0.3ms)  INSERT INTO "orders_partitions"."p2018" ("created_at", "updated_at") VALUES ($1, $2) RETURNING "id"  [["created_at", "2018-06-03 17:25:11.634532"], ["updated_at", "2016-06-03 17:25:11.635389"]]
   (2.1ms)  COMMIT
 => #<Order id: 3, created_at: "2018-06-03 17:25:11", updated_at: "2016-06-03 17:25:11">


> Order.all
  Order Load (0.6ms)  SELECT "orders".* FROM "orders"
 => #<ActiveRecord::Relation [#<Order id: 1, created_at: "2016-06-03 17:21:36", updated_at: "2016-06-03 17:21:36">, #<Order id: 2, created_at: "2017-06-03 17:25:05", updated_at: "2016-06-03 17:25:05">, #<Order id: 3, created_at: "2018-06-03 17:25:11", updated_at: "2016-06-03 17:25:11">]>
> Order.all.count
   (0.6ms)  SELECT COUNT(*) FROM "orders"
 => 3

> Order.find(1)
  Order Load (0.3ms)  SELECT  "orders".* FROM "orders" WHERE "orders"."id" = $1 LIMIT 1  [["id", 1]]
 => #<Order id: 1, created_at: "2016-06-03 17:21:36", updated_at: "2016-06-03 17:21:36">

> Order.from_partition(Date.new(2017, 1, 1)).find(2)
  Order Load (0.3ms)  SELECT  "orders".* FROM "orders_partitions"."p2017" "orders" WHERE "orders"."id" = $1 LIMIT 1  [["id", 2]]
 => #<Order id: 2, created_at: "2017-06-03 17:25:05", updated_at: "2016-06-03 17:25:05">

 > Order.from_partition(Date.new(2017, 1, 1)).find(2).update!(updated_at: 5.years.from_now)
  Order Load (0.3ms)  SELECT  "orders".* FROM "orders_partitions"."p2017" "orders" WHERE "orders"."id" = $1 LIMIT 1  [["id", 2]]
   (0.1ms)  BEGIN
  SQL (0.2ms)  UPDATE "orders_partitions"."p2017" SET "updated_at" = $1, "created_at" = $2 WHERE "orders_partitions"."p2017"."id" = 2  [["updated_at", "2021-06-03 17:29:07.077931"], ["created_at", "2017-06-03 17:25:05.413114"]]
   (1.7ms)  COMMIT

> Order.from_partition(Date.new(2018, 1, 1)).find(3).destroy
  Order Load (0.3ms)  SELECT  "orders".* FROM "orders_partitions"."p2018" "orders" WHERE "orders"."id" = $1 LIMIT 1  [["id", 3]]
   (0.1ms)  BEGIN
  SQL (0.3ms)  DELETE FROM "orders_partitions"."p2018" WHERE "orders_partitions"."p2018"."id" = $1  [["id", 3]]
   (1.7ms)  COMMIT

> Order.from_partition(Date.new(2017, 1, 1)).update_all(updated_at: Time.zone.now)
  SQL (1.6ms)  UPDATE "orders_partitions"."p2017" "orders" SET "updated_at" = '2016-06-03 17:30:59.926682'

> Order.from_partition(Date.new(2017, 1, 1)).destroy_all
  Order Load (0.3ms)  SELECT "orders".* FROM "orders_partitions"."p2017" "orders"
   (0.1ms)  BEGIN
  SQL (0.2ms)  DELETE FROM "orders_partitions"."p2017" WHERE "orders_partitions"."p2017"."id" = $1  [["id", 2]]
   (1.6ms)  COMMIT
```

<p>Awesome! Looks like all the CRUD operations work without any problems! We even have extremely helpful query method <code>from_partition</code> to scope queries to the specific child table.</p>

<h2>Wrapping up</h2>

<p>Table partitioning might a great solution to solve database performance issues. Even though it's not supported out-of-the-box by Rails, you can easily integrate it with your app thanks to <a href="https://github.com/fiksu/partitioned" target="_blank">partitioned</a> gem.</p>
