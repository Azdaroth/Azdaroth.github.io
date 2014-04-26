---
layout: post
title: "You don't (necessarily) need gem for that feature"
date: 2014-04-26 15:02
comments: true
categories: [Rails, TDD, Design Patterns, Testing, Architecture]
---


<p>You are working currently on that awesome app and just started thinking about implementing new feature, let's called it feature X. What's the first thing you do? Rolling your own solution or... maybe checking if there's a magical gem that can help you solve that problem? Ok, it turns out there's already a gem Y that does what you expect. It does tons of other things and is really complex but who cares. After some time your app breaks, something is definitively not working and it seems that gem Y is responsible for that. So you read all the issues on Github, pull requests and even read the source code and finally find a little bug. You managed to do some monkeypatching first and then send pull request for a small fix and solved a problem, which took you a few hours. Looks like a problem is solved. And then, you try to update Rails to the current version. Seems like there's a dependency problem - gem Y depends on previous version of Rails...</p>

<p>Does it sound somehow familiar to you? I know the pain... Some breaking changes happens especially when updating Rails. If this change happens in "big" gem that solves a lot of problems and is still maintained, it's not that bad. How about these "small" gems, which come in handy and look quite complex but you could roll your own solution to that particular problem within half an hour?</p>

<p>I've seen this many times where first thing when implementing new feature is searching for a gem that solves this problem. We need really basic polymorphic tags? Let's use acts-as-taggable-on, we don't need half of the features provided and setting up a few migrations and associations would take 10 minutes anyway but there's no need to reinvent the wheel. Client asked for a simple admin panel with some CRUD stuff involving several models. Let's use active_admin or rails_admin for that! Simple searching / filtering where several fields in one model are involved? Ransack is an obvious choice!</p>

