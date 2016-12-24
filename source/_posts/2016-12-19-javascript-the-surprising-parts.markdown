---
layout: post
title: "JavaScript: The Surprising Parts"
date: 2016-12-19 00:28
comments: true
categories: [JavaScript, ECMAScript]
---

<p>Do you think you know all the surprising parts of <strong>JavaScript</strong>? Some of these "features" may look as if the language was broken, but it's not necessarily the case. Things like <strong>variables hoisting</strong>, variables scope, behaviour of <strong>this</strong> are quite intentional and besides just being different from most of other programming languages, there is nothing particularly wrong with them. However, there are still some things that are quite surprising about <strong>JavaScript</strong>. Let's take a look at some of them.</p>

<h2>Surprise #1 - <code>parseInt</code> function</h2>

<p>Imagine you have some numbers as strings and you want to convert them to integers. You could probably use <code>Number</code> function to do that, but let's assume you are used to <code>parseInt</code> function. So let's do some conversions: </p>

```
["1"].map(parseInt);
// [1]

["1", 2, "3", 4].map(parseInt);
// => [1, NaN, NaN, NaN] // WUT ?!

["1", 2, "3", 4].map(parseFloat);
// => [1, 2, 3, 4] // WUT...
```

<p>Well, I guess it's not something that would expect here initially. How could possibly <code>parseFloat</code> work fine here and <code>parseInt</code> not? Obviously <strong>JavaScript</strong> is broken, right?</p>

<p>Not really. This is actually the expected behaviour. The difference between <code>parseFloat</code> and <code>parseInt</code> is that <code>parseFloat</code> takes only one argument (<code>string</code>), but <code>parseInt</code>takes two arguments - <code>string</code> and... <code>radix</code>. To verify it, let's rewrite the mapping using an anonymous function:</p>

``` js
["1", 2, "3", 4].map((number) => parseInt(number));
// => [1, 2, 3, 4]
```

<p>When you pass simply <code>parseInt</code> as an argument to <code>map</code>, the second argument (which is current index) is going to be passed as <code>radix</code> to <code>parseInt</code>, which explains why it returns <code>NaN</code>. The equivalent of just passing <code>parseInt</code> looks like this:</p>

``` js
["1", 2, "3", 4].map((number, index, array) => parseInt(number, index, array));
```

<p>As "odd" as it may look like, this is a perfectly valid behaviour and there is nothing wrong with <code>JavaScript</code> ;).</p>

<h2>Surprise #2 - sorting</h2>

<p>Now that we've  learned how to parse integers in <strong>JavaScript</strong> like a boss, let's do some sorting:</p>

``` js
[1, 20, 2, 100].sort();
// => [1, 100, 2, 20] // WUT...
```

<p>Again, seems odd. That behaviour is something intended - after consulting with <a href="https://developer.mozilla.org/en/docs/Web/JavaScript/Reference/Global_Objects/Array/sort" target="_blank">docs</a> we can learn that <code>sort</code> converts all elements into strings and compares them in Unicode code point order. I think this might be a big surprise for eveyrone performing sorting and seeing the result, but this behaviour is clearly documented. Due to the necessity of maintaing backwards compatibility, I wouldn't except this behavior to change, so it' worth keeping it in mind.</p>

<p>To perform sorting on integers you need to provide a compare function:</p>

``` js
[1, 20, 2, 100].sort((a, b) => a - b);
// => [1, 2, 20, 100]
```

<h2>Surprise #3 - <code>==</code> vs. <code>===</code></h2>

<p>You've probably heard that you should never use double equals (loose equality) and just stick to triple equals (strict equaility). But following some rules without understanding the reasons behing them is never a good solution to a problem. Let's try to understand how these operators work.</p>

<p>Loose equality (<strong>==</strong>) compares two values after converting them to common type. After conversions (both values can actually be converted) the comparison is performed by strict equality (<strong>===</strong>). So what is a common type in this case?</p>

<p>The easiest way to get the idea what happens when using <code>==</code> would be checking the table for conversion rules <a href="https://developer.mozilla.org/en-US/docs/Web/JavaScript/Equality_comparisons_and_sameness#Loose_equality_using" target="_blank">here</a> as it's not really something obvious that could be quickly explained.</p>

