---
layout: post
title: "Structuring Rails applications"
date: 2013-10-06 15:00
comments: true
categories: [OOP, Rails, Design Patterns, Callbacks, Refactoring]
---

<p>There've been a lot of discussions recently about applying Object Oriented Programming in Rails applications, how ActiveRecord callbacks make testing painful and how Rails makes it hard to do OOP the right way. Is it really true? Rails makes everything easy - you can easily write terrible code, which will be a maintenance nightmare, but is also easy to apply good practices, especially with available gems. What is the good way then to extract logic in Rails applications and the best place to put it?</p>

<h2>Standard structure</h2>

<p>By default we have four directories where we can put our code: models, views, controllers and helpers. The basic explanation of them is following:</p>

<ul>  
  <li>Models - dealing with database, validations, repository, persistence.</li>
  <li>Controllers - parsing requests, sessions, rendering views etc.</li> 
  <li>Views - user interface, data presenting.</li>
  <li>Helpers - place to put reusable methods for views.</li>
</ul>

<p>Does it mean these are the only places where you can put your code? No! It's just a default structure with basic parts of your application. You can easily extend it by creating new directories and then adding them to autoload paths, e.g.: </p>

``` ruby
  config.autoload_paths += Dir["#{AppName::Application.config.root}/app/usecases"]
``` 

<h2>How about lib directory?</h2>

<p>Unless you are extracting something to a gem, I would discourage you from putting anything there. Some developers put in the lib all the code that doesn't belong to models/controllers/helpers, but if something is part of your application why not add it to the app directory?</p>

<h2>Skinny controllers, fat models</h2>

<p>The design mantra for the last few years in Rails was to move logic from controllers to models. Well, it's partially a good thing - skinny controllers are clear, easy to test and maintain, but why should models be like 1000 lines of code with tens of responsibilities (and no, everything concerning User is not a single responsibility)? It makes models in most cases the most problematic layer in Rails applications. They often include a lot of unrelated methods, conditional validations, cross-models operations, callbacks etc. - all the things that ActiveRecord makes really easy to add. So, the important question is:</p>

<h2>Is ActiveRecord evil?</h2>

<p>ActiveRecord is a wonderful ORM, which indeed makes everythings easy. But with great power comes great responsibility. Think about callbacks: you can add new logic in a blink of an eye and it does the job. So you keep adding other callbacks until you discover that there are some cases where you don't want them to be executed. So you add conditionals or bypass-like methods. After some time, the logic in callbacks is so complexed that you waste few hours with other developers to understand why something was executed at all. If other developers join the project, it is even harder for them to understand what model class really does. But it isn't the worst part. Think about some gems and their integration with Rails. Often it means extending models with another callbacks. Here are some real world problems:

<p>Imagine the situation where you need to implement the ability for admin to register other users and the application uses Devise gem for authentication. Furthermore, the <code> Confirmable</code> module is included in the <code>User</code>  class. Accidentally, you forgot to pass a date to <code>:confirmed_at</code> field or use <code>confirm!</code>  method. What happens then? The confirmation email is sent to all registered users. Oops, welcome to the wonderful world of callbacks. I don't want to criticize Devise, because it is a great gem, which I use in almost every project, but I am not sure if sending emails being directly coupled to the model layer was a good design decision. In docs you can read about the <code>skip_confirmation!</code> method and if you use external gem for such a critical part of your application, you should read the entire docs, but it can be really suprising, that the confirmation email is sent in all cases, even if you create user from Rails Console. Oh, and guess what happens if you want to change one's email from the console and <code> reconfirmable</code> option is enabled? The confirmation email is sent... Well, remember about reading docs, especially when the gem may include callbacks.</p>

<p>Any other examples? Of course. So, you want to implement a generic forum. There is a gem called Forem, which provides you with basic forum functionality. And one day you want to change state of some posts to be approved. So you enter Rails Console and using <code> update</code>  or <code>update_attributes</code> you perform the update. What happens then? There is a callback in <code>Forem::Post</code>  model:</p>

``` ruby
  after_save :email_topic_subscribers, :if => Proc.new { |p| p.approved? && !p.notified? }
```

<p>A lot of emails have been just sent! That was really unexpected. If you are used to  skipping callbacks in such situatons by using <code>update_columns</code> method or any other way, you are safe, but callbacks are so tighly coupled to models, that you cannot be sure if you are safe, even in console. What is the conslusion? Beware of callbacks. And read docs and code of the gems you use :).</p>

