---
layout: post
title: "Scaling Up Rails Applications With PostgreSQL Table Partitioning - Part 1"
date: 2016-06-05 22:00
comments: true
categories: [PostgreSQL, databases, Ruby, Ruby on Rails, scaling, performance, architecture]
---

<p>You've probably heard many times that the database is the bottleneck of many web applications. This isn't necessarily true. Often it happens that some heavy queries can be substiantially optimized, making them really efficient and fast. As the time passes by, however, the data can remarkably grow in size, especially in several years time which can indeed make the database a bottleneck - the tables are huge and don't fit into memory any longer, the indexes are even bigger making queries much slower and you can't really optimize further any query. In many cases deleting old records that are no longer used is not an option - they still can have some value, e.g. for data analysis or statystical purposes. Fortunately, it's not a dead end. You can make your database performance great again with a new secret weapon: table partitioning.</p>

<!--more-->

<h2>Table partitioning and inheritance 101</h2>

<p>To put it in simple words, table partitioning is about splitting one big table into several smaller units. In <strong>PostgreSQL</strong> it can be done by creating <strong>master table</strong> serving as a template for other <strong>children tables</strong> that will inherit from it. <strong>Master table</strong> contains no data and you shouldn't add any indexes and unique constraints to it. However, if you need some <code>CHECK CONSTRAINTS</code> in all <strong>children tables</strong>, it is a good idea to add them to <strong>master table</strong> as they will be inherited. Due to inheritance mechanism, there is no point in adding any columns to <strong>children tables</strong> either. Creating tables inheriting from other tables is pretty straight-forward - you just need to use <code>INHERITS</code> clause:</p>

``` sql
CREATE TABLE orders(
  id serial NOT NULL,
  client_id integer NOT NULL,
  created_at timestamp without time zone NOT NULL,
  updated_at timestamp without time zone NOT NULL
);

CREATE TABLE other_orders() INHERITS (orders);
```

<p>and that's it - all columns and extra constraints will be defined on <code>other_orders</code> thanks to inheritance from <code>orders</code> table.</p>

<h2>Defining constraints for partitioning criteria</h2>

<p>As we are going to split one big table into the smaller ones, we need to have some criterium that would be used to decide which table should we put the data in. We can do it either by range (e.g. <code>created_at</code> between 01.01.2016 and 31.12.2016) or by value (<code>client_id</code> equal to 100). To ensure we have only the valid data which always satisfy out partitioning criterium, we should add proper <code>CHECK CONSTRAINTS</code> as guard statements. To make sure the orders in particular table were e.g. created at 2016, we could add the following constraint</p>

``` sql
CHECK (created_at >= DATE '2016-01-01' AND day <= created_at '2016-12-31' )
```

If we were to create tables for orders for the upcoming few years (assuming that we want to cover entire year in each of them), we could do the following:

```sql
CREATE TABLE orders_2016 (
    CHECK (created_at >= DATE '2016-01-01' AND created_at <= DATE '2016-12-31')
) INHERITS (orders);
CREATE TABLE orders_2017 (
    CHECK (created_at >= DATE '2017-01-01' AND created_at <= DATE '2017-12-31')
) INHERITS (orders);
CREATE TABLE orders_2018 (
    CHECK (created_at >= DATE '2018-01-01' AND created_at <= DATE '2018-12-31')
) INHERITS (orders);
```

<p>Beware of potential gotcha when defining <code>CHECK CONSTRAINTS</code>. Take a look at the following example:</p>

``` sql
CHECK (client_id >= 1 AND created_at <= 1000);
CHECK (client_id >= 1000 AND created_at <= 2000);
```

<p>In this case orders with <code>client_id</code> equal to 1000 could be inserted to any of these tables. Make sure the constraints are not inclusive on the same value when using ranges to avoid such problems.</p>

<h2>Performance optimization</h2>

<p>To provide decent performance it is also important to make <code>constraint_exclusion </code> in <code>postgresql.conf</code> enabled. You can set it either to <code>on</code> or <code>partition</code>:</p>


```
constraint_exclusion = on # on, off, or partition
```

or

```
constraint_exclusion = partition  # on, off, or partition
```

<p>That way we can avoid scanning all children tables when the <code>CHECK CONSTRAINTS</code> exclude them based on query conditions. Compare the query plans between queries with <code>constraint_exclusion</code> disabled and enabled:</p>

