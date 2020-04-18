---
layout: post
title: "Test Driven Ember - Testing Holding a Button"
date: 2017-03-26 23:00
comments: true
categories: [Ember, JavaScript, Testing, TDD, Quick Tips]
---

Thanks to the awesome tools in **Ember ecosystem** such as <a href="http://github.com/samselikoff/ember-cli-mirage/" target="_blank">ember-cli-mirage</a>, <a href="https://github.com/emberjs/ember-test-helpers" target="_blank">ember-qunit</a> or <a href="https://github.com/emberjs/ember-test-helpers" target"_blank">ember-test-helpers</a> writing majority of the tests is pretty straight-forward. Nevertheless, there are quite a few cases where **simulating user's interaction** is not that simple. An example of such use case would be **holding a button** for particular period of time triggering some side effect.

<!--more-->

## Anatomy of The Problem

Imagine you are implementing a feature of destroying some records in your application, e.g. the todo items from the list. It would be a bit unfortunate to destroy any item if a user **accidentally clicked** on the destroy button, so it might be a good idea to somehow make it harder to execute such an action. A simple approach would be displaying some alert **asking user to confirm** whether this item should be removed or not. This approach would get our job done, but it doesn't offer the best **UX**. What are the better options here?

A pretty cool solution to this problem would be making user **hold a delete button** for a particular period of time, e.g. for 3 seconds. Holding this button for less than 3 seconds wouldn't destroy the item, so it would be impossible to accidentally delete anything.

There is an addon which solves exactly this problem: <a href="https://www.npmjs.com/package/ember-hold-button" target="_blank">ember-hold-button</a>, so there is no need to reinvent the wheel. Let's add this to our application.


## Adding Destroy Action

Let's start by installing `ember-hold-button` addon:

```
ember install ember-hold-button
```

and assume that we already have some component for displaying a single item with `destroy` action:

``` javascript
// app/components/display-todo-item.js
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
``` html
// app/templates/components/display-todo-item.hbs
{{item.name}}
<button {{action "destroy"}} data-test="destroy-item-btn">Destroy</button>
```
{% endraw %}

and that the component was test-driven with the following test written before the actual implementation (TDD for FTW!):

{% raw %}
``` javascript
// tests/integration/components/display-todo-item-test.js
import Ember from 'ember';
import { moduleForComponent, test } from 'ember-qunit';
import hbs from 'htmlbars-inline-precompile';

const {
  set,
  RSVP,
} = Ember;

moduleForComponent('display-todo-item', 'Integration | Component | display todo item', {
  integration: true
});

test('item can be destroyed', function(assert) {
  assert.expect(1);

  const {
    $,
  } = this;

  const item = Ember.Object.extend({
    destroyRecord() {
      assert.ok(true, 'item should be destoyed');

      return RSVP.resolve(this);
    },
  });

  set(this, 'item', item);

  this.render(hbs`{{display-todo-item item=item}}`);

  const $destroyBtn = $('[data-test=destroy-item-btn]');

  $destroyBtn.click();
});
```
{% endraw %}


Basically this test verifies that the `destroyRecord` method will be called on item after clicking the button.

Let's add `hold-button` which will trigger `destroy` action after holding it for 3 seconds:

{% raw %}
``` html
// app/templates/components/display-todo-item.hbs
{{item.name}}
{{#hold-button type="rectangle" action="destroy" delay=3000 data-test="destroy-item-btn"}}
  Destroy
{{/hold-button}}
```
{% endraw %}

`delay` option will get the job done here to make it holdable for 3 seconds to trigger `destroy` action.

The button is working great, but our test obviously is failing now! How can we simulate holding action in our integration tests?

## Testing Holding Interaction

To solve that problem we should break the problem down into the single events. On desktop, pressing a button simply means triggering `mouseDown` event and releasing means trigger `mouseUp` event. On mobile that would be `touchStart` and `touchEnd` events accordingly.

Based on how `hold-button` component works, we may suspect that there is some internal timer which starts counting time after triggering `mouseDown` (`touchStart`) event or a scheduler which executes the action if it was held for required period of time and cancels it if it was released before that period of time, which would mean cancelling timer on `mouseUp` event.

After checking <a href="https://github.com/AddJam/ember-hold-button/blob/master/addon/components/hold-button.js" target="_blank">the internals</a>, it turns out this is exactly the case! Let's rewrite our test by triggering these events. We will also need two extra things as we are dealing with asynchronous actions:

* `async()` / `done()` - To make sure QUnit will wait for an asynchronous operation to be finished we need to use `async()` function. That way QUnit will wait until `done()` is called. We will call `done()` after triggering `mouseUp` event. But we also need to wait until the action is executed. We will need `wait()` helper for that.

* `wait()` - it forces run loop to process all the pending events. That way we ensure that the asynchronous operation have been executed (like calling `destroy` action after 3 seconds).

Here's our new test:

{% raw %}
``` javascript
// tests/integration/components/display-todo-item-test.js
import Ember from 'ember';
import { moduleForComponent, test } from 'ember-qunit';
import hbs from 'htmlbars-inline-precompile';
import wait from 'ember-test-helpers/wait';

const {
  set,
  RSVP,
} = Ember;

moduleForComponent('display-todo-item', 'Integration | Component | display todo item', {
  integration: true
});

test('item can be destroyed', function (assert) {
  assert.expect(1);

  const {
    $,
  } = this;

  const item = Ember.Object.extend({
    destroyRecord() {
      assert.ok(true, 'item should be destoyed');

      return RSVP.resolve(this);
    },
  });

  set(this, 'item', item);

  this.render(hbs`{{display-todo-item item=item}}`);

  const $destroyBtn = $('[data-test=destroy-item-btn]');

  $destroyBtn.mousedown();

  wait().then(() => {
    $destroyBtn.mouseup();
    done();
  });
});
```
{% endraw %}

Nice! Our test is passing again. However, there is one serious problem: this test is quite slow as it waits 3 second for the action to finish. Can we make it somehow faster?

## Making Our Test Faster

The answer is: yes. We just need to provide a way to make `delay` configurable from the outside. This can be simply done by introducing `destroyActionDelay` property with default value equal `3000` and allowing it to be modified. Let's start with applying this little change to the test:

{% raw %}
``` javascript
// tests/integration/components/display-todo-item-test.js
// the rest of the tests
this.render(hbs`{{display-todo-item item=item destroyActionDelay=0}}`);
```
{% endraw %}

We don't care about waiting for 3 seconds in the tests, we just want to test if it works and to make it fast. `0` sounds like the most reasonable value in such case.

And let's change few things in our component:

``` javascript
// app/components/display-todo-item.js
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
``` html
// app/templates/components/display-todo-item.hbs
{{item.name}}
{{#hold-button type="rectangle" action="destroy" delay=destroyActionDelay data-test="destroy-item-btn"}}
  Destroy
{{/hold-button}}
```
{% endraw %}


And that's it! You can now enjoy the much faster test suite!


## Wrapping Up

Testing holding a button for particular period of time doesn't sound like an obvious thing to do. Fortunately, with proper design and understanding the interaction from the **browser's perspective**, it isn't that hard to do and doesn't necessarily make your tests slower.

P.S. I've just started **writing a book** about **test-driving Ember** applications. If you found this article useful, you are going to love it :). **Subscribe** to my newsletter to get updates and promotion code once it's released.
