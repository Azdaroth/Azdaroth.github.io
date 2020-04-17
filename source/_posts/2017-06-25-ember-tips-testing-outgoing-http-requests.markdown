---
layout: post
title: "Ember Tips: Testing Outgoing HTTP Requests"
date: 2017-06-25 22:00
comments: true
categories: [Ember, JavaScript, ES6, Quick Tips]
---

**Ember.js** is a web frontend framework and it's no surprise that majority of the applications deal with a lot of **HTTP requests**. But such fact has a lot of implications on the process of development of the Ember apps, especially when it comes to **testing**. For basic `GET` requests which don't include any query params or don't deal with pagination it's quite straight-forward - for those we just want to fetch some data, so we can check if proper objects are present as a side-effect of these requests. What about `POST`, `PATCH` or `DELETE` requests, where we can't easily test the side effects?

Fortunately, thanks to the awesome tools such as <a href="https://github.com/pretenderjs/pretender" target="_blank">pretender</a> and <a href="https://github.com/samselikoff/ember-cli-mirage" target="_blank">ember-cli-mirage</a>, it's not a big problem.

<!--more-->

## Scenario #1: Testing if the request body sent in the outgoing request is right

Imagine that you are writing a classic sign-up for users. It would be quite useful to ensure that the right params are indeed sent to the `/api/users` endpoint (if that's the case).

For dealing with HTTP requests and/or implementing a backend mock, <a href="https://github.com/samselikoff/ember-cli-mirage" target="_blank">ember-cli-mirage</a> addon is a great choice. The setup is beyond the scope of this article, but if you happen to not be familiar with `ember-cli-mirage`, I highly recommend reading the <a href="http://www.ember-cli-mirage.com" target="_blank">docs</a> which are very clear about the setup and its features.

Let's assume that we have a proper route generated for the signup, let it be a `signup` route, a corresponding `signup` controller already handling a logic for the registration in one of its actions and that we have a `User` model with `email` and `password` attributes. Our scenario will be pretty simple: we want to make sure that after filling in `email` and `password` fields and clicking the `submit` button the request will be performed to `/api/users` with the right params. Here's our test for the signup feature:

``` javascript my-awesome-app/tests/acceptance/sign-up.js
/* global server */
import { test } from 'qunit';
import moduleForAcceptance from 'book-me/tests/helpers/module-for-acceptance';

moduleForAcceptance('Acceptance | sign up');
test('user can successfully sign up', function(assert) {
  assert.expect(1);

  server.post('/api/users', function(schema)  {
    const attributes = this.normalizedRequestAttrs();
    const expectedAttributes = {
      email: 'example@email.com',
      password: 'secretpassword'
    };

    assert.deepEqual(attributes, expectedAttributes, "attributes don't match the expected ones");

    return schema.users.create(attributes);
  });

  visit('/signup');

  andThen(() => {
    fillIn('[data-test=signup-email]', "example@email.com");
    fillIn('[data-test=signup-password]', 'secretPassword');

    click('[data-test=submit-signup]');
  });
});
```

In this acceptance test we visit the `signup` page, provide the email and password combo and we click on the submit button. There is only one simple assertion here: comparing the expected attributes against the normalized attributes from the requests to `/api/users` endpoint - we use normalized attributes to avoid dealing with JSONAPI format. To achieve that we provide a custom action handler which is very close to the default implementation for `POST` actions from `ember-cli-mirage`. The only extra step here is comparing the attributes.

What if we want to just make sure that the request was performed to the given endpoint, but we don't care about the request body?

## Scenario #2 Testing if the request was performed to the given endpoint

For this scenario imagine that we want to have a feature of deleting some tasks from the to-do list. The simplest way to make sure that the task will be removed would be checking if the `DELETE` request was performed to `/api/tasks/:id` endpoint. Again, let's assume that we already have a right implementation for this feature (too bad we didn't practice strict TDD to develop it properly).

For this use case we will do something a bit different than the last time. First, let's add the right config for the `ember-cli-mirage` to handle CRUD actions for `tasks` using `resource` helper:

``` javascript my-awesome-app/mirage/config.js
export default function() {
  this.namespace = 'api';

  this.resource('users');
}
```

And that's how our test could look like:

``` javascript my-awesome-app/tests/acceptance/delete-task.js
/* global server */
import { test } from 'qunit';
import moduleForAcceptance from 'book-me/tests/helpers/module-for-acceptance';

moduleForAcceptance('Acceptance | delete task');
test('user can delete tasks', function(assert) {
  assert.expect(1);

  const task = server.create('task');

  visit('/tasks');

  click('[data-test=delete-task]');

  andThen(() => {
    const taskUrl = `/api/tasks/${task.id}`;
    const deleteTaskRequest = server.pretender.handledRequests.find((request) => {
      return request.url === taskUrl && request.method === 'DELETE';
    });

    assert.ok(deleteTaskRequest, 'delete task request should be performed');
  });
});
```

Again, our test has a very simple structure: we visit the `tasks` route where all the tasks are displayed and delete the one we created in the test's setup. To make sure that the request was performed to the right endpoint we take advantage of the fact that `ember-cli-mirage` uses `pretender` under the hood which keeps track of all handled requests in `handledRequests` property. Thanks to this feature, we can identify our request based on the **URL** and the **request method**.

## Wrapping Up

Testing **outgoing requests** in Ember might not be the most obvious thing to do. Fortunately, thanks to <a href="https://github.com/pretenderjs/pretender" target="_blank">pretender</a> and <a href="https://github.com/samselikoff/ember-cli-mirage" target="_blank">ember-cli-mirage</a>, we can easily verify both the **URLs** of the endpoints where the requests were performed to and the **request body** that was sent with the request.

P.S. I've just started **writing a book** about **test-driving Ember** applications. If you found this article useful, you are going to love it :). **Subscribe** to my newsletter to get updates and promotion code once it's released.
