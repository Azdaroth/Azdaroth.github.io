---
layout: post
title: "How To Handle Non-CRUD Logic In Your API"
date: 2016-01-17 12:52
comments: true
categories: [API, Rails, Ruby, Architecture]
---

<p>If you happen to develop <strong>API</strong> for non-trivial app with complex business logic beyond <strong>CRUD</strong> directly mapped to the database tables (i.e. typical Active Record pattern) you were probably wondering many times how to handle these cases and what's the best way to do it. There are quite a few solutions to this problem: you could add another endpoint for handling given use case, add <strong>non-RESTful</strong> action to already existing endpoint or you can add a magic param to the payload that would force non-standard scenario in the <strong>API</strong>. Let's take a closer look at the these solutions and discuss some advantages and disadvantages of each of them.</p>

<h2>Our use case: creating drafts and articles</h2>

<p>Let's start with some feature that will be simple enough for the blog post, but still interesting enough that we will have several ways to solve some the problem. Creating drafts and published articles (both referring to some <code>Article</code> model) sounds good enough: for <code>drafts</code> and <code>published</code> articles we are going to have different <strong>business validations</strong> and we will also need to have a possibility to transit from one state to another. Let's assume that the drafts don't have any required attributes at all and published articles require presence of: <code>title</code>, <code>content</code> and <code>author_id</code>. Besides creating both type of articles, we will also need to update both type of articles while maintaining current state and have a possibility to transit from drafts to published articles. To add some extra logic articles will also have <code>published_at</code> attribute, which is not directly settable via API, but will be automatically set server-side when making a transition from <code>draft</code> to <code>published</code> state or directly creating published article.</p>

<h2>Magic param</h2>

<p>Let's start with the simplest strategy that I call <code>magic param</code> or <code>virtual param</code>. Basically, to force a different scenario we simply send some extra param, let's name it <code>published</code>. In such case we will only have a single endpoint: <code>Articles</code> with <code>create</code> and <code>update</code> actions and depending on the value of <code>published</code> param we will either run a logic for creating / updating drafts or published articles.</p>

<p>Making transition from <code>draft</code> to <code>published</code> state is going to be the same, we simply need to send <code>published</code> param with <code>true</code> value and make sure other requirements are met (title's, content's and author's presence).</p>

<p>Obviously, this approach looks pretty simple from the client perspective, everything is driven by sending a magic param and this solution is pretty easy to integrate with some client-side data layers like <strong>Ember Data</strong>. But personally I don't find this solution really clean server-side. Having one interface (endpoint) for multiple purposes (where the logic is conditionally driven by a specific value of some param) adds some extra complexity on the design. Expecially in this case where the client knows exactly that we want to handle either drafts or published articles. For some features it may be good to hide some internal details server-side, but here it's not the case. So the solution to this problem might be...</p>

<h2>Adding extra endpoint</h2>

<p>With extra endpoint we clearly separate interfaces between both types of articles. Clearly, the logic on server is now much less complex. If we want to create a draft, we just use <code>Drafts</code> endpoint. If we need to update a published article, we simply use (surprise, surprise) <code>Articles</code> endpoint.</p>

<p>As a side-effect of such design decision we can actually do some cool things, e.g. in <code>index</code> actions we could return only one type of article, either drafts or published ones, depending on the endpoint.</p>

<p>The disadvantage of this approach is that it may not be that easy to handle it client-side with frameworks' data layers, which in most cases are kind of equivalents of <strong>Active Record</strong> pattern, but in API world.</p>

<p>Adding extra endpoint solved one of the issues: having the same interface for different kind of logic. But we still need to have a possibility to make a transition from <code>draft</code> to <code>published</code> article. One way would be to simply use <code>update</code> action from Published Articles endpoint, but this would mean using endpoint for actually different resource, which looks really weird and not proper, especially after separating Articles to two different endpoints. We could still handle it with magic <code>published</code> param, but this time only in Drafts endpoint. Or we could consider doing yet another thing, which is...</p>

<h2>Adding extra action</h2>

<p>This way doesn't sound really RESTful, but I find it pretty elegant. To handle transition from <code>draft</code> to <code>published</code> we can simply add <code>publish</code> action to Drafts endpoint and let the API handle all the necessary logic.</p>

<p>What I like about combining different endpoints with extra actions is that everything is explicitly defined: every part of API has its' own interface and there's no magic and no implicit assumptions. It's also more flexible and removes some complexity server-side. The disadvantage of this approach is that it actually moves complexity to the client - having extra actions, again, may not be that easy to handle neatly by data layers (if you happen to use Ember and Ember Data, you can play with <code>adapters</code> and <code>buildURL</code> function to make it smooth).</p>

<h2>Wrapping up</h2>

<p>There are couple of different ways of handling complex logic in non typical CRUD scenarios in your API: using magic param, adding extra endpoints, adding extra method and each of them has its' own advantages and disadvatages on both server-side and client-side.</p>
