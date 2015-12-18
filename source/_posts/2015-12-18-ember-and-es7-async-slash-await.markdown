---
layout: post
title: "Ember and ES7: async / await"
date: 2015-12-18 9:50
comments: true
categories: [Ember, JavaScript, ES7, ECMAScript]
---


<p>In the <a href="http://karolgalanciak.com/blog/2015/12/02/ember-and-es7-decorators/" target="_blank">previous blog post</a> we were exploring a new wonderful feature coming with ECMAScript 7: decorators. This time we are going to learn about <code>async / await</code>, which is at this moment at Stage 3 in <a href="https://tc39.github.io/process-document/" target="_blank">TC39 process</a>, which means it's already a release candidate that passed Proposal and Draft stages. Just like decorators, it's already available in <a href="https://babeljs.io">Babel</a>. Let's see what kind of benefits does it offer.</p>

<!--more-->

<h2>A little history of writing asynchronous code in JavaScript</h2>

<p>The most basic and only available solution to write asynchronous code until recently was using callbacks. Let's check  example with multiple HTTP requests with fetching some user with id 1 and creating some task list and task for this user assuming that we have <code>HTTPService</code> that performs <code>GET</code> and <code>POST</code> requests:</p>

``` javascript

HTTPService.get('/users/1', functions(user) {
  HTTPService.post('/task_lists', { name: `default for ${user.name}`, user_id: user.id }, function(taskList) {
    HTTPService.post('/tasks', { name: 'finish setup', task_list_id: taskList.id }, function(task) {
      console.log(`created task ${task.id} for user ${user.id}`);
    }, function(error) {
      console.log(error);
    });
  }, function(error) {
    console.log(error);
  });
});
}, function(error) {
  console.log(error);
});
```

<p>Well, it's not exactly readable. Every inner function depends on the result from previous function which easily leads to Callback Hell a.k.a. Pyramid of Doom. Adding error handling for every callback makes it even worse. Could we somehow make it linear and more readable?</p>

<p>The answer is yes, thanks to promises. I assume that if you use Ember you already know what they are and how they work as they are pretty common in this framework, but for better undertanding you may want to check the <a href="https://developer.mozilla.org/pl/docs/Web/JavaScript/Reference/Global_Objects/Promise" target="_blank">reference</a>. Let's imagine that our <code>HTTPService</code> returns a promise instead of expecting callback-flow. How would the code look in such case?</p>

``` javascript
HTTPService.get('/users/1').then(user => {
  return HTTPService.post('/task_lists', { name: 'default', user_id: user.id });
}).then(taskList => {
  return HTTPService.post('/tasks', { name: 'finish setup', task_list_id: taskList.id });
}).then(task => {
  console.log(`created task ${task.id} for user ${user.id}`);
}).catch(error => {
  console.log(error);
});

```

<p>Isn't it much cleaner? We made the consecutive function calling linear and simplified error handling by having generic function chained in the end.</p>

<p>But still, something doesn't seem right. Promises make the code much better comparing to callbacks, but the syntax itself is a bit heavy as it's totally different than the standard synchronous code. Is it even possible to write asynchronous code (almost) the same way as a synchronous one? Sure it is! Say hello to your new friend: <code>async / await</code>.</p>

<h2>async / await keywords - what they are how to use them</h2>

<p>Imagine for a moment that <code>HTTPService</code> performs synchronous operations. How different would be a code flow when using it? Let's give it a try:</p>

``` javascript
let user = HTTPService.get('/users/1');
let taskList = HTTPService.post('/task_lists', { name: 'default', user_id: user.id });
let task = HTTPService.post('/tasks', { name: 'finish setup', task_list_id: taskList.id });
console.log(`created task ${task.id} for user ${user.id}`);
```

<p>What about error handling? We can use <code>try / catch</code> construct to catch any error:</p>

``` javascript
try {
  let user = HTTPService.get('/users/1');
  let taskList = HTTPService.post('/task_lists', { name: 'default', user_id: user.id });
  let task = HTTPService.post('/tasks', { name: 'finish setup', task_list_id: taskList.id });
  console.log(`created task ${task.id} for user ${user.id}`);
} catch (error) {
  console.log(error);
}
```

<p>The amazing thing is that we can preserve that flow, even though HTTPService returns promises! We just need to <code>await</code> for the result of the asynchronous function call:</p>

