---
layout: post
title: "Rails: Useful Patterns"
date: 2014-09-17 19:55
comments: true
categories: [OOP, Rails, Design Patterns, Refactoring]
---

<p>There've been a lot of discussions for several months about "The Rails Way" and problems associated with it - huge models with several thousands lines of code and no distinguishable responsibilities (User class which does everything related to users doesn't tell much what the app does), unmaintainable callback hell and no domain objects at all. Fortunately, service objects (or usecases) and other forms of extracting logic from models have become quite mainstream recently. However, it's not always clear how to use them all together without creating huge classes with tens of private methods and too many responsibilities. Here are some strategies you can use to solve these problems.</p>

<!--more--> 

<h2>Pass form objects as data aggregates to service objects</h2>

<p>Imagine situation where your usecase involves more than one model, some virtual attributes are needed etc., basically the usecase where form object is necessary (unless you want to have a serious mess in models). Furthermore, you need to implement pretty complex features - besides proper mapping of attributes to models in form objects you want to send some notifications, log an activity and other stuff. How to tackle such a problem? Often I see a code where all custom logic, apart from simple saving data, is put in form objects. That's not really a way to go. Why start from separating responsibilities and end up with form object which does everything? You can easily handle it by passing form objects with populated data to service objects. Take a look at the controller action below:</p>

``` ruby
class UsersController < ApplicationController

  def create
    user = User.new
    form = User::RegistrationForm.new(user)
    registration = User::Registration.new(logger: MyFancyCustomLogger, mailer: User::RegistraionMailer)

    if form.validate(params) && registration.register(form)
      # success path
    else
      # failure path
    end
  end

end
```

<p>The <code>UsersController</code> is responsible here for control flow, form aggregates and validates data and <code>User::Registration</code> does some domain business logic and assumes it operates on valid data. Looks and feels great, it's easy to test and the responsibilities are clear. I also inject some dependencies in the constructor of <code>User::Registration</code> to make it even more testable and extensible.</p> 

<p>The only problem with such an approach is lack of compatibility or difficulties with customization with some gems (like <code>inherited_resources</code>). But gems shouldn't force you to write code in a particular way and it would be probably better to give up on them and enjoy a clean code.</p>

<h2>Create flexible service objects with listeners</h2>

<p>Let's consider previous usecase: registration. Imagine situation where you need three types of user registration: “normal” one like when you enter the page and want to create an account,  registration by admin and registering new users by non-admin within some kind of groups. The core of registration process remains the same in all cases. However, there will be slight differences between the usesaces, eg. there won't be any notification sent to admin when user is being registered by admin. One way would be to create service object for each usecase and encapsulate entire logic within them. But it may lead to code that is not DRY and these classes may be unnecessary. If the core of the registration process doesn't change, we can create interface flexible enough to handle all cases by passing listeners that are being notified after registration process. Our service object could look like this:</p>

``` ruby

class User::Registration
    
  attr_reader :logger, :listeners
  private :logger, :listeners

  def initialize(*listeners, **options)
    @listeners = listeners
    @logger = options.fetch(:logger) { MyFancyCustomLogger }
  end

  def register(aggregate)
    # do some stuff common in all cases
    notify_listeners(aggregate)
  end

  private

    def notify_listeners(aggregate)
      listeners.each { |listener| listener.notify(aggregate) }
    end

```

<p>We can pass any number of listeners to the constructor and inject dependencies if required. All listeners have to implement the same interface: <code>notify</code> method which takes one argument. The controller action for registering new user may look like this:</p>



``` ruby
class UsersController < ApplicationController

  def create
    user = User.new
    form = User::RegistrationForm.new(user)
    registration = User::Registration.new(
      AdminNewUserListener.new,
      SomeExternalServiceNewUserListener.new
      logger: MyFancyCustomLogger
    )

    if form.validate(params) && registration.register(form)
      # success path
    else
      # failure path
    end
  end

end
```

