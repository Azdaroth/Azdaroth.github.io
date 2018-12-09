---
layout: post
title: "Inheritance and define_method - how to make them work together"
date: 2018-12-16 20:00
comments: true
categories: ["Ruby", "metaprogramming", "quick tips"]
---

Imagine that you are implementing some form object because you are fed up with treating ActiveRecord models as such, and you need some extra flexibility. You start with a straightforward implementation for a base class of a form object where you can just whitelist attributes. That could look like this:

``` rb
class FormObject
  def self.attributes_registry
    @attributes_registry ||= []
  end

  def self.attribute(attribute_name)
    attributes_registry << attribute_name

    define_method(attribute_name) do
      instance_variable_get("@#{attribute_name}")
    end

    define_method("#{attribute_name}=") do |value|
      instance_variable_set("@#{attribute_name}", value)
    end
  end
end
```

Since the base class is ready, you can create a first form object that would inherit from this class:

``` rb
class MyForm < FormObject
  attribute :some_attribute
end
```

Initially, it does the job, but then it turns out that you might need a default value if `some_attribute` turns out to be nil. So you try something like that:

``` rb
class MyFormWithDefaultValue < FormObject
  attribute :some_attribute

  def some_attribute
    super || "Default"
  end
end
```

After checking if the default value works, this is what you get:

```
> MyFormWithDefaultValue.new.some_attribute
=> NoMethodError: super: no superclass method `some_attribute' for #<MyFormWithDefaultValue:0x007f84a50ae8e0>
```

Whoops! How did it happen? The method was defined in the superclass so it should be inheritable, right?

Well, this is not really true. However, the problem is easy to fix.

## Anatomy Of The Problem

The primary question we should answer in the first place is: where are all those new methods defined using `define_method` in that particular way? Is it a superclass?

```
 FormObject.instance_methods - Object.methods
 => []
```

It's definitely not a superclass - there are no any instance methods defined there, there are only the ones inherited from `Object`. What about `MyFormWithDefaultValue`?

```
> MyFormWithDefaultValue.instance_methods - Object.methods
 => [:some_attribute, :some_attribute=]
```

Now the error that we initially got makes way more sense. The entire issue is caused by the fact that the declaration of the attribute happens in `MyFormWithDefaultValue`, if it were defined in a base class, there would be no any issue. We can verify it with a simple example:

``` rb
class MyForm < FormObject
  attribute :some_attribute
end

class MyFormWithDefaultValue < MyForm
  def some_attribute
    super || "Default"
  end
end
```

```
> MyFormWithDefaultValueA.new.some_attribute
 => "Default"
```


## Solution

Now that we fully understand the problem let's think about the solution. Ideally, about the one, that doesn't require defining explicitly an intermediate class that we can inherit from.

How about defining a module instead? Modules are also included in the inheritance chain, and for using `super`, it doesn't matter if the method is defined in the class or a module.

The exact solution to the problem would be wrapping the definition of new methods that happens in `FormObject` inside some module, it could be even an anonymous one, and including it right away:

```
class FormObject
  def self.attributes_registry
    @attributes_registry ||= []
  end

  def self.attribute(attribute_name)
    attributes_registry << attribute_name

    wrapper = Module.new do
      define_method(attribute_name) do
        instance_variable_get("@#{attribute_name}")
      end

      define_method("#{attribute_name}=") do |value|
        instance_variable_set("@#{attribute_name}", value)
      end
    end
    include wrapper
  end
end
```


Let's verify if the new solution works:

```
> MyFormWithDefaultValue.new.some_attribute
 => "Default"

```

Yay! It does exactly what we wanted to achieve.

## Wrapping Up

Metaprogramming in Ruby is a powerful tool, however; it can lead to some issues that might not be obvious why they happen. Fortunately, with enough knowledge of the language, those problems can be solved elegantly.
