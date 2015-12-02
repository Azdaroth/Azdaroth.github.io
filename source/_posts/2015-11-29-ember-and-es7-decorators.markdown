---
layout: post
title: "Ember and ES7: decorators"
date: 2015-12-02 23:30
comments: true
categories: [Ember, JavaScript, ES7, design patterns]
---


<p>ES6 introduced plenty of useful features such as modules, arrow functions, let variables, destructuring, classes and many more which made writing JS code much readable and enjoyable. Thanks to <a href="https://babeljs.io" target="_blank">Babel</a>, a JavaScript transpiler, it's been pretty painless to use them all in the applications. If you happen to develop EmberJS apps and use <a href="http://www.ember-cli.com" target="_blank">ember-cli</a>, you don't probably think much about Babel or any transpilation as these features are a natural part of every Ember application. But the new features didn't end with ES6, we're going to have even more of them in ES7 (2016). Some of them can already be used, thanks again to Babel. In this blogpost I'm going to explore a very powerful concept which of decorators.</p>

<!--more-->

<h2>Decorators - what are they and how to use them?</h2>

<p>Decorators are expressions (functions) taking <code>target</code>, <code>name</code> and <code>descriptors</code> as arguments and allowing to modify classes and properties using declarative syntax at design time. It sounds interesting, but doesn't say much what exactly it does. Let's check some basic example and examine what these arguments are and how to apply the decorator:</p>

``` javascript
function describe(target, name, descriptor) {
  console.log(target);
  console.log(name);
  console.log(descriptor);
}

class User {
  @describe
  doSomething() {
    console.log("Hey, I did it!")
  }
}
new User().doSomething();
=> [Log] User
=> [Log] doSomething
=> [Log] {value: function, enumerable: false, configurable: true, writable: true}
=> [Log] Hey, I did it!
```

<p>The decorator function is invoked obviously before the decorated method's body. To apply decorator you need to preceed the name of the decorator with <code>@</code> (you can also pass some arguments there, but we will discuss it later). What about the arguments in the decorator functions? Basically, <code>target</code> is the object whose property is being decorated, <code>name</code> is, well, name of the property and <code>descriptor</code> is the property descriptor. The most interesting key in the descriptor is <code>value</code> which has the reference to the decorated function. That means we can modify the original function! Let's say we have some heavy computation going on in some function and we want to log how long it takes to do something. That basically means we want to have some time references before executing and after executing function so that we can subtract one from another. Well, as we have reference to the original function that's going to be pretty easy, we can just define new function and call the original one from there! Let's check this out:</p>

``` javascript
function measureable(target, name, descriptor) {
  let originalFunction = descriptor.value;

  descriptor.value = function() {
    let startTime = new Date();
    // do something heavy here
    let result = originalFunction.apply(target, arguments);
    let endTime = new Date();
    console.log((endTime - startTime) / 1000);
    return result;
  }
}
```

<p>And that's it! We extended the original function in a really elegant and unobtrusive manner. Notice that we still pass the arguments to the original function with JS <code>arguments</code>. If you are familiar with Python, you've probably been using the decorators in the similar way. The cool thing is that syntax (<code>@</code>) is even the same :). </p>

<p>Decorators can also be applied to classes. However, In that case we won't have name and descriptor, only the first argument - <code>target</code> - which is going to be the constructor of the class. So what are the use cases for decorating classes?</p>

<p>How about implementing mixins? An ideal interface would be something like <code>@mixin(myAwesomeFunctions)</code>. It happens that classes are just a sugar and adding instance functions is just defining properties onto the <code>prototype</code>. We have a reference to the constructor, so if we create e.g. <code>User</code> class, we can add new functions to its prototype the following way:</p>

``` javascript
User.prototype[functionName] = func;
```

<p>How about <code>mixin</code> decorator taking arguments? Not a problem, we just need to define function which returns another function that will be applied:</p>

``` javascript
function mixin(functions) {
  return function(target) {
    // assuming that `functions` is the JS objects with keys as functions names and values as functions that's going to copy them to target's (class constructor in this context) prototype
    Object.assign(target.prototype, functions);
  }
}
```

<p>And that's how we can use it:</p>

```
let mixinFunctions = {
  displayName: function() {
    console.log(`My name is ${this.name}`);
  }
}

@mixin(mixinFunctions)
class User {
  constructor(name) {
    this.name = name;
  }
}

new User('Lazar').displayName();
=> [Log] My name is Lazar
```

<p>Quite powerful. Let's see if we can do anything interesting in Ember with the decorators.</p>

<h2>Decorators and Ember</h2>

<p>To get started with decorators you just need to enable them in <code>ember-cli-build.js</code>:</p>

``` javascript
var EmberApp = require('ember-cli/lib/broccoli/ember-app');

module.exports = function(defaults) {
  var app = new EmberApp({
    babel: {
      optional: ['es7.decorators']
    },
  });

  return app.toTree();
};

```

<p>The awesome thing is that we can use decorators for computed properties syntax! It just requires installing <a href="https://github.com/rwjblue/ember-computed-decorators" target="_blank">ember-computed-decorators</a> addon. Let's see what kind of benefits this addon has to offer. Imagine we have some <code>User</code> model with <code>firstName</code> and <code>lastName</code> properties and we want to add <code>fullName</code> computed property:</p>

``` javascript
/* global Big */
import Ember from 'ember';
import DS from 'ember-data';

export default DS.Model.extend({
  firstName: DS.attr(),
  lastName: DS.attr(),

  fullname: function() {
    return `${this.get('firstName'} ${this.get('lastName'}`;
  }.property('firstName', 'lastName')
});
```
<p>But it just doesn't look right, <code>property</code> called on function may seem a bit magical. Well, we can use <code>Ember.computed</code>:</p>

``` javascript
fullname: Ember.computed('firstName', 'lastName', function() {
  return `${this.get('firstName'} ${this.get('lastName'}`;
}
```

<p>but that's pretty heavy. Also using <code>this.get</code> is far from ideal in both cases. How about defining normal function taking some arguments and applying a decorator?</p>

``` javascript
/* global Big */
import Ember from 'ember';
import DS from 'ember-data';
import computed from 'ember-computed-decorators';

export default DS.Model.extend({
  firstName: DS.attr(),
  lastName: DS.attr(),

  @computed('firstName', 'lastName')
  fullname(firstName, lastName) {
    return `${firstName'} ${lastName}`;
  }
});
```

<p>This looks perfect now. There are plenty of more computed decorators implemented in <code>ember-computed-decorators</code> addon, I encourage you to check all of them.</p>

<p>The only problem is that the new syntax doesn't play nicely with JSHint. The policy of JSHint is to support features that are Stage 2 of standardization process, which is not the case yet for decorators. The current workaround is to add some extra config to <code>.jshintrc</code>:</p>

``` javascript
"ignoreDelimiters": [
  { "start": "start-non-standard", "end": "end-non-standard" }
]
```

<p>and use computed decorators the following way:</p>

``` javascript
//start-non-standard
import computed from 'ember-computed-decorators';
//end-non-standard

//start-non-standard
@computed('firstName', 'lastName')
//end-non-standard
fullname(firstName, lastName) {
  return `${firstName'} ${lastName}`;
}
```

<h2>Wrapping up</h2>

<p>Decorators are an excellent addition to JavaScript world. It can greatly simplify code in JS applications, especially very common things like Ember computed properties. Thanks to Babel it's quite easy to start using them even now.</p>

<p>Next time we are going to explore <code>async / await</code> and how they improve JavaScript experience.</p>
