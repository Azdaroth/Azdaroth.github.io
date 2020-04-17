---
layout: post
title: "Test Driven Rails – Part 1"
date: 2014-01-04 16:19
comments: true
categories: [TDD, BDD, Testing, Ruby on Rails, Rails]
---


<p>Testing is still one of the hottest topics when it comes to developing maintainable and business-critical applications. Ruby on Rails community embraces the importance of writings tests, yet there are so little resources about the Test-Driven Development or Behavior-Driven Development in Rails applications from a wider perspective. How should we test our application? Which tests are valuable and which don’t provide any value? What scenarios should be included in acceptance tests?</p>

<!--more-->

<h2>Value of tests</h2>

<p>If you aren’t yet into testing, you might have some doubts: what can you get from tests and how they can help you? In a few words, by writing tests:</p>

<ol>
  <li>You make sure that a feature is implemented properly.</li>
  <li>You can refactor your code without fear of breaking entire application.</li>
  <li>You have an instant feedback about your code design (unit tests).</li>
</ol>

<p>And how is that different from manually checking if everything works? Well, manual checking is already some kind of testing – you can click hundreds of buttons in a browser, fill tens of forms and test different scenarios, but doing it after each change in a code is an awful waste of time. Oh, and remember to test your entire app after Rails update or any gem update… So it is obvious that automated testing will save you a lot of time and will help you track any bugs. </p>

<p>How about code design? The rule of thumb is that a clean code is easy to test. If your tests look awful and are difficult to follow, it probably means that the implementation is even worse. This mainly refers to the unit testing, which I will cover later.</p>

<h2>TDD vs. BDD</h2>

<p>You have probably seen many times how some developers advocate Behavior-Driven Development. How is that different from Test-Driven approach? The thing is that these two terms mean basically the same thing: writing acceptance tests for a feature and unit-testing your code, so that it can guide your design. It is not about acceptance vs. unit tests - BDD is not just about writing acceptance tests and TDD does not concentrate on unit testing. Testing done right includes both of them: if you write only acceptance tests, you just make sure that a feature works, but the code can be awful and difficult to maintain and the unit-tests alone cannot give you sufficient level of confidence that the entire app works, not only separate parts. </p>

<h2>To mock or not to mock</h2>

<p>
Before discussing arguments for and against mocks and stubs, I should explain differences between them - stubs are fake objects with predetermined responses and mocks are about expectations and collaboration. Take a look at the following example:</p>

``` ruby

describe SomeUsecase do

# some code with initializing object under the test and setting collaborators

  context “user is an admin “ do
    it “sends a notification” do
      allow(user).to receive(:admin?).and_return(true)
      expect(notifier).to receive(:deliver)
      usecase.call
    end
  end

  context “user is not an admin” do
    it “doesn’t send a notification” do
      allow(user).to receive(:admin?).and_return(false)
      expect(notifier).not_to receive(:deliver)
      usecase.call
    end
  end

end

```
<p>In this usecase, a <code>user</code> has predetermined response when the <code>:admin?</code> message is sent – this is stub. Depending on the response, the  <code>:deliver</code> message is sent to the<code>notifier</code> or not – which is a mock. By using mocks, you discover how the objects interact with its’ collaborators and ensure that proper expectations are met.</p>

<p>There are many arguments for using mocks and stubs, but also there are some valid issues against them. The most significant is that it can make your tests brittle, especially when you stub non-existent method (or mock). Because of that, many developers prefer to stay with integration tests using real objects. Fortunately, there are some solutions to prevent this problem. Since RSpec 3.0 (at time of writing this post the current version is beta1) the functionality of rspec-fire is merged into the core of the framework, which provides safe stubs that will inform you about stubbing non-existent method. You can also check <a href="https://www.relishapp.com/bogus/bogus/v/0-1-4/docs/getting-started" target="_blank">bogus</a> gem that provides similar functionality.</p>

<p>What are the benefits of using mock objects? You can test in isolation, which will make your test-suite running much faster – you don’t have to talk to the database, send notifications, connect to an external API etc. – slow test suite can be really discouraging. And the other important aspect of using mock objects is the design: if you use real objects, you won’t get much feedback about your code design. Mock objects force you to write a clean and OOP code – if you don’t, tests will simply get really ugly, which is the symptom of bad design choices.</p>

