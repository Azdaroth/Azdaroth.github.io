---
layout: post
title: "Decoding Rails Magic: How Does Calling Class Methods On Mailers Work"
date: 2016-07-31 21:15
comments: true
categories: [Ruby, Ruby on Rails, Design Patterns, Architecture]
---

<p>Have you ever wondered how it is possible that calling <strong>class methods</strong> on <strong>mailers</strong> work in Rails, even though you only define some instance methods in those classes? It seems like it’s quite common question, especially when you see the mailers in action for the first time. Apparently, there is some Ruby "magic" involved here, so let’s try to <b>decode</b> it and check what happens under the hood.</p>

<!--more-->

<h2>Anatomy of ActionMailer mailers</h2>

<p>Let’s start with adding a very simple <code>WelcomeMailer</code> as an example:</p>


``` ruby app/mailers/welcome_mailer.rb
class WelcomeMailer < ApplicationMailer
  def welcome(user)
    @user = user
    mail to: user.email
  end
end
```

<p>If we wanted to send <code>welcome</code> email to some <code>user</code>, we would write the following code:</p>


``` ruby
WelcomeMailer.welcome(user).deliver_now
```

<p>It’s quite interesting that it works just like that, even though we have never defined any class method in <code>WelcomeMailer</code>.  Most likely it’s handled with <code>method_missing</code> magic in <code>ActionMailer::Base</code>. To verify that, let’s dive into Rails source code. In <a href="https://github.com/rails/rails/blob/v5.0.0/actionmailer/lib/action_mailer/base.rb#L561" target="_blank">ActionMailer::Base class</a> we indeed have <code>method_missing</code> defined for class methods:</p>

``` ruby
def method_missing(method_name, *args) # :nodoc:
  if action_methods.include?(method_name.to_s)
    MessageDelivery.new(self, method_name, *args)
  else
    super
  end
end
```

<p>Basically, any <strong>action method</strong> defined in mailer class will be intercepted by <code>method_missing</code> and will return an instance of <code>MessageDelivery</code>, otherwise it runs the default implementation. And where do <code>action methods</code> come from? <code>ActionMailer::Base</code> inherits from <code>AbstractController::Base</code>, so it works exactly the same as for controllers - it returns a set of public instance methods of a given class.</p>

<p>We now have a better idea what actually happens when we call class methods on mailers, but it still doesn’t answer the questions: how is the mailer instantiated and how is the instance method called on it? To investigate it further, we need to check <a href="https://github.com/rails/rails/blob/v5.0.0/actionmailer/lib/action_mailer/message_delivery.rb" target="_blank">MessageDelivery</a> class. We are particularly interested in <a href="https://github.com/rails/rails/blob/v5.0.0/actionmailer/lib/action_mailer/message_delivery.rb#L94" target="_blank">deliver_now</a> method (could be any other delivery method, but let’s stick to this single one) with the following body:</p>

``` ruby
def deliver_now
  processed_mailer.handle_exceptions do
    message.deliver
  end
end
```

<p>Looks like <a href="https://github.com/rails/rails/blob/v5.0.0/actionmailer/lib/action_mailer/message_delivery.rb#L103" target="_blank">processed_mailer</a> is the key method that we were looking for:</p>

``` ruby
def processed_mailer
  @processed_mailer ||= @mailer_class.new.tap do |mailer|
    mailer.process @action, *@args
  end
end
```

<p>This method creates the instance of the mailer, calls <code>process</code> method with <code>@action</code> argument (which is the name of the instance method) and with <code>@args</code>, which are the arguments passed to the class method and in the end it returns the created instance of the mailer. Inside <code>handle_exceptions</code> the  <code>deliver</code> method is called. And where does this one come from? <code>MessageDelivery</code> inherits from <code>Delegator</code> class and <a href="https://github.com/rails/rails/blob/v5.0.0/actionmailer/lib/action_mailer/message_delivery.rb#L26" target="_blank">delegates</a>  all the method calls for methods not implemented by <code>MessageDelivery</code> to <code>processed_mailer.message</code>, which is the attribute defined in our mailer instance itself.</p>

<p>And that’s it! It took a bit switching between different methods and classes to understand the entire flow and what happens under the hood, but it’s clear that such interface hiding all the complexity is quite convenient.</p>

<h2>Wrapping up</h2>

<p>Some parts of Rails may contain a lot of "magic" which makes understanding the details more difficult. However, thanks to that magic, the usage of these parts is greatly simplified by the nice abstraction and easy to use interface, which is exactly the case with Rails mailers.</p>
