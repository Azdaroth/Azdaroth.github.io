---
layout: post
title: "5 years of professional Ruby and Rails development - My Reflections"
date: 2017-07-30 23:00
comments: true
categories: [Ruby, Rails, Ruby on Rails]
---

As hard as it is for me to believe, I already have over **5 years** of professional experience in **Ruby and Rails** development. Throughout all these years my attitude towards Rails has been fluctuating between going from **blind love** to **harsh critic** (ActiveRecord, I'm looking at you) ending with a bit more balanced but certainly a positive approach. Such time is long enough to have a meaningful opinion about the **overall experience** using any framework, so here are few points about Rails that I would like particularly to focus on in my reflections.

<!--more-->

## ActiveRecord and models layer

ActiveRecord is arguably the biggest and the most important part of Rails. Not only is it quite complex itself, but following the "skinny controllers, fat models" mantra often leads to creating huge models which extend `ActiveRecord::Base` making it virtually a huge part of the majority of the applications. So what has been my experience with this layer for the last 5 years?

When I was starting with Rails I naturally followed the default "Rails Way" which meant moving logic from the controllers to models, handling entire business logic in models' classes and adding callbacks here and there for the logic around persistence. And it was awesome initially! I was able to progress with all the features really fast, even in spite of lacking meaningful Rails experience.

But then I started to experience some serious issues: I had to handle big part of the logic with a lot of conditionals depending on the context, some methods were handling logic for both creation of the records and the updates, but only with a slight differences, which added even more conditionals to that. The validation logic started to become complex which required conditional validations as well. And one day, when running some data migrations I used `update_attributes` instead of `update_columns` and tons of email notifications were sent to the users due to some callbacks that were responsible for sending notifications...

At that point I pretty much lose control over the application logic as I was not able to tell any longer what something so fundamental as calling `update` or `save` can lead to. That was the time when my default policy regarding models was "no callbacks ever, no conditional validations ever, ideally no logic at all." This approach worked for a while, but eventually it lead to some other issues like distributing similar logic between many objects (service objects and form object mostly), duplication of the logic and feature envy code small, even though it was quite clear that the logic belonged to the models. Aparently, the anemic domain model approach didn't work as well as I had thought it would. Another case was that I was doing whatever it takes to avoid callbacks and lost quite a lot of time with fighting some gems that were coupled to the models via callbacks. That could have been a right thing to do from the "purity" perspective, but it wasn't the smartest decisision business wise - the purpose of the code is to serve the business and provide the required functionality, not to be possibly the purest solution. Maintainability is one thing, but it's easy to reach a point of diminishing return in most applications where more purity and better design doesn't necessarily lead to a greater practical value, but takes definitely a lot of time.

All those events lead to more balanced attitude that I have now towards ActiveRecord and model layer. Callbacks, complex conditional validations and other typical Rails Way techniques are far from being my preferred way of handling business logic and in general I consider those approaches harmful in the long-term perspective, but I clearly see how they can be beneficial in short-term perspective when developing MVP and the rapid speed of development is required and maintainability is secondary or when something can be cleverly handled even in more complex application with minimum effort (like <a href="https://github.com/carrierwaveuploader/carrierwave" target="_blank">Carrierwave</a> callbacks, using `touch` and `dependent` associations' options erc.).

I also tend to put model-related logic in, well, models. Does it lead to fat models? Sometimes yes, In bigger applications than can easily lead to the models with 200-300 lines of code. But if the logic is cohesive and not really context-dependent I don't find it a big issue - the clarity is most often preserved, maintainability is not negatively impacted. The important thing is to put there only a generic domain model logic, ideally not related to the persistence itself.

Following that approach has been working pretty great for me and I don't really complain about ActiveRecord anymore. Maybe the architecture is a bit limiting and something like data mapper pattern would be more flexible. Or some methods like `update_attribute` / `update_columns` can be really confusing when used without a right reason or even more exotic featurs like ActiveRecord Suppress can lead to the code that is hard to reason about. Nervertheless, it is still possible to mantain models in a good condition using ActiveRecord and just the fact that something can do a lot of harm doesn't mean that it should not be there at all - it's a developer's responsibility to choose the tools for solving the problem wisely.

## Lack of Higher Level Architecture

Rails is sometimes criticized for not providing higher-level architecture and there are a lot of solutions that are supposed to fill that hole (e.g. <a href="https://github.com/trailblazer/trailblazer" target="_blank">Trailblazer</a> which is a mini-framework providing form objects, operation classess and more). However, I don't necessarily think it's a bad decision.

Models and controllers are generic enough that to some extent they can be pretty much similar in most of the applications. What about some higher level layers?

There are plenty of gems implementing form objects, service objects and other layers and most often they are significantly different from another. And just adding service objects or form objects might not be the best design decision ever. Maybe going full CQRS / Event Sourcing approach is better? And how would you know what should be the structure of service objects or operations or read / write models?

It would probably be extremely difficult to find a solution that would satisfy most of the Rails developers and any attempt to add those layers to Rails could end up with conflicts about the implementaiton details and/or interfaces, which wouldn't be really productive.

The current approch of focusing on existing layers is in my opinion the right one and any reasonably experienced developer shoudl be able to figure out what kind of architectural approach would be the best fit for the given application.

## ActiveSupport

Another layer that is arguably widely considered to be problematic is ActiveSupport, especially the monkeypatching part. I'm not a fan of monkeypatching myself and I almost never do it, however, the core extentions provided by ActiveSupport are extremely useful and very convenient and I don't really rememeber having any major problems with them. I can agree that it might not be the most "elegant" solution from the purity perspective, but it gets the job done and does it well - this is ultimately the most important factor when it comes to software engineering. I think the overall critique of ActiveSupport is a bit far-fetched and the practical negative implications of what ActiveSupport provides are negligible. However, there are quite a lot of positive outcomes which cannot be overlooked.

## What About Other Frameworks?

I've had a chance to try some different frameworks than Rails throughout all these years - including Django (Python), Play (Java), Phoenix (Elixir), Meteor (JavaScript) or other Ruby frameworks - Sinatra and Hanami. They were quite fun to work with, but the productivity and the enjoyment of development couldn't possibly match the Rails experience. Obviously, the maturity of the ecosystem plays a huge role here and that's why some of the newer frameworks have a much harder time competing with Rails, nevertheless, even Rails out-of-box without any extra gems offers a great productivity which is significantly higher comparing to the other frameworks.

## Future

Currently I don't see any framework that could possibly replace Rails in the near future, at least not for the generic webdevelopment. Phoenix, which somehow resembles Rails, might be the closest one, but in my opinion the Elixir language and functional paradigm are much harder to learn than Ruby and Object Oriented Programming. Also, due to the much bigger community, maturity and overall ease of development in Rails, it might take quite a long time until Phoenix catches up, despite having some clear advantages over Ruby and Rails like speed and concurrency (thanks to Erlang virtual machine).

## Wrapping Up

Ruby on Rails definitely made my professional life amazing and it's been a **great joy** to develop all the applications I've had a chance to work on, in spite of few times when I had a bit negative attitude towards it. Even though there are some imperfections, Rails is still a **number one choice** for me for the majority of the cases and I don't see it moving anyway in the near future.
