---
layout: post
title: "Introduction to ActiveRecord and ActiveModel Attributes API"
date: 2016-12-03 10:01
comments: true
categories: [Ruby, Rails, ActiveRecord, ActiveModel]
---

<p><strong>Rails 5.0</strong> is without a doubt a great release with plenty of useful changes and additions. The most notable change was probably <strong>ActionCable</strong> - the layer responsible for integrating your app with websockets. However, there were also other additions that could bring some <strong>substantial improvements</strong> to your Rails apps, but were a bit outshined by bigger changes. One of such features is <strong>Attributes</strong> API.</p>

<!--more-->

<h2>ActiveRecord Attributes And Defaults - The Old Way</h2>

<p>Imagine that you are in a vacation rental industry and you are adding a new model for handling reservations for rentals, let's call it <code>Reservation</code>. To keep it simple for the purpose of this example, let's assume that we need <code>start_date</code> and <code>end_date</code> date fields for handling the duration of the reservations and <code>price</code> field, which is pretty useful unless you are developing an app for a charity organization ;). Let's say we want to provide some defaults for the <code>start_date</code> and <code>end_date</code> attributes to be 1 day from now and 8 days from know accordingly when initializing a new instance of <code>Reservation</code> and the price should be converted to integer, so in fact it is going to be <code>price in cents</code>, and the expected format of the input is going to look like <code>"$1000.12"</code>. How could we handle it inside ActiveRecord models?</p>

<p>For default values one option would be to add <code>after_initialize</code> callbacks which would assign the given default defaults unless the values were already set in the initializer. For <code>price</code> we can simply override the attribute writer which is <code>Reservation#price=</code> method. We would most likely end up with something looking like this:</p>

``` rb app/models/reservation.rb
class Reservation < ApplicationRecord
  after_initialize :set_default_start_date
  after_initialize :set_default_end_date

  def price=(value)
    return super(0) if !value.to_s.include?('$')

    price_in_dollars = value.gsub(/\$/, '').to_d
    super(price_in_dollars * 100)
  end

  private

  def set_default_start_date
    self.start_date = 1.day.from_now if start_date.blank?
  end

  def set_default_end_date
    self.end_date = 8.days.from_now if end_date.blank?
  end
end
```

<p>Well, the above code works, but it can get repetitive across many models and doesn't read that well, would be much better to handle it with more of a declarative approach. But is there any built-in solution for that problem in <code>ActiveRecord</code>?</p>

<p>Then answer is yes! Time to meet your new friend in Rails world: <code>ActiveRecord Attributes API</code>.</p>

<h2>ActiveRecord Attributes And Defaults - The New Way - Attributes API</h2>

<p>Since Rails 5.0 we can use awesome Attributes API in our models. Just declare the name of the attribute with <code>attribute</code> class method, its <code>type</code> and provide optional default (either a raw value or a lambda). The great thing is that you are not limited only to attributes <strong>backed by database</strong>, you can use it for virtual attributes as well!</p>

<p>For our <code>Reservation</code> model, we could apply the following refactoring with <strong>Attributes API</strong>:</p>

``` rb app/models/reservation.rb
class Reservation < ApplicationRecord
  attribute :start_date, :date, default: -> { 1.day.from_now }
  attribute :end_date, :date, default: -> { 8.days.from_now }

  def price=(val)
    return super(0) if !value.to_s.include?('$')

    price_in_dollars = value.gsub(/\$/, '').to_d
    super(price_in_dollars * 100)
  end
end
```

<p>Looks much cleaner now! Let's see how it works:</p>

```
2.3.1 :001 > reservation = Reservation.new
 => #<Reservation id: nil, start_date: "2016-12-03", end_date: "2016-12-10", price: nil, created_at: nil, updated_at: nil>
2.3.1 :002 > reservation.start_date
 => Sat, 03 Dec 2016
2.3.1 :003 > reservation.end_date
 => Sat, 10 Dec 2016
2.3.1 :004 > reservation = Reservation.new(start_date: 3.days.from_now)
 => #<Reservation id: nil, start_date: "2016-12-05", end_date: "2016-12-10", price: nil, created_at: nil, updated_at: nil>
2.3.1 :005 > reservation.start_date
 => Mon, 05 Dec 2016
```

<p>That's exactly what we needed. What about our conversion for <code>price</code>? As we can specify the type for given attribute, we may expect that it would be possible to define our own types. Turns out it is possible and quite simple actually. Just create a class inheriting from <code>ActiveRecord::Type::Value</code> or already existing type, e.g. <code>ActiveRecord::Type::Integer</code>, define <code>cast</code> method and register the new type. In our use case let's register a new <code>price</code> type:</p>

``` rb
class PriceType < ActiveRecord::Type::Integer
  def cast(value)
    return super if value.kind_of?(Numeric)
    return super if !value.to_s.include?('$')

    price_in_dollars = BigDecimal.new(value.gsub(/\$/, ''))
    super(price_in_dollars * 100)
  end
end

ActiveRecord::Type.register(:price, Price)
```

<p>Let's use Attributes API for <code>price</code> attribute:</p>

