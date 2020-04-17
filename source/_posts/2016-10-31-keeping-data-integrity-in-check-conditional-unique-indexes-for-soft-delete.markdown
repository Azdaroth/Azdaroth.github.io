---
layout: post
title: "Keeping Data Integrity In Check: Conditional Unique Indexes For Soft Delete"
date: 2016-10-31 23:30:00
comments: true
categories: [PostgreSQL, Database, ActiveRecord, Quick Tips, Patterns]
---

<p><strong>Soft delete</strong> is a pretty common feature in most of the applications. It may increase complexity of the queries, nevertheless, not deleting anything might be a <strong>right default</strong> as the data might prove to be useful in the future: for restoring if a record was removed by mistake, to derive some conclusions based on statistics and plenty of other purposes. It may seem like it's a pretty trivial thing: just adding a column like <code>deleted_at</code> and filtering out records that have this value present. But what happens when you need to do some proper <strong>uniqueness validation</strong> on both model layer and database level? Let's take a look what kind of problem can easily be overlooked and how it can be solved with a <strong>conditional index</strong>.</p>

<!--more-->

<h2>Case study: daily prices for vacation rentals</h2>

<p>Let's imagine we are developing a <strong>vacation rental</strong> software. Most likely the pricing for each day will depend on some complex set of rules, but we may want to have some denormalized representation of base prices for each day to make things more obvious and have some possiblity of sharing this kind of data with other applications, which is quite common in this domain. We may start with adding a <code>DailyPrice</code> model having a reference to a <code>rental</code>, having <code>price</code> value and of course <code>date</code> for which the price is applicable.</p>

<h2>Ensuring uniqueness</h2>

<p>Obviously, we don't want to have any duplicated <code>daily_prices</code> for any rental, so we need to add a uniqueness validation for <code>rental_id</code> and <code>date</code> attributes:</p>

``` ruby app/models/daily_price.rb
validates :rental_id, presence: true, uniqueness: { scope: :date }
```

<p>To ensure <strong>integrity of the data</strong> and that we are protected against race conditions and potental validation bypassing, we need to add a <strong>unique index</strong> on the database level:</p>

``` ruby db/migrate/20161030120000_add_unique_index_for_daily_prices.rb
  add_index :daily_prices, [:rental_id, :date], unique: true
```

<h2>Adding soft delete functionality</h2>

<p>We have some nice setup already. But it turned out that for recalculating <code>daily_prices</code> if some rules or values influencing the price change it's much more convenient to just remove them all and recalculate from scratch than checking if the price for given date needs to be recalculated. To be on the safe side, we may decide not to hard remove these rates, but do a soft delete instead.</p>

<p>To implement this feature we could add <code>deleted_at</code> column, drop the previous index and a new one which will respect the new column. We should also update the validation in model in such case:</p>

``` ruby app/models/daily_price.rb
validates :rental_id, presence: true, uniqueness: { scope: [:date, :deleted_at] }
```

<p>And the migration part:</p>

``` ruby db/migrate/20161030120000_add_deleted_at_to_daily_prices.rb
  remove_index :daily_prices, [:rental_id, :date], unique: true
  add_column :daily_prices, :deleted_at, :datetime
  add_index :daily_prices, [:rental_id, :date, :deleted_at], unique: true
```

<p>Everything should be fine with that, right? What could possibly go wrong here?</p>

<h2>Adding index the right way</h2>

<p>Let's play with Rails console and check it out:</p>

``` ruby
> time_now = Time.current
 => Sun, 23 Oct 2016 09:44:46 UTC +00:00
> DailyPrice.create!(price: 100, date: Date.current, rental_id: 1, deleted_at: time_now)
  COMMIT
> DailyPrice.create!(price: 100, date: Date.current, rental_id: 1)
  COMMIT
> DailyPrice.create!(price: 100, date: Date.current, rental_id: 1)
  ROLLBACK
ActiveRecord::RecordInvalid: Validation failed: Rental has already been taken
```

<p>Nah, there can't be any problem, looks like we have the expected behaviour - we couldn't create a non-soft-deleted <strong>daily_price</strong> for given date and rental. But let's check one more thing:</p>

``` ruby
> price = DailyPrice.new(price: 100, date: Date.current, rental_id: 1)
> price.save(validate: false)
  COMMIT
```

<p>Whoops! Something looks very wrong here. But how is it possible? The index looks exactly like the validation in our model, yet it didn't work like that when we bypassed the validation.</p>

<p>Let's consult <strong>PostgreSQL</strong> <a href="https://www.postgresql.org/docs/9.0/static/indexes-unique.html" target="_blank">docs</a>. There is something mentioned about null values: </p>

> Null values are not considered equal

<p>That is our problem: ActiveRecord considered it as a unique value, but it doesn't work quite like that in <strong>PostgreSQL</strong>.</p>

<p>Our index should be in fact <strong>conditional</strong> and look the following way:</p>

``` ruby
add_index :nightly_rates, [:rental_id, :date], unique: true, where: "deleted_at IS NULL"
```

<p>We could optionally improve the validation in our model to make it look much closer to what we have in database and use <code>conditions</code> option:</p>

``` ruby app/models/daily_price.rb
validates :rental_id, presence: true, uniqueness: { scope: :date, conditions: -> { where(deleted_at: nil) } }
```

<p>And that's it! There's no way we could compromise <strong>data integrity</strong> now!</p>

<h2>Wrapping Up</h2>

<p>Keeping data integrity in check is essential for most of the applications to not cause some serious problems, especially when implementing soft delete. Fortunately, simply by adding PostgreSQL conditional unique indexes we can protect ourselves from such issues.</p>
