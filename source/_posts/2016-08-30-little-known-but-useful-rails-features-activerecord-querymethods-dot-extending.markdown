---
layout: post
title: "Little-known but useful Rails features: ActiveRecord.extending"
date: 2016-08-30 12:00
comments: true
categories: [Ruby, Rails, Ruby on Rails, Quick Tips]
---

<p>Every now and then I discover some features in <strong>Rails</strong> that are not that (arguably) commonly used, but there are some use cases when they turn out to be super useful and the <strong>best tool</strong> for the job. One of them would definitely be a nice addition to <code>ActiveRecord::QueryMethods</code> - <code>extending</code> method. Let’s see how it could be used in the <strong>Rails apps</strong>.</p>

<!--more-->

<h2>ActiveRecord::QueryMethods.extending - a great tool for managing common scopes</h2>

<p>Imagine you are developing an <strong>API</strong> in your Rails application from where you will be fetching data periodically. To avoid getting all the records every time (which may end up with tons of unnecessary requests) and returning only the changed records since the last time they were fetched, you may want to implement some scope that will be returning records updated from given date that may look like this:</p>


``` rb
scope :updated_from, ->(datetime) { where("updated_at >= ?", datetime) }
```

<p>To handle this logic in <strong>API</strong>, we could implement a generic method returning either all records or records updated from given date, depending on the presence of <code>updated_from</code> param:</p>

``` rb
def fetch_records(model_class, params)
  records = model_class.all
  if updated_from = ActiveRecord::Type::DateTime.new.type_cast_from_user(params[:updated_from])
    records = records.updated_from(updated_from)
  end
  records
end
```

<p>If that was the case only for one or two models, we could just add <code>updated_from</code> scope to them and that would be all. What if we needed it in plenty of other models as well?</p>

<p>One way to solve this problem would be defining <code>updated_from</code> <strong>scope</strong> in <code>ApplicationRecord</code> and letting the models <strong>inherit</strong> it from this base class:</p>


``` rb
class ApplicationRecord < ActiveRecord::Base
  self.abstract_class = true

  scope :updated_from, ->(datetime) { where("updated_at >= ?", datetime) }
end
```

<p>The problem with this solution is that <code>updated_from</code> scope would be available for all the models, even for the ones that won’t really need it. Another way would be extracting <code>updated_from</code> to <code>HasUpdatedFrom</code> models' <strong>concern</strong>:</p>

``` rb
module HasUpdatedFrom
  extend ActiveSupport::Concern

  included do
    scope :updated_from, ->(datetime) { where("updated_at >= ?", datetime) }
  end
end
```

<p>and including it in all the models that will be using that scope, but it’s a bit cumbersome. Fortunately, there’a a <strong>perfect solution</strong> for such problem in Rails: <a href="http://apidock.com/rails/ActiveRecord/QueryMethods/extending" target="_blank">ActiveRecord::QueryMethods.extending</a>, which lets you extend a collection with additional methods. In this case, we could simply define <code>updated_from</code> method in <code>HasUpdatedFrom</code> module: </p>


``` rb
module HasUpdatedFrom
  def updated_from(datetime)
    where("updated_at >= ?", datetime)
  end
end
```

<p>and use <code>ActiveRecord::QueryMethods.extending</code> in our <code>fetch_records</code> method just like this:</p>


``` rb
def fetch_records(model_class, params)
  records = model_class.all
  if updated_from = ActiveRecord::Type::DateTime.new.type_cast_from_user(params[:updated_from])
    records = records.extending(HasUpdatedFrom).updated_from(updated_from)
  end
  records
end
```

<p>and that’s it! You won’t need to remember about including proper concern in every model used in such API or defining any scopes in <code>ApplicationRecord</code> and inheriting them in models that won’t ever use them, just use <code>ActiveRecord::QueryMethods.extending</code> and <strong>extend your collection</strong> with extra methods only when you need them.</p>

<h2>Wrapping up</h2>

<p><code>ActiveRecord::QueryMethods.extending</code> is not that commonly used Rails feature, but it’s definitely a useful one for managing common scopes in your models.</p>