<p>While mocking there is an important rule to follow: only mock collaborators (peers), not the internals (like private methods – it’s an implementation detail) of the object  – if you think about doing so, then you should redesign your class. One more rule, which I don’t dogmatically follow, but is also important: only mock types you own. When you don’t own the API, you can’t be absolutely certain that the code will work in the future. It looks reasonable, but why would I treat more it like a suggestion? Consider ActiveRecord API – why wouldn’t you mock it? It is pretty stable and I can trust it won’t change, at least in the nearest future. If possible, you should implement own domain methods and treat ActiveRecord as an implementation detail – instead of calling <code>user.update(active: true)</code> in service object, you should use <code>activate</code> method: <code>user.activate</code> and define this method in the model layer, however, <code>update</code> might be sometimes the thing you need and then you can mock it.</p>

<h2>TDD rules and cycle</h2>

<p>When you TDD, it is important to follow its’ cycle, which is: Red, Green, Refactor. What does it mean exactly? Before you write the production code, you should write failing test first (red), you have to see the test fails – if it never fails, it has basically no value. Then you should write minimal implementation for satisfying this test (green), and then you can refactor your code if required – you can move some code to private methods or extract it to separate classes and because you have tests, you make sure that you haven’t broken anything. </p>

<p>Writing tests first for every line of the code is not always required. There are some cases, where a test won’t give you much value – remember: test itself is a code, which needs to be maintained - make sure you need it.</p>

<h2>What not to test?</h2>

<p>Before answering the question: how to write valuable tests, there are some issues that need to be discussed: what not to test? </p>

<h3>Do not test ActiveRecord and friends</h3>

<p>This may seem strange at first, but I’ve seen many tests having no real value and seemed as if ActiveRecord or ActiveModel cannot be trusted. Consider the following <code>User</code> model example:</p>

``` ruby

describe User do

  subject {  User.new }

  specify “user without name is not valid” do
    expect(subject).not_to be_valid
  end

end


```
<p>What kind of value does this test provide? The only scenario when this test might fail is when the model lacks of presence validation for name attribute. So either you are writing test for <code>ActiveModel::Validations</code> (believe me, it is already tested) or for the presence of the line of code with:</p>

``` ruby
  validates :name, presence: true
```

<p>This test is even pretty useless as a spec for the model, because reading model itself is much more descriptive.</p>

<p>What else falls into this category? Testing associations and relations – it is all about using them properly, there is no other way the test may fail. Do not test simple scopes as well, consider the following:</p>

``` ruby

class User < ActiveRecord::Base

  scope :active, -> { where(active: true) }

end

```

<p>Does it really make sense to write test for such code? What kind of value does it provide and how do you expect it to fail? ActiveRecord API is stable and can be trusted that it won’t change and <code>where</code> method will behave exactly the same.</p>

<h3>Do not test generic CRUD controllers</h3>

<p>What do I mean by generic CRUD controllers? Consider the following:</p>


``` ruby

class ArticlesController < ApplicationController

  def index
    @articles = Article.all
  end

  def show
    @article = Article.find(params[:id])
  end

  def new
    @article = Article.new
  end

  def create
    @article = Article.new(article_params)

    if @article.save
      flash[:notice] = “Article has been created.”
      redirect_to articles_path
    else
      render :new
    end
  end

  def edit
    @article = Article.find(params[:id])
  end

  def update
    @article = Article.find(params[:id])

    if @article.update(article_params)
      flash[:notice] = “Article has been updated.”
      redirect_to articles_path
    else
      render :edit
    end
  end

  def destroy
    Article.find(params[:id]).destroy
    flash[:notice] = “Article has been deleted.”
    redirect_to articles_path
  end

  private

    def article_params
      params.require(:article).permit(:title, :content)
    end

end

```
<p>It’s a typical easy CRUD Rails controller, where you don’t even need to read the code to know, what it does. It is so generic that you could DRY it up with some metaprogramming and naming conventions, or simply use <a href="https://github.com/josevalim/inherited_resources" target="_blank">Inherited Resources</a> gem. In many Rails testing tutorials you can find a section with controllers’ testing, which look basically like that:</p>

