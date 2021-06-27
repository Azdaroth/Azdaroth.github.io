---
layout: post
title: "Multiple databases in a single query in your Rails apps - Postgres Foreign Data Wrappers to the rescue"
date: 2021-06-27 7:00
comments: true
categories: [Ruby on Rails, Ruby, Postgres, databases]
---

Imagine that you are building a separate application for your e-commerce system dedicated to business intelligence. In other words, you want to calculate some stats for the orders. So you are going to create some new model, like OrderStat(s), and have a **separate Postgres database** for a new app. Sounds trivial so far.

However, how are you going to get the data from the actual Orders? One way of doing that would be to do some data liberation and stream all Orders (or events related to orders) into [Kafka](https://karolgalanciak.com/blog/2020/12/20/kafka-for-rubyists-mini-course/) and let the consumers get the **data from Kafka**.  If that's ever your plan to have **Kafka in your ecosystem**, then this is a way better solution than what will be discussed in this article. On the other hand, we went from **querying a single table from a different database**, which sounds like a straightforward thing, to an event-driven ecosystem backed by Kafka, which is a complex thing, especially if you don't have much experience with it. This time, for this particular problem, we are going to explore some solution that maybe is not pretty and indicates an architectural smell, but also does the job efficiently - performing queries between **two separate PostgreSQL databases** (including joins!) using **Foreign Data Wrappers**.

<!--more-->

## Foreign Data Wrappers

Foreign Data Wrappers is a fantastic feature of PostgreSQL that allows you to query against external data sources. The external data source is not just a different Postgres database - it could be anything as long as the appropriate extension is available for that particular data source. You can make it work with MySQL, Redis, MongoDB, and even Kafka, so the flexibility is quite impressive. Nevertheless, let's focus on Postgres-to-Postgres integration, which is available out of the box.

The idea behind FDWs is quite simple - after enabling the extension, we need to define an external server, define the mapping of how to access that server, and create foreign tables, which are adapter/proxy-like tables to an external data source. In the end, we are going to run queries against just yet another table - it will just be a table with some extras compared to a standard one.

Now that we know the basics let's see how we could use it in a Rails application.

## Using in Rails

Imagine that we have some OrderStat model in our current app, and we need some data from the Order model represented by the "orders" table from a different database.

We will need four migrations to make it work.

First, let's create the extension:

``` rb
class CreateFdwExtension < ActiveRecord::Migration[6.1]
  def up
    execute "CREATE EXTENSION postgres_fdw;"
  end

  def down
    execute "DROP EXTENSION postgres_fdw;"
  end
end
```


Next, let's create a server:

``` rb
class CreateFdwServer < ActiveRecord::Migration[6.1]
  def up
    execute "CREATE SERVER server_name
      FOREIGN DATA WRAPPER postgres_fdw
      OPTIONS (host 'localhost', dbname 'name_of_external_db');
    "
  end

  def down
    execute "DROP SERVER server_name"
  end
end
```

In the next step, we will need to provide the user and password to access that DB:

``` rb
class CreateFdwMapping < ActiveRecord::Migration[6.1]
  def up
    execute "CREATE USER MAPPING FOR CURRENT_USER SERVER name_of_external_db OPTIONS (user '', password '');"
  end

  def down
    execute "DROP USER MAPPING FOR CURRENT_USER SERVER name_of_external_db"
  end
end
```

In the last step, we will be creating a foreign table. One way of doing this is via `CREATE FOREIGN TABLE orders` where you provide the exact schema for this table, but this is not efficient for a large number of columns. It's way more convenient to use `IMPORT FOREIGN SCHEMA` where you can provide the schema name (unless you went with some custom solution, just use "public" here), name of the table(s), and name of the server, and that's it! You don't need to bother with the exact columns and their types and constraints.

``` rb
class CreateForeignAccountsTable < ActiveRecord::Migration[6.1]
  def up
    execute "IMPORT FOREIGN SCHEMA public LIMIT TO (orders) FROM SERVER server_name INTO public;"

    # Alternatively:
    # execute "CREATE FOREIGN TABLE orders (
    #     id integer NOT NULL
    #   )
    #     SERVER server_name
    #     OPTIONS (schema_name 'public', table_name 'orders');
    # "
  end

  def down
    execute "DROP FOREIGN TABLE orders"
  end
end
```

And that's it!

You could test it using joins:

``` rb
# assuming that OrderStat and Order models exist in the app and OrderStat belongs to Order
OrderStat.joins(:order)
```


And that's how you join tables from two different databases :). However, to make it fully work in your Rails app, so that you can, for example, execute simple queries like `OrderStat.joins(:order).first.order`, you might need one adjustment in the `Order` model with explicitly specifying the primary key, as otherwise, you might get the following error:

```
ActiveRecord::UnknownPrimaryKey (Unknown primary key for table orders in model Order.)
```
So here it is:

``` rb
class Order < ApplicationRecord
  self.primary_key = "id"
end
```

And that's it!

### Refreshing schema

It's quite likely that the schema of the "orders" table will change. In such a case, if you need to refresh the schema, just recreate foreign tables.

## Wrapping Up

Performing **queries between two different databases**, especially performing joins, is probably not something that you do every day and, to some extent, might indicate an architectural smell in your ecosystem. Still, it's worth knowing such an option is available as it might be a very quick win under certain circumstances. Fortunately, it's a pretty straightforward thing to do using **Postgres Foreign Data Wrappers**.