``` ruby app/models/reservation.rb
class Reservation < ApplicationRecord
  attribute :start_date, :date, default: -> { 1.day.from_now }
  attribute :end_date, :date, default: -> { 8.days.from_now }
  attribute :price, :price
end
```

<p>And let's test if it indeed works as expected:</p>

```
2.3.1 :001 > reservation = Reservation.new
 => #<Reservation id: nil, start_date: "2016-12-03", end_date: "2016-12-10", price: nil, created_at: nil, updated_at: nil>
2.3.1 :002 > reservation.price = "$100.12"
 => "$100.12"
2.3.1 :003 > reservation.price
 => 10012
```

<p>Nice! Much cleaner and easy to reuse.</p>

<p>Attributes API comes also with some other features, you could e.g. provide <code>array</code> or range <code>option</code> and work with arrays and ranges for given type:</p>

``` rb app/models/reservation.rb
class Reservation < ApplicationRecord
  attribute :start_date, :date, default: -> { 1.day.from_now }
  attribute :end_date, :date, default: -> { 8.days.from_now }
  attribute :price, :money
  attribute :virtual_array, :integer, array: true
  attribute :virtual_range, :date, range: true
end
```

```
2.3.1 :001 > reservation = Reservation.new(virtual_array: ["1.0", "2"], virtual_range: "[2016-01-01,2017-01-1]")
 => #<Reservation id: nil, start_date: "2016-12-03", end_date: "2016-12-10", price: nil, created_at: nil, updated_at: nil>
2.3.1 :002 > reservation.virtual_array
 => [1, 2]
2.3.1 :003 > reservation.virtual_range
 => Fri, 01 Jan 2016..Sun, 01 Jan 2017
```

<p>Attributes API is already great, but it's not the end of the story. You can use your custom types for querying a database, you just need to define <code>serialize</code> method for your custom types:</p>

``` rb
class PriceType < ActiveRecord::Type::Integer
  def cast(value)
    return super if value.kind_of?(Numeric)
    return super if !value.to_s.include?('$')

    price_in_dollars = BigDecimal.new(value.gsub(/\$/, ''))
    super(price_in_dollars * 100)
  end

  def serialize(value)
    cast(value)
  end
end
```

<p>That way we could simply give prices in original format as arguments and they are going to be converted to price in cents before performing a query.</p>

```
Reservation.where(price: "$100.12")
 => Reservation Load (0.3ms)  SELECT "reservations".* FROM "reservations" WHERE "reservations"."price" = $1  [["price", 10012]]
```

<p>As expected, the price used for query was the one after serialization.</p>

<p>If you want to check the list of built-in types or learn more, check the official <a href="http://edgeapi.rubyonrails.org/classes/ActiveRecord/Attributes/ClassMethods.html" target="_blank">docs</a>.</p>

<h2>What About ActiveModel?</h2>

<p>So far I've discussed only the ActiveRecord Attributes API, but the title clearly mentions <code>ActiveModel</code> part, so what about it? There is a bad news and good news.</p>

<p>The bad news is that it is not <a href="https://github.com/rails/rails/pull/26728" target="_blank">yet</a> supported in Rails core, but most likely it is going to be the part of <strong>ActiveModel</strong> eventually.</p>

<p>The good news is that you can use it today, even though it's not a part of Rails! I've released <a href="https://github.com/Azdaroth/active_model_attributes" target="_blank">ActiveModelAttributes</a> gem which provides Attributes API for ActiveModel and it works in a very similar way to <strong>ActiveRecord Attributes</strong>.</p>

<p>Just define your <strong>ActiveModel model</strong>, include <code>ActiveModel::Model</code> and ActiveModelAttributes</code> modules and define attributes and their types using <code>attribute</code> class method:</p>

``` rb
class MyAwesomeModel
  include ActiveModel::Model
  include ActiveModelAttributes

  attribute :description, :string, default: "default description"
  attribute :start_date, :date, default: -> { Date.new(2016, 1, 1) }
end
```

<p>You can also add your custom types. Just create a class inheriting from <code>ActiveModel::Type::Value</code> or already existing type, e.g. ActiveModel::Type::Integer</code>, define <code>cast</code> method and register the new type:</p>

``` rb
class MoneyType < ActiveModel::Type::Integer
  def cast(value)
    return super if value.kind_of?(Numeric)
    return super if !value.to_s.include?('$')

    price_in_dollars = BigDecimal.new(value.gsub(/\$/, ''))
    super(price_in_dollars * 100)
  end
end

ActiveModel::Type.register(:money, MoneyType)

class MyAwesomeModel
  include ActiveModel::Model
  include ActiveModelAttributes

  attribute :price, :money
end
```

<p>And that's it! Check the <a href="https://github.com/Azdaroth/active_model_attributes" target="_blank">docs</a>, start using it today and enjoy ;)</p>

<h2>Wrapping up</h2>

<p><strong>ActiveRecord Attributes API</strong> is defintely a great feature introduced in <code>Rails 5.0</code>. Even though it is not yet supported in ActiveModel in Rails core, <a href="https://github.com/Azdaroth/active_model_attributes" target="_blank">ActiveModelAttributes</a> can be easily added to your Rails apps to provide almost the same functionality.</p>