<p>So, how to avoid unexpected situations and have clean and understandable code?</p>

<h2>Structuring Rails applications - my way</h2>

<p>I've been working on several projects and the best solution in terms of maintenance, understandability and ease of testing is the following:</p>

<h3>Models</h3>

<p>I use models for: factory methods, queries, scopes, general validations, which are always applicable e.g. presence and uniqueness validations for fields with <code>null: false</code>  and / or <code>unique: true</code> constraints, also "domain constraints", especially with many-to-many associations. The example of domain constraint is assigning users, who belong to the same organization, to some subgroups - assigning users from other organizations is prohibited. Putting this kind of logic in controllers' before_filters or permission classes is not enough for me, I want to ensure the integrity of the data and make it impossible to bypass this restriction. Here is an example: we have <code>User</code>  model and <code>Group</code> model and the many-to-many relationship between them, which is established by <code>has_many , through: </code> macro with <code>GroupsUsers</code>  join model. Also, users and groups belong to <code>Organization</code>. Here is a validation for creating relation in join model:</p> 

``` ruby
class GroupsUsers < ActiveRecord::Base
  
  belongs_to :group
  belongs_to :user

  validates :group, presence: true
  validates :user,  presence: true
  validate :ensure_valid_organization

  private

    def ensure_valid_organization
      if user.organization != group.organization
        raise InvalidOrganizationError, "User's organization does not match Group's organization."
      end
    end

end
```
<p>Other example of domain constraint is validation of inclusion.</p>

<p>Sometimes I do use callbacks. The basic rule when applying callbacks for me is to use them for processing some data, which should always take place. In most cases, it is limited to three callbacks:</p>

``` ruby
before_save   :create_parameterized_name
after_save    :calculate_statistics
after_destroy :calculate_statistics
```

<p>Pretty easy to understand: everytime the record is saved, I want to have parameterized form of name, e.g. for a slug. Also, after the record is saved or destroyed, I want the statistics to be updated. For instance, in real estate search engine application, investment has many apartments and I want to keep track of total count of apartments, average price, minimum and maximum price etc. without performing calculations each time. And one more callback concerning associations: <code>dependent: :destroy</code>  option. It is pretty useful and keeps the integrity of data, but you have to be sure when using it. If you think for a moment, these are "low-level" callbacks - they don't concern business logic and are something that you would like to have on a database level. It can be also achieved by using trigger functions in the database, but Rails callbacks are much easier to handle.</p>

<p>This is not the only right way for using callbacks, if you are absolutely sure that something should really be executed as callback, feel free to use them, but please, don't send notifications, don't connect with Facebook API or download files from Dropbox in callbacks. You will be safe, the logic will be easy to understand and testing will be much easier.</p>

<p>Sometimes I use model as an interface for some service objects / usecases / whatever you call it. Here is an example: </p>

``` ruby
class Article < ActiveRecord::Base

  def publish(publisher = DefaultPublisher)
    publisher.new(self).publish
  end

end
```

<p>It is a great way to have a flexibility in publishing articles - by dependency injection we can control, how it is being published - just pass publisher class as a strategy. Having default publisher makes it easy to use: just call <code>article.publish</code> . Also, calling <code>article.publish</code> in e.g. controller feels much better than calling <code>DefaultPublisher(article).publish</code>. If you have very simple logic, like this one:</p>

``` ruby
def publish
  self.published_at = DateTime.now if self.published_at.blank?
  self.save
end
```

<p>don't bother with extracting it to external class, it would be pointless.</p>


<h3>Controllers</h3>

<p>Everything related to parsing requests, sessions, rendering templates, redirecting and flash messages should be put in controllers. What about application logic? In most cases it should be limited to a control-flow, for example:</p>

``` ruby
class ArticlesController < ApplicationController

  def create
    @article = Article.find(params[:id])

    if @article.save
      flash[:notice] = "You have successfully created an article."
      redirect_to articles_path
    else
      render :new
    end
  end
  
end
```

<p>Depending on the action, it could be much more complex. Consider the following:</p>