<p>We've encapsulated additional logic in separate classes in form of listeners and created quite flexible interface - we need another action in registration process but only in one type of registration, not all of them? Just pass another listener into the constructor in controller.</p>


<h2>Extract context classes</h2>

<p>It often happens that you need an entity to play different roles, eg. the user can be a seller or a buyer, depending on the usecase. Instead of adding plenty of methods to the <code>User</code> class that are related only to the particular role, you can create context classes. Both sellers and buyers will probably share the same methods. One way to solve this problem could be inheritance but it would mean single table inheritance in this case (ActiveRecord model) and that's not what we need. However, we can use <code><a href="http://ruby-doc.org/stdlib-2.1.2/libdoc/delegate/rdoc/SimpleDelegator.html" target="_blank">SimpleDelegator</a></code> which would delegate all the method calls to the decorated object (user) if the decorator doesn't implement these methods:</p>

``` ruby
class Seller < SimpleDelegator

  def rating
    # instead of rating_as_seller method in User class
    positive_opinions_from_bought_items.to_f / opinions_from_bought_items.to_f
  end 


end

```

``` ruby
class Buyer < SimpleDelegator


  def rating
    # instead of rating_as_buyer method in User class
    positive_opinions_from_seld_items.to_f / opinions_from_sold_items.to_f
  end


end

```
<p>We can also implement some convenience methods in <code>User</code> class to get user in approperiate context:</p>

``` ruby
class User < ActiveRecord::Base

  def to_buyer
    Buyer.new(self)
  end

  def to_seller
    Seller.new(self)
  end

end
```

<h2>Trade long if/case statements for declarative dispatch</h2>

<p>Rather a structural implementation detail but still quite interesting. Imagine situation when you have to return proper status based on some conditions. You can of course use <code>case</code> statement but the problem with this approach is that the code is not really pretty, especially when you have multiple conditions for each status. For complex logic it might be better to handle such usecases with more declarative approach:</p>

``` ruby
class User::SellerStatus

  attr_reader :user
  private :user

  def initialize(user)
    @user = user
  end

  def call
    statuses_conditions.detect do |aggregate|
      conditions = aggregate.last
      conditions.all? { |condition| send(condition) }
    end.first
  end

  private

    def statuses_conditions
      {
        super_seller: [
          :has_more_than_1000_opinions?,
          :has_more_than_95_percent_positive_opinions_as_seller?
        ],
        blacklisted_seller: [ 
          :has_at_least_10_opinion_as_seller?,
          :has_more_than_50_precent_or_equal_negative_opinions_as_seller?
        ],
        new: [
          :has_less_than_10_opinion_as_seller?,
        ],
        no_status: []
      }
    end

    def has_more_than_1000_opinions?
      # some code
    end

    def has_more_than_95_percent_positive_opinions_as_seller?
      # some code
    end

    def has_at_least_10_opinion_as_seller?
      # some code
    end

    def has_more_than_50_precent_or_equal_negative_opinions_as_seller?
      # some code
    end

    def has_less_than_10_opinion_as_seller?
      # some code
    end

end

```
<p>The <code>detect</code> enumerator (aliased also as <code>find</code>) will return the first element for which the block returns true. In this case all the conditions must be satisfied to return true.</p>

<p>Instead of using bunch of private methods, you can move these methods to policy objects and change the receiver of the message to be the policy, not <code>self</code>:</p>

``` ruby

def call
  policy = User::SellerPolicy.new(user)
  statuses_conditions.detect do |aggregate|
    conditions = aggregate.last
    conditions.all? { |condition| policy.public_send(condition) }
  end.first
end

```

<p>I like the clarity of this approach - you can immediately say what are the necessary conditions for each status without multiple <code>&&</code> operators in case statement which would make it harder to read.</p>

<h2>Wrapping up</h2>

<p>I've shown some simple and common techniques I use in almost everyday coding. I hope that you will find them useful and will keep the code clean.</p>