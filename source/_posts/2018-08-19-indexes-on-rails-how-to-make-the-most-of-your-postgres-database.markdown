---
layout: post
title: "Indexes on Rails: How to make the most of your Postgres database"
date: 2018-08-19 20:00
comments: true
categories: [Rails, PostgreSQL, Database, Performance]
---

Optimizing **database queries** is arguably one of the fastest ways to improve the **performance** of the Rails applications. There are multiple ways how you can approach it, depending on the kind of a problem. **N+1 queries** seem to be a pretty common issue, which is, fortunately, **easy to address**. However, sometimes you have some relatively **simple-looking queries** that seem to take way longer than they should be, indicating that they might require some optimization. The best way to improve such queries is adding a **proper index**.

But what does "proper index" mean? How to figure out what kind of index is exactly needed for a given query? Here are some essential facts and tips that should cover a majority of the queries you may encounter and make your database no longer a bottleneck.

<!--more-->

## Why index at all?

Simple - to have faster queries. But why are indexes faster? The alternative to index is a sequential scanning of the entire table. That might not sound like a bad idea, but imagine you are performing a search over a huge table. What would be the fastest way to retrieve all records you are looking for - by scanning the entire table, or maybe having a way to store a subset of the records, based on some specific criteria, and then retrieve them from that place? Obviously, it's the second option. And that's roughly how indexes work.

As trivial as it sounds, there is a valuable lesson to learn from it: to achieve a good performance, the index must be selective enough. And the more specific you will be about those criteria, the better.

## Index Types

Although Postgres by defaults creates `B-Tree` index when using `CREATE INDEX` command, there are a couple of more indexes that will be certainly useful in many use cases. Let's check them all out:

### B-Tree Index

`B-Tree` is a self-balancing tree data structure which keeps data ordered and easy to search. This index is appropriate for equality and range queries (using operators like `>=`,  `<` etc.) and will work great with text, timestamp and number fields.

B-Tree indexes are a reasonable default for most of the queries, but not for all of them. The limitation comes from the underlying structure. Discussing the details of the B-Tree data structure itself is beyond the scope of this article; nevertheless, it's worth keeping in mind that it's a similar data structure to a binary search tree, which has meaningful consequences on what can be indexed with it and how. We will get back to a couple of examples later.

### Hash Index

Before Postgres 10, the usage of hash indexes was discouraged since they used to be not WAL-logged. Fortunately, it's changed in Postgres 10, and we can use them safely without worrying about rebuilding the index if something goes wrong with our database that would cause a crash. The use cases where hash indexes are useful are very limited, as they work only for equality, but they are a bit more efficient for this kind of queries comparing to b-tree indexes. If you store tokens for example and perform lookups by the token value, hash indexes would be a good way to optimize such queries.

### BRIN Index (Block Range Index)

BRIN indexes were introduced in Postgres 9.5 which make them a pretty new addition. They tend to work very well for the large sets of ordered data, e.g., statistical data collected with timestamps which are later filtered by the time range. They will perform better than b-tree indexes in such case, although the difference won't be drastic. However, the different of the size of the index will be huge - BRIN index can be smaller by literally few orders of magnitude comparing to b-tree index.

### GIN Index (Generalized Inverted Index)

GIN Indexes are the perfect choice for "composite values" where you perform a query which looks for an element within such "composite". That is the index you will most likely want to use for `jsonb`, `array` or `hstore` data structures. They are also an excellent choice for full-text search.

### GiST Index (Generalized Inverted Seach Tree Index)

GiST Indexes will be a good choice when the records overlap values under the same column. They are commonly used for geometry types and full-text search as well. The difference between GIN and GiST Index when it comes to full-text search is that GiST Index will be less taxing on writes comparing to GIN (as it is faster to build). But since it's a lossy index, there might be some extra overhead involved for reads, which makes GIN index a better choice when you mostly care about reads optimization.

## Optimizing Queries

Here are some tips that should help you with the majority of the queries:

### Start with EXPLAIN

With enough experience and knowledge of your app, you will develop an intuition about indexes and where they might be useful, long before having performance problems with queries. Until that happens, it's essential to understand how Postgres is going to execute these queries. The best tool for that purpose is using `EXPLAIN` command, which will show the execution plan generated by the query planner. `ActiveRecord` provides a convenient method - `explain` - that you can use on collections to get the query plan:

