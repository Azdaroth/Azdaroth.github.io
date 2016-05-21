---
layout: post
title: "Scaling Up Rails Applications With PostgreSQL Table Partitioning"
date: 2016-05-09 09:14
comments: true
categories: [PostgreSQL, databases, Ruby, Ruby on Rails, scaling, performance, architecture]
---

<p>You've probably heard many times so far that the database is a bottleneck of many web applications. This isn't necessarily true. Often it happens that some heavy queries can be substiantially optimized making them really efficient and fast. As the time passes by, however, the data can remarkably grow in size, especially in several years time which can indeed make the database a bottleneck - the tables are huge, the indexes are even bigger making queries much slower and you can't really optimize further any query. In many cases deleting old records that are no longer used is not an option - they still can have some value, e.g. for data analysis or statystical purposes. Fortunately, it's not a dead end. You can make your database performance great again with a new secret weapon: Table Partitioning</p>

<!--more-->