``` javascript
try {
  let user = await HTTPService.get('/users/1');
  let taskList = await HTTPService.post('/task_lists', { name: 'default', user_id: user.id });
  let task = await HTTPService.post('/tasks', { name: 'finish setup', task_list_id: taskList.id });
  console.log(`created task ${task.id} for user ${user.id}`);
} catch (error) {
  console.log(error);
}
```

<p>Compare this code to the first version with Pyramid of Doom or even the <code>then</code> chaining in promises - it looks perfectly natural now. Basically, <code>await</code> is a keyword indicating that we wait for the promise to be fulfilled in this place. What about <code>async</code>? Every function that uses <code>await</code> keyword is <code>async</code> so to make our code actually usable we need to wrap it in such function by using this keyword before its definition:</p>

``` javascript
async function setUpDefaultTask() {
  try {
    let user = await HTTPService.get('/users/1');
    let taskList = await HTTPService.post('/task_lists', { name: 'default', user_id: user.id });
    let task = await HTTPService.post('/tasks', { name: 'finish setup', task_list_id: taskList.id });
    console.log(`created task ${task.id} for user ${user.id}`);
  } catch (error) {
    console.log(error);
  }
}
```
<p>From that moment you probably don't think about coming back to the old way of writing asynchronous code :).</p>

<h2>async / await and Ember</h2>

<p>To start using <code>async / await</code> in your Ember app you just need to include polyfill in <code>ember-cli-build.js</code>:</p>

``` javascript
var EmberApp = require('ember-cli/lib/broccoli/ember-app');

module.exports = function(defaults) {
  var app = new EmberApp({
    babel: {
      includePolyfill: true
    }
  });

  return app.toTree();
};
```
<p>Otherwise you will get error with <code>regeneratorRuntime</code> being undefined. You may also consider disabling <code>jshint</code> which sadly doesn't support <code>async / await</code> yet. You might also think about switching to <a href="https://github.com/jonathanKingston/ember-cli-eslint" target="_blank">eslint</a> with <code>babel-esling</code>, which supports every feature implemented in Babel.</p>

<p>Where could it be used? The good canditate would be <code>actions</code> functions in your components / controllers where you probably have a lot of promises with some API calls. Imagine that you have some action with creating a task and transitioning to the <code>task</code> route. With <code>async / await</code> you could simply write it like that:</p>

``` javascript
import Ember from 'ember';

export default Ember.Controller.extend({
  actions: {
    async save() {
      let task = await this.get('task').save();
      this.transitionToRoute('tasks.show', task);
    }
  }
});
```

<p>Which is much simpler than using <code>then</code>:</p>

``` javascript
import Ember from 'ember';

export default Ember.Controller.extend({
  actions: {
    save() {
      this.get('task').save().then(() => {
        this.transitionToRoute('tasks.show', task);
      }
    }
  }
});
```

<p>The other usecase would be acceptance tests. I always forget about using <code>andThen</code> when writing new tests and get failures in something that looks as a valid test. If that's also a case with you then switching to <code>async / await</code> will solve that problem forever. Here's a little example with using traditional approach with <code>andThen</code>:</p>

``` javascript
import Ember from 'ember';
import {
  module,
  test
} from 'qunit';

var application;

module('Acceptance: SomeTest', {
  beforeEach: function() {
    application = startApp();
  },

  afterEach: function() {
    Ember.run(application, 'destroy');
  }
});


test('it clicks button', function(assert) {
  click('.some-button');

  andThen(function()  {
    assert.equal(find('.clicked-button').length, 1);
  });
});
```

<p>Not really ideal. The example below looks much better:</p>

``` javascript
import Ember from 'ember';
import {
  module,
  test
} from 'qunit';

var application;

module('Acceptance: SomeTest', {
  beforeEach: function() {
    application = startApp();
  },

  afterEach: function() {
    Ember.run(application, 'destroy');
  }
});


test('it clicks button', async function(assert) {
  await click('.some-button');
  assert.equal(find('.clicked-button').length, 1);
});
```

<p>Much more intuitive, we just need to remember about adding <code>async</code> before callback in <code>test</code> function, but we are going to get syntax error if we use <code>await</code> in not <code>async</code> function, so the issue will be obvious.</p>

<h2>Wrapping up</h2>

<p><code>async / await</code> is another excellent addition in Javascript world, which may become a real game changer when it comes to writing asynchronous code. Thanks to Babel again, we can easily start using it even today.</p>