<p>So basically this table says that the following expressions will be truthy:</p>

``` js
1 == "2";
"2" == 1;
new String("string") == "string";
1 == { valueOf: function() { return 1; } }; // lulz, it's not a joke ;)
1 == true;
false == 0;
"1,2" == [1,2] // try it yourself if you don't believe me ;)
"Fri Jan 01 2016 00:00:00 GMT+0100 (CET)" == new Date(2016, 0, 1)
"1,2" == [1,2] // because why not?
```

<p>Seems quite "exotic", right? But is <strong>loose equality</strong> actually useful?</p>

<p>Yes, it is. I can imagine 3 scenarios where it comes in handy.</p>

<p>The first scenario would be when comparing integers from inputs and you don't really case about strict equality and types:</p>

``` js
if ($('.my-awesome-input').val() == 100) {
  // do something here
}
```

<p>In such case it may turn out that we don't really care if we compare strings or integers, either <code>"100"</code> and <code>100</code> are fine and we don't need to perform any explicit conversions.</p>

<p>The second use case would be treating both <code>undefined</code> and <code>null</code> as the same thing meaning lack of some value. With strict equality we would need to check for both values:</p>

``` js
x = getSomeValue();

if (x !== undefined && x !== null) {
  // some logic
}
```

<p>Doesn't look that nice. We could clean it up with loose equiality and simple check if something is not null-ish:</p>

``` js
x = getSomeValue();

if (x != null) {
  // some logic
}
```

<p>The last use case would be comparing <strong>primitives</strong> and <strong>objects</strong>. It's especially useful when dealing with both primitive strings (<code>"simple string"</code>) and strings as objects (<code>new String("string as object")</code>:</p>

``` js
x = getSomeValue();

if (x != "some special value") {
  // some logic
}
```

<p>With strict equiality we would probably need to explicitly convert to string using <code>toString()</code>, which is not that bad, but loose equiality looks arguably cleaner.</p>

<p>Surprise #4 - equiality gotcha #1: <code>NaN</code></p>

<p>Do you know how to identify <strong>NaN</strong> in <strong>JavaScript</strong>. Sounds like a silly question, right? Well, not really, both of the following expressions are falsey:</p>

``` js
NaN == NaN; // => false
NaN === NaN; // => false
```

<p>I'm really sure what was the original reason behinh such "feature", nevertheless, there is still a way to check for <code>NaN</code>: it is the only value in JS that is not equial to itself:</p>

``` js
NaN != NaN; // => true
NaN !== NaN; // => true
```

<p>So you could either take advantage of this behaviour or use <code>isNaN</code> function:</p>

``` js
isNaN(NaN); // => true
```

<p>There is one more possibility to test for <code>NaN</code>: <code>Object.is</code> function, which acts like strict equality, but with few exceptions. One of those is comparing <code>NaN</code>:</p>

``` js
NaN === NaN // => false
Object.is(NaN, NaN); // => true
```

<h2>Surprise #5 - equiality gotcha #2: comparing objects</h2>

<p>There is one more gotcha besides <code>NaN</code> when it comes to checking for equiality: comparing objects. If you think you can easily compare arrays with the same elements, objects with the same keys and values then you might be quite surprised:</p>

``` js
[1, 2, 3] == [1, 2, 3]; // false
[1, 2, 3] === [1, 2, 3]; // false
{ comparing: "objects" } == { comparing: "objects" }; // false
{ comparing: "objects" } === { comparing: "objects" }; // false
```

<p>The reasong behind is that quite simple though: <strong>strict equality</strong> doesn't compare the values, but identities instead. And two different objects are, well, different, unless they refer t exactly the same thing.</p>

<p>How about <strong>loose equality</strong>?. If the types are the same then it's the same thing as using <strong>strict equiality</strong>. It doesn't work with <code>Object.is</code> either. The only option for objects is to compare each key and associated value with the ones from other object.</p>

<p>Surprise #6 - <code>instanceof</code> and <code>typeof</code></p>

