---
layout: post
title: "Ember Tips: Computed Properties And Arrow Functions? Not A Good Idea"
date: 2016-12-11 22:00
comments: true
categories: [Ember, JavaScript, ES6, Quick Tips]
---

<p><strong>Arrow function expressions</strong> was definitely a great addition in ES6 and thanks to tools like <a href="https://babeljs.io" target="_blank">babel</a> the new syntax has been quite widely adopted. Besides more concise syntax, an interesting thing about <strong>arrow function expressions</strong> is that they preserve the context, i.e. they don't define their own <code>this</code>, which was sometimes annoying and resulted in assigning <code>that</code> or <code>self</code> variables to keep the outer context that could be referred inside functions. As great as it sounds, <code>arrow function expressions</code> cannot be used in all cases. One example would be <code>Ember computed properties</code>.</p>

<!--more-->

<h2>Arrow Function Expressions - A Quick Introduction</h2>

<p>Let's start with a quick introduction to arrow functions. Before ES6, anytime we were using <code>function expressions</code> and wanted to refer <code>this</code> from outer context, we had to do some workarounds which are (arguably) a bit unnatural, especially comparing to other major programming languages.</p>

<p>Let's do some pseudo-object-oriented programming with JavaScript (ES5) to illustrate a possible issue with <strong>function expressions</strong>:</p>

``` js
function Order() {
  this.id = Math.floor((Math.random() * 10000000) + 1); // don't do it in a production code ;)
  this.items = [];
}

Order.prototype.addItem = function(item) {
  this.items.push(item);
}

Order.prototype.logItems = function() {
  this.items.forEach(function(item) {
    console.log("item description: " + item.description + " for order with id: " + this.id);
  });
}

var order = new Order();
order.addItem({ description: 'Glimmer 2 rockzzz' });
order.logItems();  // whooops
```

<p>We have a simple class-like functionality using <strong>constructor function</strong> and <strong>prototypes</code> to implement <code>Order</code> with some questionable (;)) way of assigning id and some <code>items</code>. We can add more items with <code>Order.prototype.addItem</code> function and we can log them with <code>Order.prototype.logItems</code> function.</p>

<p>But there's a problem: <code>logItems</code> function doesn't log <code>id</code>, but logs <code>undefined</code> instead. Why is that?</p>

<p><strong>Function expressions</strong> create their own context and define own <code>this</code>, so it no longer refers to the outer context, which is the <code>order</code> instance. There are several ways to solve this problem.</p>

<p>The most obvious is to assign outer <code>this</code> to some other variable, like <code>that</code> or <code>self</code>:</p>

``` js
Order.prototype.logItems = function() {
  var self = this;
  this.items.forEach(function(item) {
    console.log("item description: " + item.description + " for order with id: " + self.id);
  });
}
```

<p>You can also pass outer <code>this</code> as a second argument to <code>forEach</code> function:</p>

``` js
Order.prototype.logItems = function() {
  this.items.forEach(function(item) {
    console.log("item description: " + item.description + " for order with id: " + this.id);
  }, this);
}
```

<p>You can even explicitly <code>bind</code> outer <code>this</code> to callback argument inside <code>forEach</code> function:</p>

``` js
Order.prototype.logItems = function() {
  this.items.forEach(function(item) {
    console.log("item description: " + item.description + " for order with id: " + this.id);
  }.bind(this));
}
```

<p>All these solutions work, but aren't really that clean. Fortunately, since ES6, we can use <code>arrow function expressions</code> which preserve outer context and don't define own <code>this</code>. After little refactoring <code>Order.prototype.logItems</code> could look like this:</p>

``` js
Order.prototype.logItems = function() {
  this.items.forEach((item) => {
    console.log("item description: " + item.description + " for order with id: " + this.id);
  });
}
```

<p>Much Better!</p>

<p>As great as it looks like, it may not be a good idea to apply <code>arrow function expressions</code> everywhere, especially for <strong>Ember computed properties</strong>.</p>

<h2>Ember Computed Properties And Arrow Functions? - Not A Good Idea</h2>

<p>Recently I was doing some refactoring in one Ember app. The syntax in one of the models was a bit mixed and there were some <strong>function expressions</strong> and <strong>arrow function expressions</strong> which looked a bit like this:</p>

``` js app/models/user.js
import Ember from "ember";
import Model from 'ember-data/model';

export default Model.extend({
  fullname: Ember.computed('firstname', 'lastname', function() {
    return `${this.get('firstName')} ${this.get('lastName')}`;
  }),

  doThis: function() {
    // some logic goes here
  },

  doThat: function() {
    // even more logic
  },

  doYetAnotherThing(args) {
    // more logic
  }
});
```

<p>So I decided ES6-ify entire syntax here and ended up with the following code:</p>

``` js app/models/user.js
import Ember from "ember";
import Model from 'ember-data/model';

export default Model.extend({
  fullname: Ember.computed('firstname', 'lastname', () => {
    return `${this.get('firstName')} ${this.get('lastName')}`;
  }),

  doThis() {
    // some logic goes here
  },

  doThat() {
    // even more logic
  },

  doYetAnotherThing(args) {
    // more logic
  }
});
```

<p>And how did this refactoring end up? Well, instead of a proper <code>fullName</code> I was getting <code>undefined undefined</code>! That was surprising, but then I looked at the changes and saw that I'm using <code>arrow function expressions</code> in computed properties and referring there to <code>this</code>, which won't obviously work. So what are the options for computed properties?</p>

<p><code>The first one would be to simply use good ol' <code>function expressions</code>:</p>

``` js app/models/user.js
import Ember from "ember";
import Model from 'ember-data/model';

export default Model.extend({
  fullname: Ember.computed('firstname', 'lastname', function () {
    return `${this.get('firstName')} ${this.get('lastName')}`;
  })
});
```

<p>But if you don't really like it, you may define <strong>explicit getter</strong>:</p>

``` js app/models/user.js
import Ember from "ember";
import Model from 'ember-data/model';

export default Model.extend({
  fullname: Ember.computed('firstname', 'lastname', {
    get() {
      return `${this.get('firstName')} ${this.get('lastName')}`;
    }
  })
});
```

<p>And the last option, my preferred one: unleashing the power of ES7 decorators, which I described <a href="https://karolgalanciak.com/blog/2015/12/02/ember-and-es7-decorators/" target="_blank">here</a> and using <a href="https://github.com/rwjblue/ember-computed-decorators" target="_blank">ember-computed-decorators</a> addon. That way we could define <code>fullName</code> computed property in the following way:</p>

``` js app/models/user.js
import Ember from "ember";
import Model from 'ember-data/model';
import computed from 'ember-computed-decorators';

export default Model.extend({
  @computed('firstName', 'lastName')
  fullname(firstName, lastName)
    return `${firstName} ${lastName}`;
  })
});
```

<p>which looks just beautiful ;).</p>

<h2>Wrapping Up</h2>

<p>Even though <strong>arrow function expressions</strong> are very convenient to use, they can't be used interchangeably with good ol' <strong>function expressions</strong>. Sometimes you don't want <code>this</code> inside a function to preserve outer context, which is exactly the case with Ember <code>computed properties</code>.</p>