``` ruby

describe "#create" do

  context "valid attributes" do

    it "saves article" do
      expect do
        post :create, params: { title: "Article title", content: "Some content" }
      end.to change(Article, :count).by(1)
    end

    it "redirects to articles page" do
      post :create, params: { title: "Article title", content: "Some content" }
      expect(response).to redirect_to articles_path
    end

  end

  context "invalid attributes" do

    it "does not save article" do
      expect do
        post :create, params: { title: "Article title" }
      end.not_to change(Article, :count)
    end

    it "renders new template" do
      post :create, params: { title: "Article title" }
      expect(response).to render_template "new"
    end

  end

end

```

<p>And add tests for the remaining six actions. How much value do these tests provide? It does everything what is expected from simple controller and the only reason it may fail is making a typo. The same thing applies to tests with mocks and stubs in controllers testing. Basically I see no point at all in writing tests for CRUD controllers. To make things easier and make sure it works, you can provide some generic solution like <a href="https://github.com/josevalim/inherited_resources" target="_blank">Inherited Resources</a> gem or use Rails scaffolding.</p>

<p>The important thing is: you need to test controllers, but don’t do it for typical CRUD. Otherwise, you should thoroughly test your code, especially before_filters with some authorization and domain related logic.</p>

<h3>Do not test Helpers</h3>

<p>Helpers should be used in most cases for providing some generic HTML markup, for example:</p>

``` ruby

def main_menu_link_to(title, path, options={})
  content_tag(:li, class: ”main-menu”) do
    link_to(title, path, options)
  end
end

```
<p>It probably doesn’t require test coverage. If you think about putting some model presentation logic in helpers, then you are doing it wrong and should look at presenters (e.g. <a href="https://github.com/drapergem/draper" target="_blank">Draper</a> gem).</p>

<h3>Do not test trivial views</h3>

<p>And what is trivial thing in views? Writing Capybara tests for titles can be counted here, also testing simple CRUD and flash messages (unless they are somehow critical for the application). Don’t write simple tests for editing an article and verifying that the title has been changed after update or the article has been deleted after clicking “Delete” button. Leave Capybara tests for some more complicated scenarios and critical parts of your app.</p>

<h3>Do not use Cucumber</h3>

<p>Cucumber seems to have significant popularity among developers. One argument for using Cucumber is that it helps non-technical people read and write tests and, e.g. sit with the client and let him/her write some scenarios. Yeah, right. Honestly, how many clients have you met who wrote any tests? Was it worth adding additional layer of complexity and maintaining it?</p>

<p>Cucumber makes you duplicating your intentions – firstly, you write some scenarios and then implement in RSpec. Why not to implement them in RSpec alone, when Capybara DSL is extremely expressive? <del>Cucumber is the most overrated tool and in most cases it is simple waste of time with no benefits at all. If you use Cucumber in everyday testing, then take some time and think if you really need it and how valuable are these tests for you. If you haven’t tried Cucumber yet, don’t bother.</del>  If you use Cucumber in everyday testing, then take some time and think if you really need it and how valuable these tests are for you. If you haven’t tried Cucumber yet, make sure it solves your actual problems.</p>

<h2>What needs to be tested</h2>

<h3>Models</h3>

<p>The important thing is that you shouldn’t put your business logic in models, so sometimes there won’t be that many things that requires testing in this layer. If you write custom validations, e.g. for URLs, zip codes etc., extract it to separate validator and test it on some generic model.</p>

<p>Write tests for not trivial scopes, especially when you write raw complex SQL queries – some of them might be quite difficult to follow is much more convenient to verify query through tests, not e.g. in Rails Console or dbconsole.</p>

<p>Scopes with some database specific queries should be tested – e.g. hstore or arrays in PostgreSQL. Some operators like <code>hstore ?& text[]</code> (which means: does hstore contain all specified keys?) might look mystical at first glance. It is quite beneficial to test drive this kind of functionality. Sometimes it is not that obvious, how to use this kind of scopes and what result can be expected, even with nice, descriptive name and tests can help as a documentation.</p>

<p>Write tests for some domain methods  - when you have for instance User model, with attribute :active which can be either false or true, you can provide the following method:</p>

``` ruby

def activate
  update(active: true)
end

```

<p>and test for it:</p>

``` ruby

let(:user) { FactoryGirl.create(:inactive_user) }

describe “#activate” do

  it “makes user active” do
    expect(user.activate).to change { user.active }.from(false).to(true)
  end

end


```

<h3>Controllers</h3>