``` ruby

class OrdersController < ApplicationController

  def buy
    order = Order.new(order_params)
    order_proccesor = BooksOrderProcessor.new(order, current_user)

    begin
      payment_processor.pay
    rescue BooksOrderProcessor::InsufficientAmount
      flash.now[:error] = "Not enough books are available."
      render :new
    rescue BooksOrderProcessor::InsufficientFounds
      flash[:error] = "You have run out of funds."
      redirect_to profiles_path(current_user)
    else
      flash[:notice] = "You have bought a book."
      redirect_to books_path
    end
  end

  private

    def order_params
      params.require(:order).permit!
    end

end

```

<p>It is still good, such control-flow can take place in a controller, but order processing logic cannot. But what should be done with creating articles and sending notification or logging action? If it is only one additional line of code with method call like <code>Tracker.register("create", @article)</code> or <code>NewArticleNotfier.delay.notify</code>, for example:</p>

``` ruby

class ArticlesController < ApplicationController

  def create
    @article = Article.find(params[:id])

    if @article.save
      NewArticleNotfier.delay.notify
      flash[:notice] = "You have successfully created an article."
      redirect_to articles_path
    else
      render :new
    end
  end
  
end


```
<p>don't extract it to usecase or service object, it is ok to keep it in a controller.</p>


<h3>Cells</h3>

<p>You have probably had many situations with setting up the same instance variables in several controller actions for some widgets like: tags cloud, recent articles, recent comments, top visited articles etc. and it can be really inconvenient. Fortunately, there's a great gem: Cells, which are like mini controllers. Consider the following:</p>

``` ruby
class ArticlesCell < Cell::Rails

  def top_visited
    @articles = Article.top_visited
    render
  end

end

```

In cells/articles/top_visited.html.haml/erb you put the related markup and invoke cells from views by:

``` ruby

= render_cell :articles, :top_five

```

<p>Another great thing about cells is that you can inject a dependency: </p>

``` ruby
= render_cell :widgets, :newsletter, newsletter_form: @newsletter_form 
```

<p>You can easily create a widget with newsletter submission form with enabled remote: true option and then render error messages or notice message that the email has been submitted.</p>


<h3>Helpers</h3>

<p>In most cases I use helpers to extract some things that aren't related to any particular model - rendering flash messages, titles, html templates etc., so nothing really fancy. Everything else should be extracted to the presenters/decorators. The good example of helper is the following:</p>


``` ruby
def section_marker(text)
  content_tag(:h2, class: "section-marker") do
    "<i class='icon-align-left'></i> #{text}".html_safe
  end
end
```

<p>Before each section I had to insert header with nested icon and some text, so instead of writing the same thing several times, I extracted it to a helper, which is much cleaner. It doesn't belong to any model, so helper is a good place to put this kind of code. If you use Boostrap a lot, you may consider writing <code>modal_activator</code> method:</p>

```ruby
def modal_activator(text, path, options)
  link_to(text, path, options.merge(role: "button", "data-toggle" => "modal"))
end
```

<h3>Presenters/Decorators</h3>

<p>Helpers aren't the best place to extract logic related to models - the code in helpers tends to be messy and difficult to maintain and test. The good solution would be to use Presenters - objects that encapsulate presentation logic in a neat way. There's a gem that is perfect for this kind of problems: Draper. Just create a decorator class, like <code>UserDecorator</code>: </p>

``` ruby
class UserDecorator < Draper::Base

  delegate_all
  decorates :user

  def link_to_edit
    h.link_to("Edit", user_path(model))
  end

  def full_name
    if model.name.present? and model.surname.present?
      "#{model.name} #{model.surname}"
    end
  end

  def display
    full_name || model.email
  end

end

```

<p>Looks great! You don't have to keep presentation logic in helpers or even worse in models.
You have an access to Rails helpers via h, also all method calls are delegated to model if it isn't implemented in a decorator. To decorate model just use <code>decorate</code> method:</p>

``` ruby
@user = User.find(params[:id]).decorate
```

<p>You can also decorate collection by using <code>decorate</code> method.</p>


<h3>Forms</h3>

<p>Imagine a situation where you need a form concerning more than one model. Also, some conditional validation is required. What would you do? Probably use nested attributes and add some complex validations, which would make model messy and maybe cause some bugs. There's much better way to do it: use form object and Reform gem. Then you can create following objects:</p>