<p>There seems to be a lot of confusion regarding those two and how use them in in different use cases. Basically, <code>typeof</code> should be used for getting the basic <strong>JavaScript</strong> type of given <strong>expression</strong> (i.e. undefined, object, boolean, string, number, string, function or symbol) and <strong>instanceof</strong> should be used for checking if prototype of given constructor is present in expression's prototype chain. Even if they may seem to be similar, there should be used in very different situations, check the following examples:</p>

``` js
typeof "basic string"  // => "string", it's a primitive so looks good so far
typeof new String("basic string" ) // => "object", because it's no longer a primitive!

"basic string" instanceof String // => false, because "basic string" is a primitive
1 instanceof Number // => false, some reason, 1 is a primitive

[] instanceof Array // => true
[] instanceof Object // => true, array is not a primitive

typeof [] => "object", there is no array primitive, it's still an object
```

<p>Unforunately, it's not that easy in all cases. There are 2 exceptions regarding usage of <code>typeof</code> that are quite surprising.</p>

<p>There is <strong>undefined</strong> type which would be returned for <code>undefined</code> expression, but what about <code>null</code>? Turns out that its type is <strong>object</strong>! There were some attempts to remove this confusion - like this proposal for introducing <a href="http://wiki.ecmascript.org/doku.php?id=harmony:typeof_null" target="_blank">null type</a> - but they were eventually rejected.</p>

<p>And another suprise: <strong>NaN</strong>. What is the type of something that is not a number? Well, it's <strong>number</strong> of course ;). As funny as it sounds, it is in accordance with <a href="https://en.wikipedia.org/wiki/IEEE_floating_point" target="_blank">IEEE Standard for Floating-Point Arithmetic</a> and the concept of <code>NaN</code> is kind of number-ish, so this behaviour is justified.</p>

<h2>Surprise #7 - <code>Number.toFixed</code> returning strings</h2>

<p>Imagine you want to round some number in <strong>JavaScript</strong> and do some math with it. Apparently <code>Math.round</code> is capable only of rounding to the nearest integer, so we need to find some better solution. There is <code>Number.toFixed</code> function which seems to do the job. Let's try it out:</p>

``` js
123.789.toFixed(1) + 2 // => 123.82, huh?
```

<p>Is math broken in JS? Not really. It's just the fact that <code>Number.toFixed</code> returns string, no a numeric type! And its intention is not really to perform rounding for math operations, it's only for formatting! Too bad there is no built-in function to do such simple operation, but if you expect a numeric type, just handle it with <code>+</code> <strong>unary prefix operator</strong>, which won't be used as an <strong>addition operator</strong>, but will perform <strong>conversion to number</strong>:</p>

``` js
const number = +123.789.toFixed(1);
number // => 123.8
```

<h2>Surprise #8 - Plus (<code>+</code>) operator and not surprising</h2>

<blockquote>"Adding stuff in JavaScript is simple, obvious and not surprising" - No one ever</blockquote>

<p>Have you ever watched <a href="https://www.destroyallsoftware.com/talks/wat" target="_blank">Wat</a> by Gary Bernhardt? If not, I highly encourage you to do it now, it's absolutely hillarious and concerns a lot of "odd" parts of JavaScript.</p>

<p>Let's try to explain most of these odd results when using <code>+</code> operator. Beware: once you finishing reading it, you will actually not find most of these results that surpsrising, it will be just "different". I'm not sure yet if it's good or bad :).</p>

<p>Take a look at the following examples:</p>

``` js
[] + [] // => ""
[] + {} // => "[object Object]"
{} + [] // => 0 // wut...
{} + {} // => "[object Object][object Object]"
[] + 1 // => "1" // it's string!
[1] + 2 => // => "12"
[1, 2] + 2 // => "1,22"
3 + true // => 4
new Date(2016, 0 , 1) + 123 // => "Fri Jan 01 2016 00:00:00 GMT+0100 (CET)123"
({ toString: function() { return "trolololo"; } }) + new Date(2016, 0 , 1) // => "trolololoFri Jan 01 2016 00:00:00 GMT+0100 (CET)"
1 + { valueOf: function() { return 10; }, toString: function() { return 5; } } // => 11
1 + { toString: function() { return 10; } } // => 11
1 + undefined // => NaN
1 + null // => 1
```