```
> Order.where(customer_id: 1).explain
  Order Load (13.8ms)  SELECT "orders".* FROM "orders" WHERE "orders"."customer_id" = $1  [["customer_id", 1]]
=> EXPLAIN for: SELECT "orders".* FROM "orders" WHERE "orders"."customer_id" = $1 [["customer_id", 1]]
                                           QUERY PLAN
-------------------------------------------------------------------------------------------------
 Index Scan using index_orders_on_customer_id on orders  (cost=0.15..19.62 rows=50 width=1417)
   Index Cond: (customer_id = 1)
(2 rows)
```

Unfortunately, `EXPLAIN ANALYZE`, which provides even more insight, as it performs a real query, is not supported out of the box by ActiveRecord. However, it can be added using an extra gem. You can check out [this blog post](https://pawelurbanek.com/slow-rails-queries) to learn more about it.

### How to tell a good query plan from a bad one?

This is not that simple as it sounds, as the sequential scan can be sometimes more efficient than using an index, especially if not kept in memory, but stored entirely on disk, and even worse, an HDD one. Usually, a preferable query plan is the one that looks simpler and utilizes the least possible number of indexes, which means that it's better to use one index instead of two of them, like in the following example:

```
> Product.where(warehouse_id: 1).where(category_id: 1).explain
  Product Load (0.5ms)  SELECT "products".* FROM "products" WHERE "products"."warehouse_id" = $1 AND "products"."category_id" = $2  [["warehouse_id", 1], ["category_id", 1]]
=> EXPLAIN for: SELECT "products".* FROM "products" WHERE "products"."warehouse_id" = $1 AND "products"."category_id" = $2 [["warehouse_id", 1], ["category_id", 1]]
                                                       QUERY PLAN
------------------------------------------------------------------------------------------------------------------------
 Bitmap Heap Scan on products  (cost=9.08..13.10 rows=1 width=1417)
   Recheck Cond: ((warehouse_id = 1) AND (category_id = 1))
   ->  BitmapAnd  (cost=9.08..9.08 rows=1 width=0)
         ->  Bitmap Index Scan on index_products_on_warehouse_id_and_name_and_something_else  (cost=0.00..4.31 rows=5 width=0)
               Index Cond: (warehouse_id = 1)
         ->  Bitmap Index Scan on index_products_on_category_id  (cost=0.00..4.52 rows=50 width=0)
               Index Cond: (category_id = 1)
(7 rows)
```

It doesn't necessarily mean that this query plan is a bad one - it could be totally the case that such query is fast enough. However, if read speed is more important for us than the index size and extra overhead on writes which will make them slower, the best way to deal with such query would be adding a compound index on both `warehouse_id` and `category_id`.

One statement that is especially worth keeping an eye on (besides `Seq Scan` which stands for a sequential scan) is `Filter` statement which indicates that the records required extra filtering and the index was not enough. Here is one example:

```
 Index Scan using index_products_on_category_id on products
   Index Cond: (category = 1)
   Filter: (created_at = '2018-08-11'::date)
```

Ideally, `created_at` part would appear in `Index Cond` and be fully covered by the index. Usually, adding a compound index on multiple columns solves the issue which in this example would mean having an index on both `category_id` and `created_at`, not only on `category_id`.

### Sequence of the columns in B-Tree index does matter

The sequence of the columns in a multi-column index is critical. Imagine that you created a following index: `create_index :tag_items, [:taggable_type, :taggable_id]` and want to perform a couple of queries. For sure this index is going to be efficient for searching by both `taggable_type` and `taggable_id`. It will also work great for search by `taggable_type`. It won't, however, be efficient when performing a search just by `taggable_id`. The reason why it is like that is quite simple though - try to imagine how the data would be stored in a hypothetical B-Tree. First, the nodes will be organized based on the leftmost column and then, by another one. Traversing such tree when you do a search based on `taggable_type` or both `taggable_type` and `taggable_id` will be simple. However, you can't do the same with just `taggable_id`. Postgres might use this index anyway as it might turn out to be still more efficient than a sequential scan, but this is going to be suboptimal. If it happens that you need to perform queries by `taggable_id` only, it would be a good idea to add a separate index on that field.

### Unique Indexes

The biggest need behind unique indexes is ensuring data integrity (since most uniqueness validations, including ActiveRecord one, don't enforce anything and are more useful for having a nice error message and not raising an exception than for data integrity). However, a nice side effect of a unique index is also a better performance comparing to a non-unique one.

### Partial Indexes

Imagine that you have some Articles in your application and you want to add `published_at` datetime field indicating whether and when the article was published, and then, filter published articles by a given author. We can most likely expect a need for an index on `author_id` column in such case. What about our second condition? We could for sure add a compound index on both `author_id` and `published_at`. However, there is a better choice. We could add a partial index for `author_id` which covers only published articles, i.e., covers `WHERE published_at IS NOT NULL`!

Fortunately, this is supported by Rails (although writing a SQL command wouldn't be that difficult), we just need to use `where` option for that:

``` rb
add_index :articles, :author_id, where: "published_at IS NOT NULL"
```

### Expression Indexes

Imagine that you need to search users by their first name which comes from some input provided by a user. However, to avoid issues with figuring out whether the name provided by a user starts with a capital letter or not or how the names were stored in the database in the first place, you perform a query like this:

``` rb
User.where("lower(first_name) = ?", name.downcase)
```

This query will obviously work, however, if you have a lot of users, a query plan will indicate that it is suboptimal and instead of seeing something like `Index Scan using index_users_on_first_name on users`, you will see `Seq Scan on users`.

There is no need to worry though. Postgres allows creating expression indexes where you can apply some functions, which in our case is `lower`. A proper index for this scenario would need to be created that way:

``` rb
add_index :users, "lower(first_name)", name: "index_users_on_lower_first_name"
```

### Optimizing LIKE queries

Optimizing queries with `LIKE` clause is simple; you just need to remember about two things:

1. Forget about B-Tree Index for this case.
2. Take advantage of trigram matching provided by [pg_trgm](https://www.postgresql.org/docs/10/static/pgtrgm.html) extension.

To avoid sequential scans and utilize index that will drastically improve the performance of this kind of queries, enable the extension and create a GIN or GiST index:

```
execute "CREATE EXTENSION pg_trgm;"
execute "CREATE INDEX CONCURRENTLY index_products_on_description_trigram ON clients USING gin(description gin_trgm_ops);"
```

Thanks to this index, this is a query plan you might expect when filtering `Products` by `descriptions` containing some text, with wildcards on both the beginning and the end:

```
EXPLAIN for: SELECT "products".* FROM "products" WHERE (products.description ILIKE '%some text with wildacards%')
                                                QUERY PLAN
-----------------------------------------------------------------------------------------------------------
 Bitmap Heap Scan on products
   Recheck Cond: (description ~~* '%some text with wildacards%'::text)
   ->  Bitmap Index Scan on index_products_on_description_trigram
         Index Cond: (description ~~* '%some text with wildacards%'::text)
```


### Ordering

B-tree indexes are sorted in an ascending order which we can use to our advantage to avoid performing sorting in memory. However, we also need to keep in mind the limitation of the data structure itself. A rule of thumb for efficient ordering would be: order by the same columns you perform filtering by. It is going to be the case by default when you don't explicitly add any `ORDER` clause since the indexes are ordered. But if it happens that you need to apply different ordering criteria, you can take advantage of `order` option and explicitly specify the order:

```
add_index :products, :created_at, order: { created_at: :desc }
```

### Adding indexes concurrently

The way how the indexes are added doesn't impact the performance once they are created; however, it's good to keep in mind that just simple `CREATE INDEX` will block concurrent writes (inserts, updates, and deletes) until it's finished. It can lead to some issues, including deadlocks, especially when the index is getting created for a huge table under massive write operations.

To prevent such a problem, it's worth creating indexes [concurrently](https://www.postgresql.org/docs/10/static/sql-createindex.html#SQL-CREATEINDEX-CONCURRENTLY) instead. You can do that in Rails using `algorithm: :concurrently` option and by making sure that the index creation will run outside of a transaction by calling `disable_ddl_transaction!`.

``` rb
class AddIndexToAsksActive < ActiveRecord::Migration[5.0]
  disable_ddl_transaction!

  def change
    add_index :users, :active, algorithm: :concurrently
  end
end
```

There is one caveat here though. If you attempt to create a unique index concurrently, there is a possibility that something will go wrong, e.g., when a non-unique record is created during the index creation. Since the command is run outside the transaction, it won't be rolled back, and you will end up with an invalid index. Nevertheless, that is not a big problem - should it ever happen, just drop the invalid index and try creating it concurrently one more time.

## Wrapping up

Optimizing **PostgreSQL queries** might not look a trivial task, but if you keep these rules in mind, you will have much easier time with your database, and you will enjoy fast queries for a long time.