``` ruby
require 'reform/form/coercion'
require 'reform/rails'

class UserRegistrationForm < Reform::Form

  include DSL
  include Reform::Form::ActiveRecord
  include Reform::Form::Coercion

  properties [:email, :name, :country_id],  on: :user
  property :birth_date,        on: :user_profile, type: Date
  properties [:age, :photo],   on: :user_profile
  
  validates :email, :photo, :birth_date, :name, :age, presence: true
  validates :age, numericality: true
  validates :email, uniqueness: { case_sensitive: false }

  model :user

  def countries_collection
    Country.all.pluck(:id, :name)
  end

  def persist!(params)
    if validate(params)
      begin
        save do |data, map|
          UserRegistration.new.register!(
            User.new(map[:user]),
            UserProfile.new(map[:user_profile])
          )
        end
      rescue UserRegistration::RegistrationFailed
        false
      end
    end
  end

end

```

<p>By using Reform gem, you can easily create clean form objects, which would deal with validations, coercions (thanks to Virtus) and persisting data concerning multiple models. Also, you can put some form interface logic here - consider <code>countries_collection</code> method: instead of passing: <code>collection: Country.all.pluck(:id, :name)</code> to the select field, you can just pass <code>form_object.countries_collection</code>. This example is trivial, but if you had some filtering and ordering logic needed to display collection, then it would be great way to keep everything clean. Using form objects doesn't change control-flow in controllers:</p>

``` ruby
class UsersController < ApplicationController

  def new
    @registration = registration_form
  end

  def create
    @registration = registration_form

    if @registration.persist!(user_params)
      redirect_to root_path
    else
      render :new
    end
  end

  private

    def registration_form
      UserRegistrationForm.new(user: User.new, user_profile: UserProfile.new)
    end

    def user_params
      params.require(:user).permit!
    end

  
end
```

<p>Form objects are also great way to extract search forms and logic related to filtering. Reform can deal with <code>has_many</code> associations and nested collections, so it is pretty powerful. However, there are some cases where you would still want to use <code>accepts_nested_attributes_for</code> - when you need funcionality provided by nested_form gem. It is not really clean to use <code>accepts_nested_attributes_for</code> macro, but the benefits are great. In other cases, form object is a way to go.</p>

<h3>Uploaders</h3>

<p>For file uploading I use Carrierwave where the uploaders' configuration is kept in the /uploaders directory. That's a really good approach, because thumb-processing strategy etc. has nothing to do with ActiveRecord model, so there's no reason to keep this kind of information there. Here is an example of general uploader:</p>

``` ruby
class ApplicationUploader < CarrierWave::Uploader::Base

  include CarrierWave::MiniMagick

  storage :file

  CarrierWave::SanitizedFile.sanitize_regexp = /[^[:word:]\.\-\+]/

  def store_dir
    "system/#{Rails.env}/#{model.class.to_s.underscore}/#{mounted_as}/#{model.id}"
  end
  
  def extension_white_list
    %w(jpg jpeg gif png pdf tiff tif eps bmp ps)
  end

  private

    def rgbify
      begin
        manipulate! do |img|  
          img.colorspace "sRGB"
          img
        end
      end
    end

end

```

<p>And example of some images uploader:</p>

``` ruby

class LogoUploader < ApplicationUploader


  def filename
    "original.#{model.logo.file.extension}" if original_filename
  end

  version :thumb do
    process :rgbify
    process :resize_to_fill => [100, 100]
    process :convert => 'jpg'
    def full_filename(for_file)
      "thumb.jpg"
    end
  end

end

```

<p>Looks great and doesn't clutter models with unrelated image-processing configuration options.</p>

<h3>Services</h3>

<p>You may expect that in /services directory so called service-objects would be placed. Well, not really. I prefer to call them (service objects) usecases and in /services I put some wrappers concerning third party APIs. In one application I've been working on, I had to deal with Google Calendar integration and the adapter layer for performing requests to GC was a service, for instance:</p>

``` ruby

module GoogleCalendar
  class Calendars

    attr_reader :client
    def initialize(client)
      @client = client
    end

    #some other methods

    def patch(calendar_id, calendar_data)
      client.execute(api_method: client.service.calendars.patch), body: calendar_data,
        parameters: { "calendarId" => calendar_id }, headers: {'Content-Type' => 'application/json'})      
    end

  end  
end

```

<p>In smaller applications you won't probably need this layer, otherwise it is a neat way to separate services from the rest of the application.</p>


