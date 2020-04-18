---
layout: post
title: "The Problems With Validating ActiveRecord Models And Why State Validation Is a Bad Idea"
date: 2018-09-30 20:00
comments: true
categories: [Rails, Ruby, Ruby on Rails, ActiveRecord, Design Patterns, Architeture, Architecture]
---

In the typical **Rails application**, you can find the most of the validations in the **ActiveRecord models**, which is nothing surprising - ActiveRecord models are used for multiple things. Whether it is a good thing, or a bad thing (in most cases it's the latter) deserves a separate book or at least blog post-series as it's not a simple problem, there is one specific thing that can cause **a lot of issues** that are **difficult to solve** and go beyond **design decisions** and ease of maintenance of the application, something that impacts the behavior of the model - **the validations**.

Just to give you a real-world example of what validation in ActiveRecord model looks like (as impossible as it seems, it really did happen) - when updating the check-in time of the reservation, which is a simple attribute on Reservation model, the record turned out to be invalid because... the format of guest's phone didn't match some regexp.

There are multiple ways to bypass this problem: use `validate: false` flag with `save` method: `save(validate: false)` or use `update_columns` method, but this is definitely not something that can be applied in a "normal" use case. In a typical scenario, this will be the error message displayed in the UI/returned to API consumer, and it will be confusing.

However, this is the expected behavior of ActiveRecord (or in general, ActiveModel-style) validations, which is **a validation of the state** of the model. And judging from this example, it's evident that it leads to **problematic scenarios**. What kind of design then would be the most appropriate to **prevent such issues**?

<!--more-->

## Forget State Validation

Based on the previous example, it's clear that the real problem is the idea of a model's state validation. And the more complex state of the models can be (especially if there are some cross-validations between several models, which is not uncommon in complex applications), the more problems you will get.

Just wanted to update some `notes` attribute to add some quick info about something? Forget it - you will get three different validation errors that will tell you that someone's email has an invalid format, description is too short, a discount amount of something is invalid.

Sadly, this is the typical Rails Way of handling validations. In the initial phase of the application, this is certainly convenient - adding new validations is super easy, there is no need to discuss the design of potential alternatives and how it fits the bigger picture, and there is very little overhead. Unless you are ok with such problems, at some point, you will probably need to migrate validations to some other solution. What would be the potential alternative for validations?

## Validate The Actual Use Case

The answer to that question is straight-forward (although it doesn't mean that achieving it will be simple) - just validate the thing you are doing, the actual use case. If you want to update `description`, you should only be concerned with the description - if it's present or not, it's length, etc., whether `headline` is too short or not (this can happen when you change the validation rules and don't somehow migrate the data) is not the subject of that use case.

There are a lot of implications of such approach - indeed, it will result in different sets of validators per creation and per update, since for creation we usually need way more data, and for an update, we may merely want to update a single attribute. Effectively, it will result in different validation pipelines for create and update actions. For creating, we may always need to apply specific validators (e.g., presence validators for some attributes), but for updating it will make more sense to apply only the validators for what we are trying to do - when we want to update email, we apply the presence and format validation for an email, if we want to update a description, we apply presence and length validators for a description.

## Potential Implementation

What would be the way to implement it? The specific design is out of the scope of this article as it might require building mini-framework for validations and consider some design implications on the entire application (especially if we are escaping the traditional Rails Way). However, one thing is sure here - there will be dedicated validator objects, probably different for create and update action, and the validations will need to be removed from ActiveRecord models.

A potential way of interacting with such objects could look like this:

``` rb
validation_result = Reservation::CreateValidator.call(params)
if validation_result.success?
  # handle happy path here
else
  puts validation_result.errors.messages # for convenience and familiarity, `errors` object could have a similar interface to ActiveModel::Errors
end
```

What if we need the model itself in the validator due to some complex business rules, like cross-model validation? We could either reuse `id` from `params` or just provide `model` as an argument:

``` rb
validation_result = Reservation::CreateValidator.call(record, params)
```


## Side-Effects Of Such Design

The implications of such design go far deeper than just moving things from one place to another to prevent some edge cases (and naturally increasing the complexity of the design, but it seems to be a fair price to pay for what we get as a result). Since it would make the most sense to have validations per use case, then... maybe we can have use case as objects that would expose their constraints, and the validators would take the rules from those objects and apply some specific logic on top of it to achieve the desired result? Maybe we could even create value objects composed of a single or multiple attributes, e.g. `Client::Email` object that would enforce its constraints and also, move some logic specific to the email itself in the context of a hypothetical `Client` model? And if we can identify the use cases themselves, aren't they domain events? And how hard would it be to build event-based architecture, or even apply Event Sourcing?

These are not trivial questions, however, doing one change in the design opens
the door to a holistic architectural approach where all parts of the domain fit together and the interaction between them is way more intentional comparing to ad hoc duct-tape-like solutions.

## Wrapping Up

Putting **too much logic** in **ActiveRecord models** has a lot of disadvantages, most of them being problematic on the **design level**. However, things like validations can result in some nasty issues that go beyond the maintenance and cause actual business problems. Fortunately, by keeping that in mind and putting the **validation logic** in a **separate object(s)**, we can easily avoid such issues and as a nice side-effect, have a design that is way more flexible, extendible and eventually simpler to maintain.