``` sql
# SET constraint_exclusion = off;
SET

# EXPLAIN (ANALYZE ON, BUFFERS ON) SELECT * FROM orders WHERE created_at >= DATE '2018-01-01' AND created_at <= DATE '2018-12-31';
                                                 QUERY PLAN
-------------------------------------------------------------------------------------------------------------
 Append  (cost=0.00..97.95 rows=25 width=24) (actual time=0.001..0.001 rows=0 loops=1)
   ->  Seq Scan on orders  (cost=0.00..0.00 rows=1 width=24) (actual time=0.001..0.001 rows=0 loops=1)
         Filter: ((created_at >= '2018-01-01'::date) AND (created_at <= '2018-12-31'::date))
   ->  Seq Scan on orders_2016  (cost=0.00..32.65 rows=8 width=24) (actual time=0.000..0.000 rows=0 loops=1)
         Filter: ((created_at >= '2018-01-01'::date) AND (created_at <= '2018-12-31'::date))
   ->  Seq Scan on orders_2017  (cost=0.00..32.65 rows=8 width=24) (actual time=0.000..0.000 rows=0 loops=1)
         Filter: ((created_at >= '2018-01-01'::date) AND (created_at <= '2018-12-31'::date))
   ->  Seq Scan on orders_2018  (cost=0.00..32.65 rows=8 width=24) (actual time=0.000..0.000 rows=0 loops=1)
         Filter: ((created_at >= '2018-01-01'::date) AND (created_at <= '2018-12-31'::date))
```

``` sql
# SET constraint_exclusion = partition;
SET

# EXPLAIN SELECT * FROM orders WHERE created_at >= DATE '2018-01-01' AND created_at <= DATE '2018-12-31';
                                         QUERY PLAN
---------------------------------------------------------------------------------------------
 Append  (cost=0.00..32.65 rows=9 width=24)
   ->  Seq Scan on orders  (cost=0.00..0.00 rows=1 width=24)
         Filter: ((created_at >= '2018-01-01'::date) AND (created_at <= '2018-12-31'::date))
   ->  Seq Scan on orders_2018  (cost=0.00..32.65 rows=8 width=24)
         Filter: ((created_at >= '2018-01-01'::date) AND (created_at <= '2018-12-31'::date))
(5 rows)
```

<p>We wanted to select only the orders created on 2018, so there is no need to scan other children tables that don't contain such data.</p>

<p>The difference between <code>on</code> and <code>partition</code> setting is that the former checks constraints for all tables and the latter only for children tables inheriting from parent table (and also when using <code>UNION ALL</code> subqueries).</p>

<h2>Create new records easily with triggers</h2>

<p>Having multiple tables is certainly difficult to manage when creating new records. Always remembering that they should be inserted to a specific table can be cumbersome. Fortunately, there's an excellent solution for this problem: PostgreSQL triggers! If you are not familiar with them, you can read my previous <a href="https://karolgalanciak.com/blog/2016/05/06/when-validation-is-not-enough-postgresql-triggers-for-data-integrity/" target="_blank">blog post</a> about database triggers.</p>

<p>We can automate the insertion process by checking the value of <code>created_at</code> and decide which table it should be put in. Here's an example how we could approach it:</p>


``` sql
CREATE OR REPLACE FUNCTION orders_create_function()
RETURNS TRIGGER AS $$
BEGIN
    IF (NEW.created_at >= DATE '2016-01-01' AND
         NEW.created_at <= DATE '2016-12-31') THEN
        INSERT INTO orders_2016 VALUES (NEW.*);
    ELSIF ( NEW.created_at >= DATE '2017-01-01' AND
            NEW.created_at <= DATE '2017-21-31' ) THEN
        INSERT INTO orders_2017 VALUES (NEW.*);
    ELSIF (NEW.created_at >= created_at '2018-01-01' AND
            NEW.created_at <= created_at '2018-12-31') THEN
        INSERT INTO orders_2018 VALUES (NEW.*);
    ELSE
        RAISE EXCEPTION 'Date out of range, probably child table is missing';
    END IF;
    RETURN NULL;
END;
$$
LANGUAGE plpgsql;

CREATE TRIGGER orders_create_trigger
BEFORE INSERT ON orders
FOR EACH ROW EXECUTE PROCEDURE orders_create_function();
```

<p>There's a potential gotcha though: as we as we are dealing with multiple tables, the <code>id</code> of the orders might not necessarily be unique across all of them. When creating new records we can ensure that the next id will be based on "global" sequence for partitioned tables, but it still gives a possibility to have duplicated ids in some tables, e.g. by accidental update of the id. Probably the best way to make sure there are no duplicates in all partitioned tables would be using <strong>uuid</strong> which most likely will be unique.</p>

<h2>Wrapping up</h2>

<p>Table partitioning might be a great solution to improve performance of your application when the amount of data in tables is huge (especially when they don't fit into memory any longer). In the first part, we learned some basics from raw SQL perspective about table partitioning. In the next one we will be applying this concept to real-world Rails application.</p>