<h3>Usecases</h3>

<p>This is a place where most of the business logic should be extracted - almost everything that would be in models, according to "skinny controllers, far models". The benefits of using usecase objects / service objects are great - they area easy to undestand and maintain, testing is simple and don't lead to unexpected actions (like the ones I pointed out in callbacks). Let's take a look again at the user registration process from form object, the implementation of <code>UserRegistration</code> could be following:</p>

``` ruby

class UserRegistration
  
  attr_reader :admin_notifier, :external_service_notifier
  def initialize(notifiers = {})
    @admin_notifier = notifiers.fetch(:admin_notifier) { AdminNotifier.new }
    @external_service_notifier = notifiers.fetch(:external_service_notifier) { ExternalServiceNotifier.new }
  end

  def register!(user, profile)
    ActiveRecord::Base.transaction do
      begin
        user.save!
        profile.save!(user: user)
      rescue
        raise UserRegistration::RegistrationFailed
      end
    end
    notify_admin
    notify_external_service
  end

  def notify_admin
    admin_notifier.notify(user)
  end

  def notify_external_service
    external_service_notifier.new_user(user, profile)
  end


  class RegistrationFailed < Exception 
  end

end

```

<p>Let's discuss some design choices here: in the constructor I added a possibility to inject some notifiers and provide reasonable defaults using <code>Hash#fetch</code> method to avoid nils. In <code>register</code> method I wrap the persistence process in <code>ActiveRecord::Base.transaction</code>, to ensure that user is not created without the profile if any error occurs (notice the bang methods), if it fails, the exception is raised. Then, some notifiers are called, one is a mailer, the other one connects with an external service and does some stuff. They should be executed asynchronously, in Delayed Job, Resque or Sidekiq to make sure they are completed if failure occurs - there might be a temporary problem with connecting to Gmail, Facebook, Twitter etc. but it's not a reason for an entire registration process to fail.</p>


<h3>Policies</h3>

<p>Policy objects are a bit special - it's a decorator, but Draper decorators are not the best place to put them, because they concern presentation logic. Models, except small applications, are also wrong place to write policy logic as they encapsulate important domain logic which can be quite complex. So it is a good idea to create separate objects - policy objects. Depending on the size of your application, you may have several policy objects or just one for a model, here is an example:</p>

``` ruby

class InvestmentPromotionPolicy

  attr_reader :investment, :clock
  def initialize(investment, clock = DateTime)
    @investment = investment
    @clock = clock
  end

  def promoted?
    valid_promotion_date? and owner_promotable?
  end

  def owner_promotable?
    investment.owner.active_for_promotion?
  end

  def promotion_status
    case
    when promoted?
      :promoted
    when valid_promotion_date? and !owner_promotable?
      :pending_for_promotion
    else
      :not_promoted
    end
  end

  private

    def valid_promotion_date?
      (investment.promotion_starts_at..investment.promotion_ends_at).cover? clock.now
    end

end

```

<p>In the constructor I pass an investment and the clock, which by default is <code>DateTime</code>. I had some issues with concept of time, especially in policy objects where I had to implement own <code>Clock</code>, because <code>DateTime</code> was not sufficient, so just to be on a safe side, I add a possibility for a dependency injection. It doesn't increase a complexity of the class and I wouldn't consider it as a premature optimization. Then we have some methods that encapsulate promotion logic and one that returns proper status. You will probably use policy objects in many cases - e.g. <code>promotion_status</code> method looks like it could be used in a presenter, which would display proper content, depending on the returned status and the <code>promoted?</code> method could be used in the usecases or in a model class method that would return promoted investments. You can use policy objects in many ways: inject into a model and delegate method calls:</p>

``` ruby

class Investment < ActiveRecord::Base

  delegate :promoted?, :owner_promotable?, :promotion_status to: :promotion_policy

  # some methods

  private

    def promotion_policy
      @promotion_policy ||= InvestmentPromotionPolicy.new(self)
    end

end

```

<p>In the same way you can use them in presenters if you don't want to keep it in the model layer. They can also be injected as a dependency into a usecase. Choose whatever suits you better and the complexity of the application.</p>

<h3>Value objects</h3>

