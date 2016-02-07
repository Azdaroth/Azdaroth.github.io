---
layout: post
title: "Implementing non-RESTful actions with Ember Data"
date: 2016-02-07 10:45
comments: true
categories: [Ember, Ember Data, API]
---

<p>In my <a target="_blank" href="http://karolgalanciak.com/blog/2016/01/24/how-to-handle-non-crud-logic-in-your-api/">recent post</a> I mentioned some strategies of handling non-strictly <strong>CRUD</strong> / <strong>RESTful</strong> actions in <strong>API</strong>. One of them was adding extra actions beyond creating, updating and deleting resources. As it's not a standard solution and some data layers on client side (like <strong>Ember Data</strong>) don't handle it out-of-box, I was asked by some developers what's the best way to handle such actions. So let's see how can we hack into <strong>Ember Data</strong> and make it smooth.</p>

<!--more-->

<h2>Our use case: publishing articles</h2>

<p>Let's reuse the example from the previous blog post - the articles and publishing process. What we are going to do is to add <code>publish</code> function to our <code>Article</code> model, which simply sends <code>PATCH</code> request to <strong>API</strong> endpoint with <code>/api/articles/:id/publish</code> URL.</p>

<p>First thought about implementation could be using <code>Ember.$.ajax</code> call with manually passing URL and all the data. But that's not really a great solution. For simple cases it may work, but what about sending some custom headers, using namespaces and other options? For these reasons we should encapsulate all the logic within <strong>adapter</strong> - the layer that's responsible for communication with the API. So let's add <code>publish</code> function to our article adapter for executing the request and use this function from <code>article</code> model.</p>

``` javascript
// app/adapters/article.js

import ApplicationAdapter from './application';

export default ApplicationAdapter.extend({
  publish(id) {
    return this.ajax(this.urlForPublishAction(id), 'PUT');
  },

  urlForPublishAction(id) {
    return `${this.buildURL('article', id)}/publish`;
  }
});
```

<p>There are some interesting things going on here: the first one is that we use <code>ajax</code> function defined in adapter, which is also utilized when peforming all other requests in <strong>Ember Data</strong>. It takes care of setting up options like headers, proper success and error handling etc., so we should always use this function instead of simple <code>Ember.$.ajax</code>. Another thing is <code>buildURL</code> function, which builds, well, URL for given resource represented by model name (with given id if present) considering adapter options like <code>host</code> or <code>namespace</code>. By using these functions we ensure the consistency between all <strong>API</strong> calls.</p>

<p>To make it work we just need to find proper adapter for <code>article</code> model and call <code>publish</code> function on this adapter from the model:</p>

``` javascript
// app/models/article.js

import Ember from 'ember';
import DS from 'ember-data';

const { getOwner } = Ember;

export default DS.Model.extend({
  publish() {
    let modelName = this.constructor.modelName;
    let adapter = getOwner(this).lookup(`adapter:${modelName}`);
    // if you use Ember version prior to 2.3 you'll probably need to use container:
    // let adapter = this.container.lookup(`adapter:${modelName}`);
    return adapter.publish(this.get('id'));
  }
});
```

<p>To avoid hardcoding model name we take it from the <code>constructor</code>, then use it as a name of adapter we want to fetch from <code>owner</code> (or <code>container</code> in Ember versions prior to 2.3) and finally call the proper method on adapter with id as argument.</p>

<p>What if we needed to pass the serialized attributes as well? The third argument of <code>ajax</code> function in adapter is a hash, so we would need to pass the serialized article as <code>data</code> param there. Here's a quick example, starting from the model:</p>

``` javascript
// app/models/article.js

import Ember from 'ember';
import DS from 'ember-data';

const { getOwner } = Ember;

export default DS.Model.extend({
  publish() {
    let modelName = this.constructor.modelName;
    let adapter = getOwner(this).lookup(`adapter:${modelName}`);
    return adapter.publish(this.get('id'), this.serialize());
  }
});
```

<p>and here's the adapter:</p>

``` javascript
// app/adapters/article.js

import ApplicationAdapter from './application';

export default ApplicationAdapter.extend({
  publish(id, serializedData) {
    return this.ajax(this.urlForPublishAction(id), 'PUT', { data: serializedData });
  },

  urlForPublishAction(id) {
    return `${this.buildURL('article', id)}/publish`;
  }
});
```

<p>And that's it!</p>


<h2>Wrapping up</h2>

<p>Non-RESTful actions are not supported out of the box by <strong>Ember Data</strong>, but they are not that hard to implement when using adapters.</p>