<p>More gems mean: slower boot time of your application, more dependencies (don't look only at Gemfile, Gemfile.lock is the real deal), more things that can break, more issues to take care of when updating Rails and the gem itself (reading Changelogs, issues etc.).</p>

<h2>When to use third party gem when implementing feature X?</h2>

<ul>
  <li>Gem is actively being maintained, there were some commits not that long ago (basic prerequisite)</li>
  <li>Gem solves the exact problem you have and does only that</li>
  <li>Gem does plenty of other things but it deals with areas you are not really familiar involving security, encryption etc. (e.g. symmetric-encryption)</li>
  <li>Gem does many other things and you need just a small part of it but rolling your own solution would take really a lot of time (e.g. devise)</li>
  <li>Gem deals with complex infrastructure things (e.g. carrierwave)</li>
</ul>

<p>Remember that using gem Y means also reading docs and it might be beneficial to read some parts of source code, just to get the general idea how it works. It also takes some time. Why not implement your own solution? It might look like reinventing the wheel but no gem will be that customizable to the extent you need. Or you will be using just a small part of it and the models / controllers will have tens of additional methods you don't need (and hundreds more with several gems).</p>


<h2>Writing own solution</h2>

<p>How much work does it really take to reimplement a gem? Let's take a look at something popular - draper gem. Draper is a pretty good solution for decorators/presenters for your models in Rails apps. I've been using it for quite long a time, had some issues but managed to solve them rather quickly. But the source code looks quite complex, especially extracting view_context with a bit global-variable-like RequestStore. And there are some other complex parts that I don't really use. Let's write custom presenters and call it DecentPresenter. What kind of interface and conventions would I expect from it?</p>

<ul>
  <li>Include some module in controllers (ApplicationController) - I want to be explicit here, without including it automatically on Rails app boot. Also I don't want to include it in models - model doesn't have to know that it can be presented in one way or another</li>
  <li>Establish naming convention: default presenter for User would be UserPresenter</li>
  <li>Call <code>present(user)</code> in controller which would wrap user by UserPresenter and present(User.all) which would handle collections</li>
  <li>Ability to specify other presenter than the default one - present(user, with: OtherPresenter)</li>
  <li>Have access to helpers within presenters</li>
  <li>Presenters will inherit from some base class (DecentPresenter::Base)</li>
</ul>

<p>Doesn't really look that hard. Getting access to Rails helpers might seem difficult but we can get it from <code>view_context</code> in controllers. Let's start with integration test for presenters. We want to include a module to a class (Controller), which would mix in <code>present</code> method. Let's call it DecentPresenter::Exposable:</p>

``` ruby spec/decent_presenter/exposable_spec.rb

require 'spec_helper'

class DummyModelForExposableTest 

  def name
    "name"
  end

end

class DummyModelForExposableTestPresenter < DecentPresenter::Base 

  def name
    "presented name"
  end

end

class DummyModelForExposableOtherPresenter < DecentPresenter::Base 

  def name
    "other presented name"
  end

end

class DummyObjectErrorPresenterExposable

  include DecentPresenter::Exposable

  def present_model(model)
    present(model)
  end

end

class DummyObjectPresenterExposable


  def view_context ; end 

  include DecentPresenter::Exposable

  def present_model(model)
    present(model)
  end

  def present_model_with_options(model, options)
    present(model, options)
  end


  def present_collection(collection)
    present(collection)
  end

  def present_collection_with_options(collection, options)
    present(collection, options)
  end

end



describe DecentPresenter::Exposable do

  context "view_context prerequisite" do

    it "raises DoesNotImplementViewContextError if view_context method
      is not defined" do
      model = DummyModelForExposableTest.new
      expect do 
        DummyObjectErrorPresenterExposable.new.present_model(model)
      end.to raise_error DecentPresenter::Exposable::DoesNotImplementViewContextError,
        "Object must implement :view_context method to handle presentation"
    end

    it "doesn't raise DoesNotImplementViewContextError if view_context method
      is defined" do
      model = DummyModelForExposableTest.new
      expect do 
        DummyObjectPresenterExposable.new.present_model(model)
      end.not_to raise_error
    end

  end

  context "presentation" do

    let(:model) { DummyModelForExposableTest.new }
    let(:collection) { [model] }

    subject { DummyObjectPresenterExposable.new }

    it "presents model with default presenter" do
      expect(subject.present_model(model).name).to eq "presented name"
    end

    it "presents model with specified presenter" do
      expect(subject.present_model_with_options(
          model,
          with: DummyModelForExposableOtherPresenter
        ).name
      ).to eq "other presented name"
    end

    it "presents models collection with default presenter" do
      expect(subject.present_collection(collection).first.name).to eq "presented name"
    end

    it "presents models collection with specified presenter" do
      expect(subject.present_collection_with_options(
          collection,
          with: DummyModelForExposableOtherPresenter
        ).first.name
      ).to eq "other presented name"
    end

  end

end

```

<p>What happens here? First off, we set up some dummy classes: DummyModel with <code>name</code> method, two presenters for testing with default presenter and other presenter and two classes, where we include DecentPresenter::Exposable module. Why two? Just to check that if the object implements <code>view_context</code> method. If the <code>view_context</code> method is not implemented, we provide descriptive error. Then we test write some tests for a single model / collection and default / custom presenter to check if they are presented. Let's write some code:</p>

``` ruby lib/decent_presenter/exposable.rb

module DecentPresenter
  module Exposable
 
    def present(presentable, options = {})
      if respond_to? :view_context
        # decorate the presentable object here
      else
        raise DecentPresenter::Exposable::DoesNotImplementViewContextError.new(
          "Object must implement :view_context method to handle presentation"
        )
      end
    end

    class DoesNotImplementViewContextError < StandardError ; end
        
  end
end

```

<p>And just define base class for presenters:</p>

``` ruby lib/decent_presenter/base.rb
moduleDecentPresenter
  class Base 

  end
end
```

<p>Tests within presentation context still fail but they will be the last ones that will pass. Let's leave them for now and thing about base class - DecentPresenter::Base and it's subclasses, our presenters. We want to have access to helpers by <code>helpers</code> method and <code>h</code> for shorthand. We also need have access to presented object: by <code>object</code> and <code>model</code> methods. If the method isn't implemented by presenter, it should be delegated to presented model. Sounds like <code>method_missing</code>? That's one possibility. Let's try something different - <a href="http://www.ruby-doc.org/stdlib-1.9.3/libdoc/delegate/rdoc/SimpleDelegator.html" target="_blank">SimpleDelegator</a>. SimpleDelegator is a pretty cool core class with two public methods <code>__getobj__</code> and <code>__setobj__</code> - the first one exposes decorated object and the latter sets objects to which all method calls will be delegated. The object is set when we pass it to the constructor of <code>SimpleDelegator</code>. Looks like our <code>DecentPresenter::Base</code> class will inherit from <code>SimpleDelegator</code>. But we will need to override constructor to pass <code>view_context</code>. Also, it would be quite useful to be able to present other objects within our presenters. Let's write some tests:</p>

``` ruby specs/decent_presenter/base_spec.rb
require 'spec_helper'

class DummyModelForBaseClassTest

  def name
    "dummy_model_name"
  end

  def stuff
    "stuff"
  end

end

class DummyViewContext ; end


class DummyModelPresenter < DecentPresenter::Base

  def name
    "presented #{model.name}"
  end

end


describe DecentPresenter::Base do

  let(:model) { DummyModelForBaseClassTest.new }
  let(:view_context) { DummyViewContext.new }
  
  context "base" do

    subject { DecentPresenter::Base.new(model, view_context) }

    it "exposes model as model" do
      expect(subject.model).to eq model
    end

    it "exposes model as object" do
      expect(subject.object).to eq model
    end

    it "exposes view_context as h" do
      expect(subject.h).to eq view_context
    end

    it "exposes view_context as helpers" do
      expect(subject.helpers).to eq view_context
    end

  end

  context "subclass" do

    subject { DummyModelPresenter.new(model, view_context) }

    it "decorates model's methods" do
      expect(subject.name).to eq "presented dummy_model_name"
    end

    it "delegates method calls to model when the method is not defined
      within presenter" do
      expect(subject.stuff).to eq "stuff"
    end

    it "implements presentable interface" do
      expect(subject).to respond_to :present
    end

  end

end
```

<p>Like before, we setup some DummyClasses and write some tests for the requirements we've just discussed. Our base class implements <code>view_context</code> so it looks like we just need to include <code>DecentPresenter::Exposable</code> module and we will be able to decorate other objects within our presenters. We cover it be checking if the subclasses implement required interface. We also cover some delegation stuff in tests, <code>SimpleDelegator</code> ensures it will be delegated but it is a core functionality for presenters so it might be a good idea to test for it. Let's write the implementation:</p>

``` ruby lib/decent_presenter/base.rb
module DecentPresenter
  class Base < SimpleDelegator

    include DecentPresenter::Exposable

    attr_reader :view_context
    private :view_context
    
    def initialize(object, view_context)
      super(object)
      @view_context = view_context
    end

    def model
      __getobj__
    end

    alias :object :model

    def helpers
      view_context
    end

    alias :h :helpers    

  end
end
```

<p>We need a main interface which would wrap our models within presenters. Sure, we could do it in present method but I don't really like the idea that the e.g. controller would know, how to present a model. Let's implement dedicated interface which is going to be used by <code>present</code> method. We have some integration tests for presenters, base class is already covered, so we will just need to check, if a model or collection is decorated by presenters:</p>

``` ruby spec/decent_presenter/exposure_spec.rb
require 'spec_helper'

class DummyModelForExposureTest ; end

class DummyModelForExposureTestPresenter < DecentPresenter::Base ; end

class DummyModelForExposureTestOtherPresenter < DecentPresenter::Base ; end

describe DecentPresenter::Exposure do

  let(:presenter_factory) { double(:presenter_factory) }
  let(:view_context) { double(:view_context) }

  let(:model) { DummyModelForExposureTest.new }
  let(:collection) { [model] } 

  subject { DecentPresenter::Exposure.new(view_context, presenter_factory) }

  before(:each) do
    allow(presenter_factory).to receive(:presenter_for)
      .with(model) { DummyModelForExposureTestPresenter }
  end

  it "presents model with default presenter" do
    presented_model = subject.present(model)
    expect(presented_model).to be_instance_of DummyModelForExposureTestPresenter
  end

  it "presents model with specified presenter" do
    presented_model = subject.present(model, with: DummyModelForExposureTestOtherPresenter)
    expect(presented_model).to be_instance_of DummyModelForExposureTestOtherPresenter
  end

  it "presents models in collection with default presenter" do
    presented_collection = subject.present(collection)
    expect(presented_collection.first).to be_instance_of DummyModelForExposureTestPresenter
  end

  it "presents models in collection with specified presenter" do
    presented_collection = subject.present(collection, with: DummyModelForExposureTestOtherPresenter)
    expect(presented_collection.first).to be_instance_of DummyModelForExposureTestOtherPresenter
  end

end
```

<p>The <code>Exposure</code> class is going to have one public method which takes model or collection as the first argument and the options hash, where we can specify presenter. If it's not specified the default presenter will be used. And how do we know what the default presenter is? Don't know yet, so let's introduce a collaborator, which takes model and returns default presenter for it. We will call it <code>presenter_factory</code>. We also need to remember about the <code>view_context</code> dependency. Let's write the implementation:</p>

<p>Note: again, the implementation is quite clean, but remember the TDD cycle: red, green, refactor, write minimal implementation for the first test, make it pass and repeat. This post is not about how to TDD properly and to focus on the core things I just give code after refactoring phase. </p>

``` ruby lib/decent_presenter/exposure.rb
module DecentPresenter
  class Exposure
    
    attr_reader :view_context, :presenter_factory
    private :view_context, :presenter_factory

    def initialize(view_context, presenter_factory)
      @view_context = view_context
      @presenter_factory = presenter_factory
    end

    def present(presentable, options = {})
      if presentable.respond_to?(:size)
        present_collection(presentable, options)
      else
        present_model(presentable, options)
      end
    end

    private

      def present_model(presentable, options = {})
        presenter = options.fetch(:with) do
          presenter_factory.presenter_for(presentable)
        end
        presenter.new(presentable, view_context)
      end

      def present_collection(collection, options = {})
        collection.map { |el| present_model(el, options) }        
      end      

  end
end
```
<p>We need somehow to distinguish between collection and a single model. The collection will probably implement the <code>size</code> method. What if the model also implements size method ? Looks like we need to make some paranoid check. Let's modify test for <code>DecentPresenter::Exposure</code> and add <code>size</code> method to DummyModel:</p>

``` ruby spec/decent_presenter/exposure_spec.rb
# other code

class DummyModelForExposureTest 
  
  def size ; end

end

# other code

end
```

<p>Now the tests fail. How can we make sure the collection really is a collection? Besides <code>size</code>, it'll probably implement <code>to_a</code> and <code>first</code> methods. Let's update the implementation:</p>

``` ruby lib/decent_presenter/exposure.rb
module DecentPresenter
  class Exposure
    
    attr_reader :view_context, :presenter_factory
    private :view_context, :presenter_factory

    def initialize(view_context, presenter_factory)
      @view_context = view_context
      @presenter_factory = presenter_factory
    end

    def present(presentable, options = {})
      if presentable_is_a_collection?(presentable)
        present_collection(presentable, options)
      else
        present_model(presentable, options)
      end
    end

    private

      def present_model(presentable, options = {})
        presenter = options.fetch(:with) do
          presenter_factory.presenter_for(presentable)
        end
        presenter.new(presentable, view_context)
      end

      def present_collection(collection, options = {})
        collection.map { |el| present_model(el, options) }        
      end      

      def presentable_is_a_collection?(presentable)
        [:size, :to_a, :first].all? { |method| presentable.respond_to? method }
      end

  end
end
```

<p>Looks like we only have <code>DecentPresenter::Factory</code> left. The factory should return a default presenter (constant) based on model's class. What if it doesn't exist? We will provide descriptive error message. Let's write tests:</p>

``` ruby spec/decent_presenter/factory_spec.rb
require 'spec_helper'

class DummyModelForFactoryPresenter ; end
class DummyModelForFactory ; end
class OtherDummyModel ; end


describe DecentPresenter::Factory do

  subject { DecentPresenter::Factory }

  it "implements DecentPresenter Factory interface" do
    expect(subject).to respond_to :presenter_for
  end

  describe ".presenter_for" do

    it "gives presenter class based on object's class in convention: KlassPresenter" do
      model = DummyModelForFactory.new
      expect(subject.presenter_for(model)).to eq DummyModelForFactoryPresenter
    end

    it "raises PresenterForModelDoesNotExist error if presenter class is not defined" do
      model = OtherDummyModel.new
      expect do 
        subject.presenter_for(model) 
      end.to raise_error DecentPresenter::Factory::PresenterForModelDoesNotExist,
        "expected OtherDummyModelPresenter presenter to exist"
    end

  end

end
```

<p>I also added test for covering factory interface to guard against changing interface which is used in <code>DecentPresenter::Exposure</code> - you can imagine the situation where the method name is changed and the tests still pass. We have integration tests for it (<code>DecentPresenter::Exposable</code>) but having these kind of tests underlines the fact that it shouldn't be changed. To extract the presenter's name from model we will ask model for it's class, add "Presenter" suffix and use <code>classify</code> method:</p>

``` ruby lib/decent_presenter/factory.rb
module DecentPresenter
  module Factory
    
    extend self

    def presenter_for(model)
      presenter_class_name = "#{model.class}Presenter"
      begin
        presenter_class_name.constantize
      rescue NameError
        raise PresenterForModelDoesNotExist.new(
          "expected #{presenter_class_name} presenter to exist"
        )
      end
    end

    class PresenterForModelDoesNotExist < StandardError ; end

  end
end
```

<p>The last thing is to make integration tests pass, let's finish the <code>present</code> method:</p>

``` ruby lib/decent_presenter/exposable.rb
module DecentPresenter
  module Exposable
 
    def present(presentable, options = {})
      if respond_to? :view_context
        DecentPresenter::Exposure.new(
          view_context, DecentPresenter::Factory
        ).present(presentable, options)
      else
        raise DecentPresenter::Exposable::DoesNotImplementViewContextError.new(
          "Object must implement :view_context method to handle presentation"
        )
      end
    end

    class DoesNotImplementViewContextError < StandardError ; end
        
  end
end
```

<p>Seems like we are almost done. All tests pass but one common use case still won't work - pagination. We can use some array pagination but it's pretty inconvenient. We need somehow to keep a reference of the original collection, delegate some pagination methods to the original collection and other methods should be handled by presented collection. Sounds like a proxy? Let's write tests for <code>DecentPresenter::CollectionProxy</code>:</p>

``` ruby spec/decent_presenter/collection_proxy_spec.rb

  require 'spec_helper'

TEST_COLLECTION_PROXY_PAGINATION_METHODS = [
  :current_page, :total_pages,
  :limit_value, :model_name, :total_count,
  :total_entries, :per_page, :offset
]

class DummyOriginalForCollectionProxy
  
  TEST_COLLECTION_PROXY_PAGINATION_METHODS.each do |method|
    define_method method do 
      "original"
    end
  end

end

class DummyPresentedForCollectionProxy

  def presented_method
    "presented"
  end

  def other_presented_method
    "presented"
  end

end

describe DecentPresenter::CollectionProxy do

  subject { DecentPresenter::CollectionProxy.new(
    DummyOriginalForCollectionProxy.new, DummyPresentedForCollectionProxy.new
    )
  }

  it "delegates pagination-related methods to original collection" do

    TEST_COLLECTION_PROXY_PAGINATION_METHODS.each do |pagination_method|
      expect(subject.send(pagination_method)).to eq "original"
    end

    
  end

  it "delegates other methods to presented collection" do
    [:presented_method, :other_presented_method].each do |presented_method|
      expect(subject.send(presented_method)).to eq "presented"
    end
  end

end

```

<p>I searched for some pagination-related methods and put them in <code>TEST_COLLECTION_PROXY_PAGINATION_METHODS</code>. I also introduced two dummy collection classes - one for pagination methods and the latter for handling other methods. To DRY out the implementation I use <code>define_method</code>. The tests verify that the method calls are properly delegated. Let's write the implementation with <code>method_missing</code>:</p>

``` ruby lib/decent_presenter/collection_proxy.rb
module DecentPresenter
  class CollectionProxy

    delegate :current_page, :total_pages, :limit_value, :model_name, :total_count,
      :total_entries, :per_page, :offset, to: :original_collection
      
    attr_reader :original_collection, :presented_collection
    private :original_collection, :presented_collection

    def initialize(original_collection, presented_collection)
      @original_collection = original_collection
      @presented_collection = presented_collection
    end

    def method_missing(method, *args, &block)
      presented_collection.send(method, *args, &block)
    end

  end
end
```

<p>The <code>delegate</code> method from <code>ActiveSupport</code> comes in handy for proxies. We need to modify <code>DecentPresenter::Exposure#present</code> and wrap the presented collection and the original collection in proxy. Let's add a test for that also:</p> 

``` ruby spec/decent_presenter/exposure_spec.rb
require 'spec_helper'

describe DecentPresenter::Exposure do

  # other code

  it "wraps collection in CollectionProxy" do
    presented_collection = subject.present(collection)
    expect(presented_collection).to be_instance_of DecentPresenter::CollectionProxy
  end

end
```

``` ruby lib/decent_presenter/exposure.rb
module DecentPresenter
  class Exposure
    
    attr_reader :view_context, :presenter_factory
    private :view_context, :presenter_factory

    def initialize(view_context, presenter_factory)
      @view_context = view_context
      @presenter_factory = presenter_factory
    end

    def present(presentable, options = {})
      if presentable_is_a_collection?(presentable)
        present_collection(presentable, options)
      else
        present_model(presentable, options)
      end
    end

    private

      def present_model(presentable, options = {})
        presenter = options.fetch(:with) do
          presenter_factory.presenter_for(presentable)
        end
        presenter.new(presentable, view_context)
      end

      def present_collection(collection, options = {})
        presented_collection = collection.map { |el| present_model(el, options) }
        DecentPresenter::CollectionProxy.new(collection, presented_collection)
      end      

      def presentable_is_a_collection?(presentable)
        [:size, :to_a, :first].all? { |method| presentable.respond_to? method }
      end

  end
end
```

<p>And we are done! The test for verifying if the instance of <code>DecentPresenter::CollectionProxy</code> is returned when handling collection introduces some coupling but I'm pretty comfortable with it. It won't be handled by any other object than the CollectionProxy.</p>

<p>The DecentPresenter is much simpler than Draper, it offers most of the stuff I need in my presenters and writing it was pretty enjoyable :). It didn't take much time and I have a solution, which I'm familiar with and if something breaks I will know why. In fact, I like it so much that I'm going to release it as a gem :).</p>

<h2>Wrapping up</h2>

<p>Using third party gem isn't always a best solution, sometimes it's quite easy to write similar solution. Many gems are quite complex because they need to handle all possible use cases and that level of complexity and other dependencies might not be necessary for your app.</p>