<p>In many applications you may encounter a situation where a concept deserves own abstraction and whose equality isn't based on identity but on the value, some examples would be Ruby's <code>Date</code> or <code>Money</code> concept, typical for e-commerce applications. Extraction to a value object (or domain model) is a great convenience. Imagine a situation where you have a hierarchy of roles of users - you will probably want to compare the roles if one is "greater" than another to decide, if some action can be performed - the <code>RoleRank</code> would solve this problem:</p>

``` ruby

class RoleRank
  
  include Comparable

  ROLES = %w(superadmin admin junior_admin user guest)

  attr_reader :value
  def initialize(role)
    check_role_existence(role)
    @value = value
  end

  def <=>(other_role)
    ROLES.index(other_role.value) < ROLES.index(value)
  end

  def to_s
    value
  end

  class InvalidRole < Exception
  end

  private

    def check_role_existence(specified_role)
      unless ROLES.include? specified_role
        raise RoleRank::InvalidRole, "Specified Role Doesn't Exist"
      end
    end

end

```

<p>Looks great. The <code>Comparable</code> module and <code><=></code> takes care of implementing comparison operators. You can add a method with ranked role to the user model: </p>

``` ruby
class User < ActiveRecord::Base

  def role
    @role ||= RoleRank.new(permission_level)
  end

end
```

<p>and then compare users' roles:</p>

``` ruby
user = User.new(permission_level: "superadmin")
other_user = User.new(permission_level: "admin")
user.role > other_user.role => true
```
<h3>What about Observers and Concerns?</h3>

<p>There are two more ways to extract logic "the standard way": observers (removed from Rails 4) and concerns. Observers aren't really different from callbacks, except they are more difficult to deal with - you will probably forget that you've used them and debugging or following the application logic would be even harder than in callbacks and I'm glad they were removed. And the new thing in Rails 4: concerns. They are great, expecially for shared behaviour. When you need to parameterize field name in several models, you can extract it to a module in concerns, and then include Parameterizable concern, some custom finders and factory methods also can be extracted into concerns. If you use the same before_filters in more than controller, extracting them to the concerns would be a good idea. In Presenters, such concern as <code>Presenters::Publishable</code> would be beneficial when you have articles, posts and some other models that act in a similar way, so introducing concerns and encouragement to extract similar behaviour was definitely a good idea.</p>

<h3>Any other application layers?</h3>

<p>Depending on your application, you may introduce additional layers like JSON representations of models, jobs that should be done in a background or XML importers, but they can be considered as presentation logic (jsons) or usecases / services (importers, background jobs). If XML importers are important part of your business logic, then maybe extracting them from usecases and treating in a special way would be beneficial.</p>

<h2>Wrapping up</h3>

<p>The concepts mentioned here might not be popular among some developers and be considered as over-engineering. When writing simple CMS, introducing services, form objects etc. probably is a premature optimization and models / contollers / helpers and maybe presenters would be sufficient, including writing business logic in ActiveRecord callbacks. But in more complex application applying some OOP techniques can save you (and other developers you work with) from a lot of problems.</p>


<h2>Further reading</h2>

<ul>
  <li><a href="http://blog.codeclimate.com/blog/2012/10/17/7-ways-to-decompose-fat-activerecord-models" target="_blank">7 Patterns to Refactor Fat ActiveRecord Models</a></li>
  <li><a href="http://samuelmullen.com/2013/05/the-problem-with-rails-callbacks/" target="_blank">The Problem With Rails Callbacks</a></li>
  <li><a href="http://blog.steveklabnik.com/posts/2011-09-06-the-secret-to-rails-oo-design" target="_blank">The Secret to Rails OO Design</a></li>
  <li><a href="http://objectsonrails.com" target="_blank">Objects On Rails</a></li>
  <li><a href="http://solnic.eu/2011/08/01/making-activerecord-models-thin.html" target="_blank">Making ActiveRecord Models Thin</a></li>
  <li><a href="http://blog.arkency.com/2013/09/services-what-they-are-and-why-we-need-them/" target="_blank">Services - what are they and why we need them?</a></li>
</ul>

<p class="meta small-p">Changelog: 09-10-2013 - Use <code>Comparable</code> module and <code><=></code> method for implementing comparison operators in RankedRole. Provide better example in <code>OrdersController</code>. Thanks <a href="http://www.reddit.com/user/yxhuvud" rel="nofollow" target="_blank">yxhuvud</a> for suggestions.</p>
