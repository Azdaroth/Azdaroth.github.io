---
layout: post
title: "PostgreSQL Quick Tips: Working With Dates Using EXTRACT function"
date: 2018-01-30 4:30
comments: true
categories: [PostgreSQL, Database, ActiveRecord, Quick Tips]
---

Imagine that you are implementing an e-commerce platform and want to grab all orders from the **current year**. What would be the simplest way of doing it in Rails? Probably writing a query looking like this:

``` ruby
Order.where("created_at >= ? AND created_at < ?", Date.today.beginning_of_year, Date.today.beginning_of_year.next_year)
```

It gets the job done but requires unnatural filtering by a range for a use case generic enough that it should be handled just using some native functions. Is it possible?

Apparently, it is! We can use <a href="https://www.postgresql.org/docs/10/static/functions-datetime.html#FUNCTIONS-DATETIME-EXTRACT" target="_blank">`EXTRACT`</a>  and <a href="https://www.postgresql.org/docs/10/static/functions-datetime.html#FUNCTIONS-DATETIME-CURRENT" target="_blank">`now()`</a> functions - the former could be used for extracting the current **year** from a timestamp and the latter could be used for getting the current time.

With those two functions, the query could look like the following one:

``` ruby
Order.where("EXTRACT(year FROM created_at) = EXTRACT(year FROM now())")
```

Much cleaner! And the great thing is that you can also create a functional index for `EXTRACT(year FROM created_at)` to avoid sequential scanning and get much better performance.
