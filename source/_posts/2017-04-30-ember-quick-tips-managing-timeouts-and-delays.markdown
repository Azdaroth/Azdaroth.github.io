---
layout: post
title: "Ember Tips: Managing Timeouts And Delays"
date: 2017-03-30 22:00
comments: true
categories: [Ember, JavaScript, ES6, Quick Tips]
---

**Timeouts** and **delays** are quite extensively used in many applications when deferring execution of some action using `Ember.run.later` or debouncing via `Ember.run.debounce`. Having small amounts of tests executing such methods might not be a problem initially, but obviously, as the application grows, this can easily lead to **slow test suite** which takes minutes to finish due to the waiting for all the timeouts and delays in many places. Let's try to find the best solution to solve this problem.

<!--more-->

## Anatomy of The Problem

Imagine you are implementing a todo-list and want to add a **destroy item feature**. The obvious solution would be adding a button which would trigger some `destroy` action once a user clicks it. But the problem with such solution is that it doesn't offer the best **UX** as a user could easily destroy items **by accident**. A nicer way for such use cases is making a user hold the button for a certain period of time and only after this **delay** would the action be called, otherwise it won't be executed.

A great news is that there is already an addon solving such problem: <a href="https://www.npmjs.com/package/ember-hold-button" target="_blank">ember-hold-button</a>. Let's create a very simple component handling the logic of displaying the item and deleting it after holding a button for 3 seconds using `ember-hold-button`:

``` javascript app/components/display-todo-item.js
import Ember from 'ember';

const {
  get,
} = Ember;

export default Ember.Component.extend({
  actions: {
    destroy() {
      const item = get(this, 'item');

      item.destroyRecord();
    },
  },
});
```

{% raw %}
``` html app/templates/components/display-todo-item.hbs
{{item.name}}
{{#hold-button type="rectangle" action="destroy" delay=3000 data-test="destroy-item-btn"}}
  Destroy
{{/hold-button}}
```
{% endraw %}


Ok, cool, so the feature is done. What about integrations tests verifying that this feature works? Currently it would take at least 3 seconds due to the waiting time + the runtime of the test itself, which is definitely too slow.

## Solving The Problem

One way to fix this problem would be moving `delay` to computed property which would be configurable and by default make it equal to 3 seconds. The component would look like this in such case:


``` javascript app/components/display-todo-item.js
import Ember from 'ember';

const {
  get,
} = Ember;

export default Ember.Component.extend({
  destroyActionDelay: 3000,

  actions: {
    destroy() {
      const item = get(this, 'item');

      item.destroyRecord();
    },
  },
});
```

{% raw %}
``` html app/templates/components/display-todo-item.hbs
{{item.name}}
{{#hold-button type="rectangle" action="destroy" delay=destroyActionDelay data-test="destroy-item-btn"}}
  Destroy
{{/hold-button}}
```
{% endraw %}


To make integration tests fast, we would simply override the default value of `destroyActionDelay` and render the component in the test the following way:

{% raw %}
``` javascript tests/integration/components/display-todo-item-test.js
// the rest of the tests

this.render(hbs`{{display-todo-item item=item destroyActionDelay=0}}`);

// the rest of the tests
```
{% endraw %}

This surely solves the problem for **integration tests**, but what about the **acceptance ones**? It would still take at least 3 seconds of waiting for this delay.

To solve this problem, we could add a special function which would return the value **based on the environment**. For **non-test** we may want to return a provided value and for test environment some other value, which by default would be equal to 0 to make the tests fast. Let's add such a utility function and call it `timeoutForEnv`:


``` javascript my-app/app/utils/timeout-for-env.js
import config from 'fitbot-client/config/environment';

export default function timeoutForEnv(timeout, timeoutForTestEnv = 0) {
  debugger;
  if (config.environment === 'test') {
    return timeoutForTestEnv;
  } else {
    return timeout;
  }
}
```

And update the component:


``` javascript app/components/display-todo-item.js
import Ember from 'ember';
import timeoutForEnv from 'fitbot-client/utils/timeout-for-env';

const {
  get,
} = Ember;

export default Ember.Component.extend({
  destroyActionDelay: timeoutForEnv(3000),

  actions: {
    destroy() {
      const item = get(this, 'item');

      item.destroyRecord();
    },
  },
});
```

If we wanted for some reason to have a delay different than `0` for the test env, we could simply provide the value of second argument:

``` javascript app/components/display-todo-item.js
import Ember from 'ember';
import timeoutForEnv from 'fitbot-client/utils/timeout-for-env';

const {
  get,
} = Ember;

export default Ember.Component.extend({
  destroyActionDelay: timeoutForEnv(3000, 1000),

  actions: {
    destroy() {
      const item = get(this, 'item');

      item.destroyRecord();
    },
  },
});
```

And that's it! It will work for both integration and acceptance tests.


## Wrapping Up

Using a lot of **timeouts** and **delays** without special adjustments for tests can easily lead to a very **slow test suite** as the application grows. Fortunately, it's quite easy so solve this problem by using **environment-dependent** config and setting the values to `0` for tests.

P.S. I've just started **writing a book** about **test-driving Ember** applications. If you found this article useful, you are going to love it :). **Subscribe** to my newsletter to get updates and promotion code once it's released.
