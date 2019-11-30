---
layout: post
title: "PostgreSQL In Action: Sorting With NULLIF Expression"
date: 2016-02-20 21:20
comments: true
categories: [PostgreSQL, Database, ActiveRecord, Quick Tips]
---

<p>Ordering with <strong>ActiveRecord</strong> and <strong>PostgreSQL</strong> may seem like an obvious and simple thing: in most cases you just specify one or several criteria with direction of ordering like <code>order(name: :asc)</code> and that's all, maybe in more <b>complex scenarios</b> you would need to use <code>CASE</code> statement to provide some more customized conditions. But how could we approach sorting with forcing <b>blank values</b> to be the last ones, regardless of the direction of the sort? You might be thinking now about <code>NULLS LAST</code> statement for this purpose, but that's not going to handle empty string. For this case you need something special: time to meet <code>NULLIF</code> conditional expression.</p>

<!--more-->

<h2>NULLIF to the rescue</h2>

<p>Imagine that you want to sort users by <code>fullname</code> ascending and for whatever reason it happens that the records contain both null and empty string values (besides some meaningful data of course). As previously mentioned, the following expression: <code>order("fullname ASC NULLS LAST")</code> won't be enough: it will work only for null values and the blank strings will get in a way. Fortunately, <strong>PostgreSQL</strong> offers <code>NULLIF</code> conditional statement which takes 2 arguments. If argument 1 equals argument 2 it will return <code>NULL</code>, otherwise it will return argument 1. In our case we want to return <code>NULL</code> if <code>fullname</code> is a blank string, so the final ordering statment could look like this: <code>order("NULLIF(fullname, '') ASC NULLS LAST")</code>. That's all you need for such sorting!</p>

<h2>Wrapping up</h2>

<p><code>NULLIF</code> conditional expression can help tremendously in sorting by  nullifying empty strings and always placing them in the end when combined with <code>NULLS LAST</code> statement.</p>
