---
layout: post
title: "JavaScript Tips: Redefining userAgent property"
date: 2017-02-26 23:00
comments: true
categories: [JavaScript, Quick Tips]
---

Imagine a use case where you are trying to check if a user accessed your app from a **mobile** device or not. Most likely you will need to use <a href="https://developer.mozilla.org/en-US/docs/Web/API/NavigatorID/userAgent" target="_blank">navigator.userAgent</a>  property and craft some smart regular expression to test for the presence of particular expression, like `(/Mobi/.test(navigator.userAgent)` which seems to be the <a href="https://developer.mozilla.org/en-US/docs/Web/HTTP/Browser_detection_using_the_user_agent" target="_blank">recommended way</a> to do it. Ok, so we're almost done with our feature, we just need to add some tests to make sure it works as expected. But there's a problem - you can't redefine `userAgent` property with just using a setter! Fortunately, there is a way to solve this problem.

<!--more-->

## Anatomy of the problem

<div class="img-center-wrapper">
  {% img /images/useragent/one_does_not_simply_override_useragent.jpg 'one does not simply override user agent' %}
</div>

Let's check what happens when we try to override `navigator.userAgent` property with a setter in a browser.

``` javascript
> navigator.userAgent
< "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_12_2) AppleWebKit/602.3.12 (KHTML, like Gecko) Version/10.0.2 Safari/602.3.12"
> navigator.userAgent = "Mobile"
< "Mobile"
> navigator.userAgent
< "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_12_2) AppleWebKit/602.3.12 (KHTML, like Gecko) Version/10.0.2 Safari/602.3.12"
```

Well, that's not exactly what we wanted to be returned. But we need to override this value somehow to test both behaviours - when the device is a mobile one and not a mobile one. Fortunately, **JavaScript** is quite powerful at this point and it's possibly to redefine such property using <a href="https://developer.mozilla.org/en/docs/Web/JavaScript/Reference/Global_Objects/Object/defineProperty" target="_blank">`Object.defineProperty`</a>.


## Object.defineProperty to the Rescue

`Object.defineProperty` allows to define a new property or redefine an existing one on a  given object. The syntax is following:

``` javascript
Object.defineProperty(obj, prop, descriptor)
```

`descriptor` argument is a particularly interesting one - it allows to define a `value` of the property, a getter, a setter, whether the property should be `enumerable` (if it's going to be included when iterating over the properties), if it's `writable` (if the value can be changed with an assignment operator) and `configurable` (if the property can be changed and deleted from the object's properties).

Looks like `value` is exactly what we need. Let's try it then:

``` javascript
> Object.defineProperty(window.navigator, 'userAgent', {
  value: 'Mobile'
});

> navigator.userAgent;
< "Mobile"
```

Looks good so far. What if we wanted to override this property again?

``` javascript
> navigator.userAgent = 'Desktop';

> navigator.userAgent;
< "Mobile"; // whooops
```

Hmm, doesn't work, maybe let's try to redefine this propert again then?

``` javascript
> Object.defineProperty(window.navigator, 'userAgent', {
  value: 'Mobile'
});

< TypeError: Attempting to change value of a readonly property.
```

Apparently it's not that great as we thought it would be. However, that's not a problem! We just need to make this property either `configurable` or `writable`! Let's check both scenarios:

``` javascript
> Object.defineProperty(window.navigator, 'userAgent', {
  value: 'Mobile',
  configurable: true
});

> navigator.userAgent;
< "Mobile"

> Object.defineProperty(window.navigator, 'userAgent', {
  value: 'Desktop',
  configurable: true
});

> navigator.userAgent;
< "Desktop"

> navigator.userAgent = "Mobile";

> navigator.userAgent;
< "Desktop" // setter won't work here!
```

``` javascript
> Object.defineProperty(window.navigator, 'userAgent', {
  value: 'Mobile',
  writable: true
});

> navigator.userAgent;
< "Mobile"

> navigator.userAgent = 'Desktop';

> navigator.userAgent;
< "Desktop"

> Object.defineProperty(window.navigator, 'userAgent', {
  value: 'Mobile',
  writable: true
});

> navigator.userAgent;
< "Mobile"
```

Both of the ways work just fine, however, `writable` is a bit more flexible as it allows to change the `value` returned by a given property by redefining this property or using a simple setter. In case of `configurable` you can only redefine a property.


## Wrapping Up

Maybe **JavaScript** has some  TU WSTAW LINKS DO WPISU O DZIWACTWACH <a href="" target="_blank">odd parts</a>, nevertheless, it's a quite powerful language. Changing the value of read-only properties is probably not a something do you will do often, but if you really need to do it, `Object.defineProperty` will be your friend.
