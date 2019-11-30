---
layout: post
title: "Model your domain with composed models"
date: 2015-02-26 9:10
comments: true
categories: [OOP, Rails, Design Patterns, Refactoring]
---

<p>In many Rails applications the modeling is limited only to creating classes inheritng from <code>ActiveRecord::Base</code> which are 1:1 mapped to database tables. Having AR models like <code>User</code> and <code>Project</code> doesn't tell much about the domain of your application. Well, you can add some domain logic to the models but that way you will easily end up having giant classes with thousands lines of code, so let's just use models for database-related stuff only. Other option would be to create service objects for every usecase. That's a good and clean way, but it's merely the interaction layer between different parts of your application. You may end up easily with all logic encapsulated within service objects that will start looking more like procedural programming rather than proper OOP and not real domain API at all. The good news is that you can easily counteract it: time to use composed models.</p>

<!--more-->

<h2>Definition and examples composed models</h2>

<p>Composed models are classes which emphasize the relation between entities and the interactions between them. In most applications the models have multiple different relations between each other, rarely are they self-contained. So what happens if we take some entities and try to put them in one class?</p>

<p>Imagine you are developing project management application and you've got <code>User</code>, <code>Project</code> and <code>Task</code> models. What are the possible interactions between these models? User can be assigned to many tasks in a given project, so we can both query for the existing tasks and add some new tasks. We would probably query for finished tasks, currently being done and the ones not started. We may also check if user is in given project or can add/remove him/her from the project. In this case, the predominant relation is the one between the <code>user</code> and <code>project</code>, so let's create a class <code>UserWithProject</code>. We will make it a decorator over these two models, so the class will take both <code>user</code> and <code>project</code> to constructor:</p>

``` ruby
class UserWithProject
  attr_reader :user, :project
  private     :user, :project

  def initialize(user, project)
    @user = user
    @project = project
  end
end
```

<p>Let's add some actual logic to our composed model: querying for different tasks for related <code>user</code> and <code>project</code>, adding new tasks, checking if user is assigned to the project and maybe leaving the project. </p>

``` ruby
class UserWithProject
  attr_reader :user, :project
  private     :user, :project

  def initialize(user, project)
    @user = user
    @project = project
  end

  def tasks
    @tasks ||= project.tasks.with_assignee(user)
  end

  def pending_tasks
    tasks.pending
  end

  def finished_tasks
    tasks.finished
  end

  def not_started_tasks
    tasks.not_started
  end

  def add_task(task)
    task.asignee = user
    task.project = project
    task.save!
  end

  def assigned_to_project?
    project.users.include?(user)
  end

  def leave_project
    project.users.destroy(user)
  end
end
```

<p>Most methods are probably self-explanatory and don't need to be discussed. Now we have an actual domain model which neatly encapsulates interactions between <code>users</code>, <code>projects</code> and <code>tasks</code>. Looks like a real API for application that can be simply (re)used.</p>

<p>One usecase for composed models is about interactions between models. But this patterns also shines when you consider some modifiers of values. By modifier I mean an object that has some kind of influence on values being returned by methods of other object. For example you might be developing an e-commerce app and have <code>Order</code> with <code>total_price</code>. Let's imagine that you need to handle discounts for orders, which as you max expect, are going to decrease <code>total_price</code>. With composed model pattern you could create <code>OrderWithDiscount</code> class. To make it still behave like an <code>Order</code> instance, the class may inherit from <code>SimpleDelegator</code> and all the method calls not implemented by <code>OrderWithDiscount</code> are going to be delegated to <code>Order</code>:</p>

``` ruby
class OrderWithDiscount < SimpleDelegator
  attr_reader :order, :discount
  private     :order, :discount

  def initialize(order, discount)
    @order = order
    @discount = discount
    super(order)
  end

  def total_price
    # somehow apply the discount.value to order.total_price
  end
end
```

<p>That way you can still have <code>total_price</code> on Order without adding additional arguments, conditionals etc. for handling discounts and have a separate object for special usecases.</p>

<h2>Extracting existing logic to composed models</h2>

<p>Now that you know how what are the composed models for, you may be wondering how to extract already existing codebase to that pattern. Fortunately, it's easy to tell in many cases if a particular method is a good fit to move. When you have multiple methods in one class taking the same kind of argument(s), that's probably a good idea to think about some changes. Let's use the example with <code>User</code> and <code>Project</code>. If that pattern hadn't been used there we would probably have had some code in <code>Project</code> model looking like this:</p>

``` ruby
class Project < ActiveRecord::Base
  # associations and stuff like that

  def tasks_for_user(user)
    # some logic
  end

  def pending_tasks_for_user(user)
    # some logic
  end

  def finished_tasks_for_user(user)
    # some logic
  end

  def add_task_for_user(task, user)
    # some logic
  end
end
```
<p>This class really begs for refactoring ;). Another sign would be having methods where there might be an argument modyfing the value or may not. Using the <code>Order</code> example, there could be a method like:</p>

``` ruby
class Order < ActiveRecord::Base
  def total_price(discount: nil)
    # somehow calculate the total_price
    if discount?
      # apply the discount
    end
  end
end
```

<p>Doesn't really look great, having separate class makes it much easier to read and understand.</p>

<h2>Wrapping up</h2>

<p>I've shown a pretty cool pattern I've started using recently, which works really great and makes a big difference when looking at the domain logic of the application. I hope you will find it useful.</p>