<p>Basically everything beyond the CRUD requires testing, especially some authorization-related logic. Consider the <code>ArticlesController</code> and the feature, when we don’t want to render inactive article for non-admin user:</p>

``` ruby

class ArticlesController < ApplicationController

  before_filter :allow_only_admin_for_inactive, only: [:show]

  # some code

  private

  def allow_only_admin_for_inactive
    article = Article.find(params[:id])
    if !article.active? and !(current_user and current_user.admin?)
      flash[:error] = “Article is not active”
      redirect_to articles_path
    end
  end

end

```
<p>Test for this before_filter should look like the following:</p>

``` ruby

require 'spec_helper'

describe ArticlesController do

  describe "inactive article" do

    let(:article) { double(:article, active?: false, id: 1) }

    before(:each) do
      allow(Article).to receive(:find) { article }
    end

    describe "user is logged in" do

      context "user is an admin" do

        let(:user) { double(:user, admin?: true) }

        it "renders article" do
          allow(controller).to receive(:current_user).and_return(admin)
          get :show, id: article.id
          expect(response).to render_template :show
        end
      end

      context "user is not an admin" do

        let(:user) { double(User, admin?: false) }

        it "redirects to articles path" do
          allow(controller).to receive(:current_user).and_return(user)
          get :show, id: article.id
          expect(response).to redirect_to articles_path
        end
      end

      context "user is not logged in" do

        before(:each) do
          allow(controller).to receive(:current_user).and_return(nil)
        end

        it "redirects to articles path" do
          get :show, id: article.id
          expect(flash[:error]).not_to be nil
          expect(response).to redirect_to root_path
        end
      end
    end
  end
end

```
<p>And that should be sufficient. If you have some complex authorization logic, then you should move it to separate class and write tests for this class, not test in controllers.</p>

<p>How about acceptance tests for his feature? Well, it is quite simple and controller test gives me sufficient level of confidence that it works, so I believe that it is not needed.</p>

<p>The good practice is to always use mock objects and stub everything in controllers, which is writing unit tests for controllers, not integration tests.</p>

<h3>Presenters</h3>

<p>Most of the time tests are not that essential for the presenters – they contain presentation logic, often related to nice formatting and, unless it is somehow business-critical, you don’t have to test it. If you have some complex logic, consider moving it to a separate class and write test for the new object (maybe <code>DateFormatter</code>?). Personally I write tests for methods, where few scenarios are possible (i.e. they contain conditionals) – it serves as a nice documentation and gives instant information how it works.</p>

<p>I wouldn’t write test for the following usecase:</p>

``` ruby

class InvestmentDecorator < ApplicationDecorator

  # assuming that draper gem is used here
  # every investment has statistic_profile

  def display_areas_range
    “Apartments’ areas from #{statistic_profile.minimum_apartments_area} to #{statistic_profile.maximum_apartments_area} “
  end

end

```

<p>However, this may require testing:</p>

``` ruby

class UserDecorator < ApplicationDecorator

  def display
    if model.firstname.present? and model.surname.present?
      “#{model.firstname} #{model.surname}”
    else
      model.email
    end
  end

end

```
<p>Business logic - usecases, services, policy objects, value objects etc.</p>

<p>Nothing to be discussed here – business logic requires 100% test coverage, as simple as that. It is essential for your application, so you cannot leave anything untested.</p>


<h2>Views and acceptance testing</h2>

<p>Acceptance tests might be difficult to maintain and they are slow, you should write them carefully and make sure that you are testing right stuff. Focus on critical features of your app. When you work on an e-commerce solution, buying process is essential (with different scenarios for registered user and guest user), rendering current shopping cart, sending notifications after completing order etc. When you have georegion specific content, you should write acceptance tests for it. You have some important UI implemented using Javascript? Don’t forget to write tests for it with <code>js: true</code> option in Capybara. Focus on critical parts and complex scenarios, not simple single features.</p>


<h2>Integration tests</h2>

<p>Acceptance tests shouldn’t cover every possible scenarios, it may get too slow and might not give sufficient feedback why something has failed. Leave it to integrations tests with – especially when you have some XML/JSON importing or you interact with 3rs party APIs. Don’t stub or mock anything there, use real objects.</p>

<hr />

<p>And that’s would be end for part 1. Part 2 will be more practice oriented with implementing specified feature using techniques described here.</p>