{% img /images/js_results_not_so_wut.jpg 'js_results_not_so_wut' 'js_results_not_so_wut' %}

<p>All of these results may seem to be somehow exotic, but only of them is, maybe two at most are exceptional. The basic thing before figuring out the result of those expressions is understanding how happens under the hood. In <strong>JavaScript</strong> you can only add numbers and strings, all other types must be converted to one of those. The <code>+</code> operator basically converts each value to primitives (which are: undefined, null, booleans, numbers and strings), strings and values. The conversion to primitives is handled by internal operation called <code>ToPrimitive</code> which has the following signature: <code>ToPrimitive(input, PreferredType)</code>. The <code>PreferredType</code> can be either <strong>number</strong> or <strong>string</strong>. The algorithm of this operation is quite simple, here are the steps is <strong>string</strong> the preferred type:</p>

<ul>
  <li>return <code>input</code> if it's already a primitive</li>
  <li>If it's not a primitive, call <code>toString()</code> method on <code>input</code> and return the result if it's a primitive value</li>
  <li>If it's not a primitive, call <code>valueOf()</code> method on <code>input</code> and return the result if it's a primitive value</li>
  <li>If it's not a primitive, throw <code>TypeError</code></li>
</ul>

<p>For <code>number</code> as preferred type th eonly difference is the sequence of steps 2 and 3: <code>valueOf</code> method will be called first and if it doesn't return a primitive then <code>toString</code> method wil be called. In most cases <code>number</code> will be the preferred type, <code>string</code> will be used only when dealing with instance of <code>Date</code>.</p>

<p>Now that we know what happens under the hood, let's explain the results feom the examples above.</p>

<p>The result of calling <code>valueOf</code> method on <strong>objects</strong> (<code>{}</code>) and <strong>arrays</strong> (which technically are also objects) is simple the object itself, so it's not a primitive. However, for objects <code>toString</code> method will return <code>"[object Object]"</code> and for ararys it will return empty string - <code>""</code>. Now we have primitives that can  added. From this point we can predict the results of operation like <code>{} + {}</code>, <code>[] + {}</code> or even <code>1 + { valueOf: function() { return 10; }, toString: function() { return 5; } }</code> and <code>1 + { toString: function() { return 10; } }</code> (remember the steps for converting objects to primitives?). If you remember that <string>string</string> is the preferred type for operations involving dates, the result of <code>({ toString: function() { return "trolololo"; } }) + new Date(2016, 0 , 1)</code> is not really surprising. But how is it possible that <code>{} + []</code> returns <code>0</code>, not <code>"[object Object]"</code>?</p>

<p>Most likely <code>{}</code> in the beginning is interpreted as an empty block and it's ignored. In fact that expression is interpreted as <code>+[]</code> which is very different from addition! As I've already mentioned before, it's the <strong>unary prefix operator</strong> which performs conversions to numbers. For arrays, the result of such conversion is simply 0.</p>

<p>And why does <code>1 + undefined</code> return <code>NaN</code>? We can add only numbers and strings, <code>undefined</code> is neither of them, so it must be converted to a number in this case. The result of such operation is simply <code>NaN</code> and <code>1 + NaN</code> is still <code>NaN</code>.</p>


<h2>Surprise #9 - No integers and floats - just numbers</h2>

<p>In most programming languages there are different type of numbers, like integers and floats. What is again surprising about <strong>JavaScript</strong> is that all numbers are simply double precision floating point numbers! This has a huge impact of anything related to math, even for such things like precision. Take a look at the following example:</p>

```
9999999999999999 === 10000000000000000 // => true
```

<p>This is definitely not something that would be expected here. If you are planning to do any math in <strong>JavaScript</strong>, make sure you won't run into any issues caused by the implementation details of the numbers.</p>


<h2>Wrapping up</h2>

<p><strong>JavaScript</strong> may sometimes seem like it's "broken" somehow, especially comparing to other programming languages. However, many of these features are quite <strong>intentional</strong> and others are consequences of some decisions. There are still few things that seem to be really odd, but after digging eeper they start to make sense, so to avoid unfortunate surprises it's definitely worth learning about those odd parts of <strong>JavaScript</strong>.</p>

