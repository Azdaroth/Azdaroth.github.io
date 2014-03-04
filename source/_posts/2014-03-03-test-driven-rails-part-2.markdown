---
layout: post
title: "Test Driven Rails - Part 2"
date: 2014-03-03 19:52
comments: true
categories: [TDD, BDD, Testing, Rails, OOP, Design Patterns]
---

<p>Last time, in <a href="http://karolgalanciak.com/blog/2014/01/04/test-driven-rails-part-1/" target="_blank">part 1</a>, I was giving some advice about testing - why to test at all, which tests are valuable and which are not, when to write acceptance tests and in what cases aim for the maximum code coverage. It brought about some serious discussion about testing ideas and if you haven't read it yet, you should probably check (<a href="http://karolgalanciak.com/blog/2014/01/04/test-driven-rails-part-1/#disqus_thread" target="_blank">it</a>) it out. Giving some general point of view about such broad topic like Test Driven Development / Behavior Driven Development is definetely not enough so I will try to apply these techniques by implementing a concrete feature. I wanted to choose some popular usecase so that most developers will have an opinion how they would approach it. In most applications you will probably need:</p>

<h2>User Registration</h2>

<p>It is quite common feature and it can be approached in many ways. The most popular is to some authentication gem, like Devise, which is the probably the safest and the fastest way. However, Devise might be an overkill for some cases or maybe you need highly customizable solution. How would you write an implementation fot that usecase then?</p>

<p>Note: the implementation below doesn't aim to be the most secure approach for that feature, it's rather for demonstration purposes. I made some non-standard design decisions for the Rails application, you may want to read one of my <a href="http://karolgalanciak.com/blog/2013/10/06/structuring-rails-applications/" target="_blank">previous posts</a> to get more details why this way of designing code might be beneficial.</p>

<h2>Specification</h2>

<p>We know that we want to implent user registration. Let's say that we want user to confirm his/her account before signing in so we will need to send some confirmation instructions. Also, let's add some admin notifications about new user being registered to make it more interesting.</p>

<p>To make it even better, let's assume that we will create both <code>User</code> and <code>UserProfile</code> during registration: <code>User</code> will have just an <code>email</code> and <code>encrypted_password</code> attributes, <code>UserProfile</code> will have <code>country</code> and <code>age</code> attributes. User will also have to accept some policy to register. If we want to have confirmation, we will also need some attributes for <code>confirmation_token</code>, confirmation date (<code>confirmed_at</code>) and let's add <code>confirmation_instructions_sent_at</code> just to know, when the instructions were sent. These are just registration-specific attributes and we won't need them in most cases so let's extract them to <code>UserRegistrationProfile</code></p>

<p>Note: when writing the implementation and the tests, the following gems were used: <code>rails (4.0.3)</code>, <code>database_cleaner (1.2.0)</code>, <code>simple_form (3.0.1)</code> with <code>country_select (1.3.1)</code>, <code>reform (0.2.4)</code>, <code>bcrypt (3.1.6)</code>, <code>rspec-rails (3.0.0.beta1)</code>, <code>factory_girl_rails (4.3.0)</code> and <code>capybara (2.2.1)</code>.</p>

<h2>Start with acceptance tests</h2>

<p>When writing new feature we should start from acceptance tests - we will make sure that the feature works from the higher level: from the user perspective and some side effects like sending emails. So the good start will be covering user creation and sending emails to an admin and to the user. Let's write some Capybara tests:</p>

``` ruby spec/features/user_registration_spec.rb

require 'spec_helper'

feature "User Registration" do

  context "when visiting new user path" do

    background do
      visit new_user_path
    end

    context "registering with valid data" do

      given(:email) { "myawesome@email.com" }

      background do
        fill_form_with_valid_data(email: email)
      end

      scenario "new user is created" do
        expect do
          register
        end.to change(User, :count).by(1)
      end

      context "notifications" do

        background do
          register
        end

        scenario "confirmation email is sent to the user" do
          expect(all_email_addresses).to include email
        end

        scenario "notification is sent to the admin" do
          expect(all_email_addresses).to include "admin@example.com"
        end

        scenario "2 emails are sent" do
          expect(all_emails.count).to eq 2
        end

      end

    end

  end

end

def fill_form_with_valid_data(args={})
  email = args.fetch(:email, "email@example.com")
  fill_in "email", with: email
  fill_in "user_password", with: "my-super-secret-password"
  fill_in "user_password_confirmation", with: "my-super-secret-password"
  fill_in "age", with: 22
  select "Poland", from: "country"
  check "policy"
end

def register
  click_button "Register"
end

```

<p>I like using some helper methods, especially in acceptance tests so I wrote <code>fill_form_with_valid_data</code> and <code>register</code> helpers - these are just some details and I don't need to know them when reading tests. There are also some helpers like <code>all_email_addresses</code> and <code>all_emails</code>, which come from the <code>MailerMacros</code>:</p>

``` ruby spec/support/mailer_macros.rb
module MailerMacros

  def last_email
    ActionMailer::Base.deliveries.last
  end

  def last_email_address
    last_email.to.join
  end

  def reset_email
    ActionMailer::Base.deliveries = []
  end

  def reset_with_delayed_job_deliveries
    ActionMailer::Base.deliveries = []
  end

  def all_emails
    ActionMailer::Base.deliveries
  end

  def all_emails_sent_count
    ActionMailer::Base.deliveries.count
  end

  def all_email_addresses
    all_emails.map(&:to).flatten
  end

end
```

<p>If you like it, just create <code>spec/support/mailer_macros.rb</code>, put the code there and in your <code>spec_helper.rb</code> insert the following lines:</p>

``` ruby spec/spec_helper.rb
config.include(MailerMacros)
config.before(:each) { reset_email }
```

<p>Also, the select with country might be not clear - the collection with countries comes from <code>country_select</code> gem.</p>

<p>We have some failing acceptance tests, it will take some time to make them all green. Now we can write some migrations:</p>

``` ruby
rails generate model User email encrypted_password
rails generate model UserProfile user_id:integer age:integer country
```
<p>We also need to add some database constraints, to ensure that users' emails are unique and fields are not null, the migrations would look like this:</p>

``` ruby

class CreateUsers < ActiveRecord::Migration
  def change
    create_table :users do |t|
      t.string :email, null: false
      t.string :encrypted_password, null: false

      t.timestamps
    end

    add_index :users, :email, unique: true
  end
end


class CreateUserProfiles < ActiveRecord::Migration
  def change
    create_table :user_profiles do |t|
      t.integer :age
      t.string :country, null: false
      t.integer :user_id, null: false

      t.timestamps
    end
    add_index :user_profiles, :user_id
  end
end


```

<p>Now we have to define some routes:</p>

``` ruby config/routes.rb

root to: "static_pages#home"

resources :users do
end 

``` 

<p>For user registration, we have REST actions: <code>new</code> and <code>create</code>. Let's also add some root page, currently just to get rid of default Rails page:</p>

``` ruby app/controllers/static_pages_controller.rb
class StaticPagesController < ApplicationController
  
  def home
    
  end

end
```

<p>But how to deal with <code>UsersController</code> and form for user registration? We have some fields that are not present in models (<code>password/password_confirmation</code> and <code>policy</code>). The popular solution would be using: <code>accepts_nested_attributes_for :profile</code> and some virtual attributes. I don't really like this solution, <code>accepts_nested_attributes_for</code> sometimes can really save a lot of time, especially with complex nested forms with <a href="https://github.com/ryanb/nested_form" target="_blank">nested_form</a> gem. But virtual attributes are quite ugly and they make models the interfaces for forms. Much better approach is to use form objects. There's a great gem for this kind of problems: <code>Reform</code> -  we will use it here.</p>

``` ruby app/controllers/users_controller.rb
class UsersController < ApplicationController
  
  def new
    @registration_form = registration_form
  end

  def create

  end


  private

    def registration_form
      UserRegistrationForm.new(user: User.new, profile: UserProfile.new)   
    end

end

```

<p>That's it for <code>UsersController</code>, we will need some views and the actual form object:</p>

``` ruby app/views/users/new.html.haml

%h1 User Registration

= simple_form_for @registration_form do |f|
  = f.input :email, label: "email"
  = f.input :country, label: "country", as: :country
  = f.input :age, label: "age"
  = f.input :password, label: "password"
  = f.input :password_confirmation, label: "password confirmation"
  = f.input :policy, label: "I accept the policy", as: :boolean
  = f.submit "Register"

```

<p>And the actual <code>UserRegistrationForm</code>:</p>

``` ruby app/forms/user_registration_form.rb

class UserRegistrationForm < Reform::Form

  include Reform::Form::ActiveRecord
  include Composition

  property :email, on: :user
  property :password, on: :nil, empty: true
  property :password_confirmation, on: :nil, empty: true
  property :age, on: :profile
  property :country, on: :profile
  property :policy, on: :nil, empty: true
  
  validates :email, presence: true, email: true, uniqueness: { case_sensitive: false }
  validates :password, presence: true, confirmation: true
  validates :age, presence: true
  validates :country, presence: true
  validates :policy, acceptance: true, presence: true

  model :user

end


```
<p>Reform is not (yet) that popular in the Rails community so some things require explanation (check also the <a href="https://github.com/apotonick/reform" target="_blank">docs</a> out). The <code>Reform::Form::ActiveRecord</code> module is for uniqueness validation and the <code>Composition</code> is for... composition - some properties are mapped to user and other to profile. There is also a mystical mapping with <code>on: :nil</code> - these are "virtual" properties like <code>password</code>, <code>password_confirmation</code> and <code>policy</code> - all properties must be mapped to a resource so just to satisfy Reform API I use <code>on: :nil</code> as a convention, also the <code>empty: true</code> option is for virtual attributes that won't be processed. And where does the email validation come from? From our custom validator, let's write some specs but before we should add /forms (and /usecases for business logic) directories to be autoloaded:</p>

``` ruby config/application.rb
config.autoload_paths += %W(#{config.root}/app/usecases)
config.autoload_paths += %W(#{config.root}/app/forms)
```

``` ruby spec/usecases/email_validator_spec.rb

require 'spec_helper'

class DummyModel

  include ActiveModel::Validations

  attr_accessor :email

  validates :email, email: true

end


describe EmailValidator do

  let(:model) { DummyModel.new }

  it "validates email format" do

    valid_emails = %w[email@example.com name.surname@email.com 
        e-mail@example.com]

    valid_emails.each do |email|
      model.email = email
      expect(model).to be_valid
    end

    invalid_emails = %w[email @email.com email.example.com 
      email@example email@example.]

    invalid_emails.each do |email|
      model.email = email
      expect(model).not_to be_valid
    end

  end

end

```

<p>You can probably come up with some more examples to cover email validation but these are sufficient cases. I've introduced <code>DummyModel</code> here to have a generic object that can be validated so the <code>ActiveModel::Validations</code> module is needed and an accessor for an email. Let's implement the actual validation:</p>

``` ruby usecases/email_validator.rb 

class EmailValidator < ActiveModel::EachValidator

  def validate_each(record, attribute, value)
    unless value =~ /\A([^@\s]+)@((?:[-a-z0-9]+\.)+[a-z]{2,})\z/i
      record.errors[attribute] << (options[:message] || "is not a valid email format")
    end
  end

end

```

<p>The regexp for email validation comes from Rails guides:). It won't cover all the possibilities but the <a href="http://www.ex-parrot.com/pdw/Mail-RFC822-Address.html" target="_blank">actual format</a> of the email is an overkill.</p>

<p>I don't fell the need to write tests for other validations and composition for <code>UserRegistrationForm</code>: it's just using very descriptive DSL, the validation are already tested in Rails.</p>

<p>We haven't set up the associations yet in models:</p>

``` ruby app/models/user.rb
class User < ActiveRecord::Base

  has_one :profile, class_name: "UserProfile", inverse_of: :user

  validates :email, presence: true, uniqueness: { case_insensitive: false }, email: true
  validates :encrypted_password, presence: true

```

``` ruby app/models/user_profile.rb
class UserProfile < ActiveRecord::Base

  belongs_to :user, inverse_of: :profile

  validates :user, :country, :age, presence: true

end

```

<p>I added also validations in models. These may seem like a duplication because form object already implements them but these are validations always applicable do these models so it is a good idea to have them in models.</p>

<p>Let's concentrate on <code>UsersController</code> and <code>create</code> action. I don't really like testing controllers, especially for CRUD-like stuff, user creation still feels like CRUD but not that typical in Rails, especially when using dedicated form object. So let's test drive registration process: we are going to use <code>UserRegistrationForm</code> for data aggregation and validation - if the data is valid, the user will be created by <code>UserRegistration</code> service object with redirection to root path, otherwise it will render <code>new</code> template.</p>

``` ruby spec/controllers/users_controller_spec.rb

require 'spec_helper'

describe UsersController do

  describe "#create" do

    let(:registration_form) { instance_double(UserRegistrationForm) }

    let(:user_params) { { "email" => "email@example.com" } }
    let(:params) { { user: user_params } }

    let(:user_registration) { instance_double(UserRegistration) }
  
    before(:each) do
      allow(UserRegistrationForm).to receive(:new) { registration_form }
      allow(registration_form).to receive(:assign_attributes)
        .with(user_params) { registration_form }
      allow(user_registration).to receive(:register!)
        .with(registration_form) { true }
      allow(UserRegistration).to receive(:new) { user_registration }        
    end

    context "valid data" do

      before(:each) do
        expect(registration_form).to receive(:valid?) { true }
        post :create, params  
      end

      it "executes registration" do
        expect(user_registration).to have_received(:register!).with(registration_form)
      end

      it "redirects to root path" do
        expect(response).to redirect_to root_path
      end

    end

    context "invalid data" do

      before(:each) do
        expect(registration_form).to receive(:valid?) { false }
        post :create, params  
      end

      it "renders registration form" do
        expect(response).to render_template :new
      end

    end

  end

end


```
<p>Well, it is not really clear, that's the problem with testing controllers and they should be as thin as possible. We need to implement the <code>assign_attributes</code>
 method in form object to fill models' attributes with params and implement the actual <code>UserRegistration</code> usecase. In tests I use <code>instance_double</code> 
 instead of simple <code>double</code> to make sure I'm not stubbing non-existent methods or with wrong number of arguments - that's a great feature introduced in RSpec 3, which comes from <a href="https://github.com/xaviershay/rspec-fire" target="_blank">rspec-fire</a> gem. Also, I'm stubbing responses so that I can spy on them using <code>have_received</code> method - It's much cleaner and easier to read. Compare these two examples:</p>

``` ruby

before(:each) do
  expect(registration_form).to receive(:valid?) { true }
  post :create, params  
end

it "executes registration" do
  expect(user_registration).to have_received(:register!).with(registration_form)
end

it "redirects to root path" do
  expect(response).to redirect_to root_path
end

```
<p>and</p>

``` ruby

before(:each) do
  expect(registration_form).to receive(:valid?) { true }
end

it "executes registration" do
  expect(user_registration).to receive(:register!).with(registration_form)
  post :create, params 
end

it "redirects to root path" do
  post :create, params 
  expect(response).to redirect_to root_path
end

```

<p>I really encourage you to spy on a stubbed method, I will make your tests much more readable and DRY them up.</p>

<p> I made also some non-standard design decisions here: why not to implement the persistence logic in the form object and use it like:</p>

``` ruby
if @registration_form.persist(user_params) # populate data, perform validation and persist data if is valid
  # happy paths
else
  # failure path
end
```

<p>For simple persistence logic I would probably go with that approach but we will also need to send some confirmation instructions, admin notifications etc., I'm not really comfortable with the idea of form object knowing something about sending notifications, persistence alone would be ok, it would be quite convenient to use but this is too complex, I would leave form object for data aggregation and validation. Let's write code for the controller:</p>

``` ruby app/controllers/users_controller.rb

class UsersController < ApplicationController

  def create
    @registration_form = registration_form.assign_attributes(params[:user])
  
    if @registration_form.valid?
      UserRegistration.new.register!(@registration_form)
      redirect_to root_path, notice: "You have register. Please, check your email for confimartion instructions"
    else
      render :new
    end

  end

  private

    def registration_form
      UserRegistrationForm.new(user: User.new, profile: UserProfile.new)
    end
end

```

<p>We need to implement <code>assign_attributes</code> method (we have nice failure message thanks to <code>instance_double</code> that informs us about it):</p>

``` ruby
Failure/Error: allow(registration_form).to receive(:assign_attributes)
  UserRegistrationForm does not implement:
    assign_attributes
```

<p>and UserRegistration. Let's start from test for <code>assign_attributes</code> method. It looks like, besides assigning params, it should return itself:</p>

``` ruby spec/forms/user_registration_form_spec.rb

require 'spec_helper'

describe UserRegistrationForm do

  let(:user) { User.new }
  let(:profile) { UserProfile.new }

  subject { UserRegistrationForm.new(user: user, profile: profile) }

  describe "#assign_attributes" do

    it "populates models' attributes with params" do
      subject.assign_attributes("email" => "email@example.com", "country" => "Poland")
      expect(subject.user.email).to eq "email@example.com"
      expect(subject.profile.country).to eq "Poland"
    end

    it "assigns profile to user" do
      subject.assign_attributes({})
      expect(user.profile).to eq profile
    end

    it "returns self" do
      expect(subject.assign_attributes({})).to eq subject
    end

  end

end

```


<p>And the code for implementation:</p>

``` ruby app/forms/user_registration_form.rb

def assign_attributes(params)
  from_hash(params)
  save_to_models
  self
end


```

<p>It uses some Reform::Form private methods that I found in source code so this implementation might not be stable but fortunately we have it covered in tests so we will know breaking changes if it happens in next versions. And there's a gotcha here: The keys in hash must be stringified, symbols won't work (applies to 0.2.4 version of Reform).</p>

<p>Let's write some minimal implementation for <code>UserRegistration</code> to satisfy controller's specs:</p>

``` ruby app/usecases/user_registration.rb
class UserRegistration

  def register!(aggregate)
    
  end

end

```

<p>And what the <code>UserRegistration</code> should be responsible for? Let's start with persistence logic: user with it's profile must be created and the encrypted password should be assigned to the user. We will also need registration profile to be created.</p>

``` ruby spec/usecases/user_registration_spec.rb

require 'spec_helper'

describe UserRegistration do

  let(:user) { FactoryGirl.build_stubbed(:user) }
  let(:profile) { FactoryGirl.build_stubbed(:user_profile) }

  let(:form) { double(:form, user: user, profile: profile,
    password: "password") }

  subject { UserRegistration.new(encryption: encryption) }

  let(:encrypted_password) { "encrypted_password" }

  let(:encryption) { instance_double(Encryption,
     generate_password: encrypted_password) }

  context "persistence is success" do

    before(:each) do
      allow(user).to receive(:save!) { true }
      allow(profile).to receive(:save!) { true }
      allow(user).to receive(:create_registration_profile!) { true }
    end

    before(:each) do
      subject.register!(form)
    end

    specify "user gets encrypted password" do  
      expect(user.encrypted_password).to eq encrypted_password
    end

    it "saves user" do
      expect(user).to have_received(:save!)
    end

    it "creates profile for user" do
      expect(profile).to have_received(:save!)
    end

    it "create registration profile for user" do
      expect(user).to have_received(:create_registration_profile!)
    end

  end

  context "persistence fails" do

    it "raises RegistrationFailed error" do
      allow(user).to receive(:save!) { raise_error ActiveRecord::RecordInvalid }
       expect do
        UserRegistration.new.register!(form)
      end.to raise_error UserRegistration::RegistrationFailed
    end

  end

end

```

<p>Note: keep in mind that you should write one test and then write minimal implementation to make it pass and then another test. I gave the several tests and the actual <code>UserRegistration</code> in advance, just to make it easier to read and follow.</p>

<p>It is quite clear from the tests what should be expected from this class: creation of user, profile, registration profile and assigning encrypted password. Data aggregate (<code>form</code>) is just a <code>double</code> with profile and user, we don't care what it actually is, it should just implement the stubbed interface. I also use FactoryGirl and <code>build_stubbed</code> method for initializing models - I find it more convenient than to use <code>instance_double</code> because instance doubles don't cover attributes from database tables.</p>

<p>The factories for User and profiles would look like that:</p>

``` ruby spec/factories.rb

  FactoryGirl.define do

  factory :user do
    email "email@example.com"
    # I'll explain that later, why it is that long
    encrypted_password "$2a$10$bcMccS3q2egnNICPLYkptOoEyiUpbBI5Q.GAKe0or2QB7ij6yCeOa" 
  end

  factory :user_profile do
    age 22
    country "Poland"
  end


end

```

<p>And the actual implementation:</p>


``` ruby app/usecases/user_registration.rb

class UserRegistration

  class RegistrationFailed < StandardError ; end
    
  attr_reader :encryption
  private :encryption

  def initialize(options={})
    @encryption = options.fetch(:encryption, Encryption.new)
  end

  def register!(aggregate)
    user = aggregate.user
    profile = aggregate.profile
    user.encrypted_password = encrypted_password(aggregate.password)
    ActiveRecord::Base.transaction do
      begin
        user.save!
        profile.save!
        user.create_registration_profile!
      rescue ::ActiveRecord::StatementInvalid, ::ActiveRecord::RecordInvalid => e
        raise_registration_error(e)
      end
    end  
  end

  private

    def raise_registration_error(errors)
      message =  "Registration Failed due to the following errors: #{errors}"      
      raise UserRegistration::RegistrationFailed, message
    end

    def encrypted_password(password)
      encryption.generate_password(password)
    end

end

```

<p>Let's discuss some design decisions: the constructor accepts options hash so that we can inject dependencies like <code>encryption</code> and to provide defaults if it's injected. The persistence logic is wrapped in transaction block so that e.g. user won't be created if profile creation fails. If it fails, <code>RegistrationFailed</code> error is raised with a descriptive message. Also, the <code>encryption</code> is private: we don't need it to be public.</p>

<p>To satisfy tests, the <code>create_registration_profile!</code> must be implemented and <code>generate_password</code> for encryption. Fortunately, we just need to setup associations for <code>UserRegistrationProfile</code> to have <code>create_registration_profile!</code> implemented. But we need to generate the model first:</p>

``` ruby
rails generate model UserRegistrationProfile confirmed_at:datetime confirmation_instructions_sent_at:datetime confirmation_token user_id:integer
```

<p>let's set up some database constraints in generated migration:</p>

``` ruby

class CreateUserRegistrationProfiles < ActiveRecord::Migration
  def change
    create_table :user_registration_profiles do |t|
      t.datetime :confirmed_at
      t.datetime :confirmation_instructions_sent_at
      t.string :confirmation_token
      t.integer :user_id, null: false

      t.timestamps
    end

    add_index :user_registration_profiles, :user_id
    add_index :user_registration_profiles, :confirmation_token, unique: true
  end
end

```

<p>and then write the associations:</p>

``` ruby app/models/user.rb

class User < ActiveRecord::Base

  has_one :registration_profile, class_name: "UserRegistrationProfile", inverse_of: :user

end

```

``` ruby app/models/user_registration_profile.rb

class UserRegistrationProfile < ActiveRecord::Base

  belongs_to :user, inverse_of: :registration_profile

  validates :user, presence: true

end


```

<p>The minimal implementation for <code>Encryption</code> to make the <code>UserRegistration</code> tests happy is the following:</p>

``` ruby app/usecases/encryption.rb

class Encryption

  def generate_password(phrase)
  end

end

```

<p>To finish the user creation we have to implement the password generation. Bcrypt and it's <code>create</code> password method is a reasonable choice here. Let's write the tests:</p>

``` ruby spec/usecases/encryption_spec.rb

require 'spec_helper'

describe Encryption do

  subject { Encryption.new }

  let(:password) { "password" }
  let(:encypted_password) { "$2a$10$vI8aWBnW3fID.ZQ4/zo1G.q1lRps.9cGLcZEiGDMVr5yUP1KUOYTa" }
  let(:password_generator) { class_double(BCrypt::Password).as_stubbed_const }

  before(:each) do
    allow(password_generator).to receive(:create).with(password) { encypted_password }
  end

  it "creates password using Bcrypt as default" do
    expect(subject.generate_password(password)).to eq encypted_password
  end

end

```

<p>The <code>encrypted_password</code> doesn't have to be that long but looks more genuine that way. The BCrypt::Password is also a class double so that we make sure we don't stub a non-existent method. And the implementation of <code>Encryption</code> class:</p>

``` ruby app/usecases/encryption.rb

class Encryption
  
  attr_reader :password_generator
  private :password_generator

  def initialize(args={})
    @password_generator = args.fetch(:password_generator, BCrypt::Password)
  end

  def generate_password(phrase)
    password_generator.create(phrase)
  end

end

```

<p>The pattern for constructor is similar to the one from <code>UserRegistration</code>. The <code>password_generator</code> is also made private - the rule of thumb is that everything should be private unless it needs to be public, just to keep the interfaces clean.</p>

<p>Now we have the basic implementation for user creation with it's profiles. Still, we need confirmation stuff and notification to tje admin. It is beyond the <code>UserRegistration</code> responsibilities, we also don't need always to a notification or confirmation instructions or to confirm user at all, just to have the interface flexible enough. Maybe we will have some additional things that will take place during registration - like third party API notification. To keep the responsibilities separate and <code>UserRegistration</code> easy to use, we can implement all the additional actions as the listeners that are being passed to the constructor of <code>UserRegistration</code>. Let's write specs for it first:</p>

``` ruby spec/usecases/user_registration_spec.rb

require 'spec_helper'

describe UserRegistration do

  # same code a before
  
  context "persistence is success" do

    # same code a before

    # and this is new:

    context "with listeners" do

      let(:user_confirmation) { double(:user_confirmation, 
        notify: true) }
      let(:admin_notification) { double(:admin_notification,
        notify: true) }

      before(:each) do
        UserRegistration.new(user_confirmation, admin_notification,
          encryption: encryption).register!(form)
      end

      it "notifies user_confirmation listener" do
        expect(user_confirmation).to have_received(:notify).with(user)
      end

      it "notifies admin_notificaiton listener" do
        expect(admin_notification).to have_received(:notify).with(user)
      end

    end

  end

end


```

<p>We don't actually care what the listeners are, the only requirement is that they must implement the same interface: <code>notify</code> method which takes <code>user</code> argument. And the implementation:</p>


``` ruby app/usecases/user_registration.rb

class UserRegistration

  class RegistrationFailed < StandardError ; end
    
  attr_reader :encryption, :listeners
  private :encryption, :listeners

  def initialize(*listeners, **options)
    @listeners = listeners
    @encryption = options.fetch(:encryption, Encryption.new)
  end

  def register!(aggregate)
    user = aggregate.user
    profile = aggregate.profile
    user.encrypted_password = encrypted_password(aggregate.password)
    ActiveRecord::Base.transaction do
      begin
        user.save!
        profile.save!
        user.create_registration_profile!
      rescue ::ActiveRecord::StatementInvalid, ::ActiveRecord::RecordInvalid => e
        raise_registration_error(e)
      end
    end  
    notify_listeners(user)
  end

  private

    def raise_registration_error(errors)
      message =  "Registration Failed due to the following errors: #{errors}"      
      raise UserRegistration::RegistrationFailed, message
    end

    def encrypted_password(password)
      encryption.generate_password(password)
    end

    def notify_listeners(user)
      listeners.each do |listener|
        listener.notify(user)
      end
    end


end


```

<p>These changes are not that noticeable but they are huge. The constructor now takes some listeners (splat) - we can pass one listener, several or none, it will always be an array. Also, the options is now a keyword argument introduced in Ruby 2.0 which makes the changes really smooth. And the new method: <code>notify_listeners</code> which sends <code>notify</code> message to all the listeners with <code>user</code> argument.</p>

<p>To handle the user confirmation stuff we will need, well, <code>UserConfirmation</code> and <code>UserRegistrationAdminNotification</code> to handle the notifcations.</p>

<p>Let's start with <code>UserConfirmation</code>. We need <code>notify</code> method which will take care of: assigning confirmation token, which must be unique, setting date when the confirmation instructions were sent and sending the instructions. We will need some mailer here (<code>UserConfirmationMailer</code>), clock (<code>DateTime</code>) and something to generate token - <code>SecureRandom</code> will be a good fit here with it's <code>base64</code> method. Let's translate the specification to the tests:</p>

``` ruby spec/factories.rb

FactoryGirl.define do

  # same as before

  factory :user_registration_profile do # this in new here
    
  end

end

```

``` ruby spec/usecases/user_confirmation_spec.rb

require 'spec_helper'

describe UserConfirmation do

  describe "#notify" do

    let!(:user) { FactoryGirl.build_stubbed(:user, 
      registration_profile: FactoryGirl.build_stubbed(:user_registration_profile)) }

    let(:mailer_stub) { double(:mailer, deliver: true) }

    let!(:mailer) { class_double(UserConfirmationMailer,
      send_confirmation_instructions: mailer_stub).as_stubbed_const }

    let(:confirmation_instructions_sent_date) { DateTime.new(2014, 2, 23, 21, 0, 0)}
    let(:clock) { double(:clock, now: confirmation_instructions_sent_date) }

    subject { UserConfirmation.new(mailer: mailer, clock: clock) }

    before(:each) do
      allow(user).to receive(:save_with_profiles!)
      allow(SecureRandom).to receive(:base64) { "token" }
      subject.notify(user)
    end

    it "assigns confirmation token to user" do
      expect(user.confirmation_token).to eq "token"
    end

    it "sends email with confirmation instructions" do
      expect(mailer).to have_received(:send_confirmation_instructions).with(user)
    end

    it "sets date when the confirmation instructions have been sent" do
      expect(user.confirmation_instructions_sent_at).to eq confirmation_instructions_sent_date
    end

    it "persists new data" do
      expect(user).to have_received(:save_with_profiles!)
    end
    
  end

end

```

<p>Like before, we should start with one test, make it pass and then write the next one. Here is the implementation for it:</p>

``` ruby app/usecases/user_confirmation.rb

class UserConfirmation

  attr_reader :mailer, :clock
  private :mailer, :clock

  def initialize(args={})
    @mailer = args.fetch(:mailer, UserConfirmationMailer)
    @clock = args.fetch(:clock, DateTime)
  end

  def notify(user)
    assign_confirmation_token(user)
    user.confirmation_instructions_sent_at = clock.now
    mailer.send_confirmation_instructions(user).deliver
    user.save_with_profiles!
  end

  private

    def assign_confirmation_token(user)
      begin
        user.confirmation_token = SecureRandom.base64(20)
      end while User.find_by_confirmation_token(user.confirmation_token).present?
    end
  
end


```

<p>The pattern for constructor is similar to the previous ones: provide the way to inject dependencies and some defaults if they are not specified so it is more flexible, less coupled and the testing becomes easier as a bonus. We have while loop to ensure the confirmation token is unique amongst users. The <code>find_by_attribute</code> methods are deprecated since Rails 4.0.0 and the <code>activerecord-deprecated_finders</code> will be removed from dependencies in 4.1.0 so we have to implement our own finder method. Here are also some important design decisions - we assign both <code>confirmation_instructions_sent_at</code> and <code>confirmation_token</code> to the user, not the registration profile. How is that? The important question is: do we need to expose that the user has registration profile? What if we change our mind and decide to put this data in "normal" profile, not registration profile? Or we didn't make a decision to create a registration profile at all in a first place and these attributes belonged to the user since the beginning and we later decided to move them to a separated table? From the <code>UserConfirmation</code> perspective, it is just an implementation detail. The <code>save_with_profiles!</code> is provided to make user's data persistence more convenient. We need to implement mailer as well but let's start with user's related stuff.</p>

``` ruby spec/models/user.rb

require 'spec_helper'

describe User do

  subject { User.new(email: "email@example.com",
    encrypted_password: "password") }

  describe ".find_by_confirmation_token" do

    let!(:user) { FactoryGirl.create(:user) }

    before(:each) do
      FactoryGirl.create(:user_registration_profile,
        confirmation_token: "token", user_id: user.id)
    end

    it "finds user with specified confirmation token" do
      expect(User.find_by_confirmation_token("token")).to eq user
    end

  end

  describe "#confirmation_token=" do

    it "assigns confirmation token to user" do
      subject.confirmation_token = "token"
      expect(subject.confirmation_token).to eq "token"
    end

  end

  describe "#confirmation_instructions_sent_at=" do

    it "assigns confirmation instructions sent date to user" do
      date = DateTime.now
      subject.confirmation_instructions_sent_at = date
      expect(subject.confirmation_instructions_sent_at).to eq date
    end

  end

end


```

<p>The <code>find_by_confirmation_token</code> finder method is pretty easy but it involves another table with registration profile so I decided to write test for it. The tests also suggest that we need readers for these attributes, not only the writers. Let's use <code>delegate</code> macro from ActiveSupport for it:</p>

``` ruby app/models/user.rb

class User < ActiveRecord::Base

  # the same code as before

  # new code

  delegate :confirmation_token, :confirmation_instructions_sent_at, :confirmed_at,
     to: :registration_profile, allow_nil: true

  def self.find_by_confirmation_token(token)
    joins(:registration_profile)
      .where("user_registration_profiles.confirmation_token = ?", token)
      .first
  end

  def confirmation_token=(token)
    ensure_registration_profile_exists
    registration_profile.confirmation_token = token
  end

  def confirmation_instructions_sent_at=(date)
    ensure_registration_profile_exists
    registration_profile.confirmation_instructions_sent_at = date
  end

  def save_with_profiles!
    User.transaction do
      save!
      profile.save! if profile
      registration_profile.save! if registration_profile
    end
  end

  private

    def ensure_registration_profile_exists
      build_registration_profile if registration_profile.blank?
    end

```

<p>Before making any assignment, we have to make sure that the registration profile exists. The same applies to the persistence, which is again wrapped in a transaction. And let's implement the mailer for sending confirmation instructions:</p>

``` ruby
rails generate mailer UserConfirmationMailer send_confirmation_instructions
```

<p>Some basic tests to prove that the mailer actually works:</p>

``` ruby spec/mailers/user_confirmation_mailer_spec.rb

require "spec_helper"

describe UserConfirmationMailer do

  describe "#send_confirmation_instructions" do

    let!(:user) { FactoryGirl.build_stubbed(:user, email: "email@example.com",
      registration_profile: FactoryGirl.build_stubbed(:user_registration_profile,
      confirmation_token: "token"))
    }

    let(:mail) { UserConfirmationMailer.send_confirmation_instructions(user) }

    it "has proper subject" do
      expect(mail.subject).to eq("Confirmation Instructions")
    end

    it "sends email to the user" do
      expect(mail.to).to eq([user.email])
    end

    it "has link to confirm account" do
      url = "/confirmations/#{user.confirmation_token}"
      expect(mail.body.encoded).to match(url)
    end
  end

end

```

<p>The setup with FactoryGirl may seem to be complex but I like doing this kind of setup manually, not to rely on predefined attributes for the factory so that I know where the data comes from. We also assume that there will be some controller action for confirmations so we will need to define routes to make the tests pass:</p>

``` ruby app/mailers/user_confirmation_mailer.rb

  class UserConfirmationMailer < ActionMailer::Base

  default from: "contact@email.com"

  def send_confirmation_instructions(user)
    @user = user
    mail(to: user.email, subject: "Confirmation Instructions")
  end

end

```


``` html app/views/user_confirmation_mailer/send_confirmation_instructions.html.erb

<p>To complete the registration process, click the link below:</p>
<%= link_to "Confirm", user_confirmation_path(token: @user.confirmation_token) %>

```

<p>And the route with a controller action:</p>

``` ruby config/routes.rb

  get '/confirmations/:token', to: "confirmations#confirm", as: :user_confirmation

```

``` ruby app/controllers/confirmations_controller.rb


class ConfirmationsController < ApplicationController
  
  def confirm

  end

end

```

<p>And add the listener in <code>UsersController</code>:</p>

``` ruby app/controllers/users_controller.rb

  def create
    @registration_form = registration_form.assign_attributes(params[:user])
  
    if @registration_form.valid?
      UserRegistration.new(
        UserConfirmation.new
      ).register!(@registration_form)
      redirect_to root_path, notice: "You have register. Please, check your email for confimartion instructions"
    else
      render :new
    end

  end


  private

    def registration_form
      UserRegistrationForm.new(user: User.new, profile: UserProfile.new)   
    end



```

<p>To make all the tests happy, we need some to send a notification to the admin. It looks like <code>UserRegistrationAdminNotification</code> will be just an adapter layer for <code>NewUserAdminNotificationMailer</code> to provide the listener interface. The tests and the implementation are quite simple:</p>

``` ruby spec/usecases/user_registration_admin_notification_spec.rb

require 'spec_helper'

describe UserRegistrationAdminNotification do

  describe "#notify" do

    let!(:user) { FactoryGirl.build_stubbed(:user) }

    let(:mailer_stub) { double(:mailer, deliver: true) }

    let!(:mailer) { class_double(NewUserAdminNotificationMailer,
      notify: mailer_stub).as_stubbed_const }

    subject { UserRegistrationAdminNotification.new(mailer: mailer) }

    before(:each) do
      subject.notify(user)
    end

    it "sends email to admin about new user being registered" do
      expect(mailer).to have_received(:notify).with(user)
    end
    
  end
  
end


```

<p>The implementation:</p>

``` ruby app/usecases/user_registration_admin_notification.rb

class UserRegistrationAdminNotification
  
  attr_reader :mailer
  private :mailer

  def initialize(args={})
    @mailer = args.fetch(:mailer, NewUserAdminNotificationMailer)
  end

  def notify(user)
    mailer.notify(user).deliver
  end

end

```

<p>We also need to generate the mailer with <code>notify</code> method (yes, the same as for the listener but it is good enough here):</p>

``` ruby
rails generate mailer NewUserAdminNotificationMailer notify
```

<p>and the simple implementation to make the tests green:</p>

``` ruby app/mailers/new_user_admin_notification_mailer.rb

class NewUserAdminNotificationMailer < ActionMailer::Base
  
  default from: "contact@email.com"
  
  def notify(user)
    @user = user
    mail(to: "admin@example.com", subject: "New User Registration")
  end
end


``` 

<p>Now the tests for the mailer and we are almost finished with the registration:</p>

``` ruby spec/mailers/new_user_admin_notification_mailer_spec.rb


require "spec_helper"

describe NewUserAdminNotificationMailer do

  describe "#notify" do

    let!(:user) { FactoryGirl.build_stubbed(:user, email: "email@example.com") }

    let(:mail) { NewUserAdminNotificationMailer.notify(user) }

    it "sends email to the admin" do
      expect(mail.to).to eq(["admin@example.com"])
    end

    it "has link to confimartion in the body" do
      expect(mail.body.encoded).to match(user.email)
    end
  end

end


```


<p>The views for the mailer:</p>

``` ruby app/views/new_user_admin_notification_mailer/notify.html.erb

<p>New user with email: <%= @user.email %> has registered</p>

```

<p>And the listener for <code>UserRegistrationAdminNotification</code> in <code>UserRegistrationAdminNotification.new</code>:</p>

``` ruby app/controllers/users_controller.rb

  def create
    @registration_form = registration_form.assign_attributes(params[:user])
  
    if @registration_form.valid?
      UserRegistration.new(
        UserConfirmation.new,
        UserRegistrationAdminNotification.new
      ).register!(@registration_form)
      redirect_to root_path, notice: "You have register. Please, check your email for confimartion instructions"
    else
      render :new
    end

  end


  private

    def registration_form
      UserRegistrationForm.new(user: User.new, profile: UserProfile.new)   
    end


```

<p>Hell yeah, all tests are happy now, we have completed the user registration feature. Let's add account confirmation feature and simple sign in. We don't need acceptance test or integration test in controller for that feature, it's pretty simple and unit test for controller would be enough. We probably need to find user by confirmation token, confirm the account and redirect to some page. Also, we should return 404 error if there's no match for confirmation token. In a real world application it would probably need some expiration date for token and other features but keep in a mind it's just for demonstration purposes, not writing the complete devise-like solution.</p>

``` ruby spec/controllers/confirmations_controller_spec.rb

require 'spec_helper'

describe ConfirmationsController do
  
  describe "#confirm" do

    let!(:user) { FactoryGirl.build_stubbed(:user,
      registration_profile: FactoryGirl.build_stubbed(:user_registration_profile,
        confirmation_token: "token")) }
    let(:factory) { class_double(User).as_stubbed_const }

    before(:each) do
      allow(factory).to receive(:find_by_confirmation_token!)
        .with(user.confirmation_token) { user }
    end

    it "it confirms user and redirects to root path" do
      expect(user).to receive(:confirm!) { true }
      get :confirm, token: user.confirmation_token
      expect(response).to redirect_to root_path
    end

  end

end

```

<p>We find the user with bang method so, by convention, it raises ActiveRecord::RecordNotFound if the resource is not found - we won't write test for the failure path. Then the  <code>confirm!</code> method is used which needs to be implemented and redirect to root path. The implementation for the controller is the following:</p> 

``` ruby app/controllers/confirmations_controller.rb

class ConfirmationsController < ApplicationController
  
  def confirm
    user = User.find_by_confirmation_token!(params[:token]) 
    user.confirm!
    redirect_to root_path, notice: "You have confirmed you account. Now you can login."
  end

end


```

<p>Now we need to implement <code>confirm!</code> and <code>find_by_confirmation_token!</code> methods:</p>

``` ruby spec/models/user_spec.rb

require 'spec_helper'

describe User do

  subject { User.new(email: "email@example.com",
    encrypted_password: "password") }

  # some old code

  describe "#confirm!" do

    let(:date) { DateTime.new(2014, 02, 23, 22, 6, 0) }

    before(:each) do
      allow(DateTime).to receive(:now) { date }
      subject.confirm!
    end

    it "assigns confirmation date with current date" do
      expect(subject.confirmed_at).to eq date
    end

    it "persists user and the profile" do
      expect(subject.registration_profile.persisted?).to eq true
      expect(subject.persisted?).to eq true
    end

  end

end

```

<p>It would be quite convenient to use <code>confirm!</code> method for new user and make it persisted. I don't feel a need to write test for <code>find_by_confirmation_token!</code> as it is really simple and will use <code>find_by_confirmation_token</code>.</p>

``` ruby app/models/user.rb

class User < ActiveRecord::Base

  def self.find_by_confirmation_token!(token)
    user = find_by_confirmation_token(token)
    if user.blank?
      raise ActiveRecord::RecordNotFound
    else
      user
    end
  end

  def confirm!
    ensure_profile_exists
    registration_profile.confirmed_at = DateTime.now
    save_with_profiles!
  end

  private

    def ensure_registration_profile_exists
      build_registration_profile if registration_profile.blank?
    end

end


```

<p>It's another method in <code>User</code> model, shouldn't the models be thin? Well, it's not business logic involving some complex actions, these are just domain methods for user to handle it's own state (or the profile's state which is rather an implementation detail in this case), it looks like a model's responsibility so it's a right place to add this kind of logic, much better than using e.g. <code>update</code> method on registration profile outside the models.</p>

<p>We completed another feature: user can confirm his/her account. There's only one feature left: sign in. Let's test drive it starting from acceptance test again: when the user exists and is confirmed, we let the user sign in, if exists but is not confirmed yet we render proper info and if the email/password combination is invalid we also want to display proper info. Capybara test for these specs may look like this:</p>

``` ruby spec/features/sign_in_spec.rb

require 'spec_helper'

feature "Sign In" do

  context "user is confirmed" do

    given!(:user) { FactoryGirl.create(:user, 
    registration_profile: FactoryGirl.build(:user_registration_profile,
      confirmed_at: DateTime.now)) }

    describe "with valid data" do

      background do
        visit sign_in_path
        fill_in_sign_in_form_with_valid_data(user)
        sign_in
      end

      scenario "user signs in and and shows success message" do
        expect(page).to have_content "You have successfully signed in"    
      end

      scenario "after sign in user sees it's email" do        
        expect(page).to have_content user.email  
      end

    end

    describe "with invalid data" do

      scenario "signin is prohibited and user sees error message
        with wrong email/password combination" do
        visit sign_in_path
        fill_in_sign_in_form_with_invalid_data(user)
        sign_in
        expect(page).to have_content "Wrong email/password combination"    
      end

    end

  end

  context "user is not confirmed" do

    given!(:user) { FactoryGirl.create(:user, 
    registration_profile: FactoryGirl.build(:user_registration_profile)) }

    background do
      visit sign_in_path
      fill_in_sign_in_form_with_valid_data(user)
      sign_in
    end

    scenario "signin is prohibited and user sees info about unconfirmed account" do
      expect(page).to have_content "You must confirm your account"    
    end

  end

end

def fill_in_sign_in_form_with_valid_data(user)
  fill_in "email", with: user.email
  fill_in "password", with: "password"
end

def fill_in_sign_in_form_with_invalid_data(user)
  fill_in "email", with: user.email
  fill_in "password", with: "wrong_password"
end

def sign_in
  click_button "Sign in"
end

```

<p>The structure is similar to the one from registration process: there are some helper methods for filling forms and signing in. For the happy path, we also want to verify that the user is actually signed in so we will display it's email. This test will work because in <code>User</code> factory in <code>spec/factories.rb</code> the <code>encrypted_password</code> value is an encrypted form of "password" phrase. Let's start from defining routes and creating controller for the user signin:</p>

``` ruby config/routes.rb


resources :sessions, except: [:new]

get '/sign_in', to: "sessions#new", as: :sign_in


```

``` ruby app/controllers/sessions_controller.rb


class SessionsController < ApplicationController
  
  def new
    
  end

  def create

  end


```

<p>and the view layer:</p>

``` ruby app/views/sessions/new.html.haml


= display_messages

%h1 Sign In

= simple_form_for :sign_in, url: :sessions, method: :post do |f|
  = f.input :email, label: "email"
  = f.input :password, label: "password"
  = f.submit "Sign in"

```

<p>Where does the <code>display_messages</code> helper comes from? It's a simple helper for displaying flash messages which can be implemented as follows:</p>

``` ruby app/helpers/application_helper.rb


module ApplicationHelper

  def display_messages
    case
    when flash[:notice]
      display_flash_message(flash[:notice], "alert-success")
    when flash[:error]
      display_flash_message(flash[:error], "alert-error")
    when flash[:alert]
      display_flash_message(flash[:alert], "alert-error")
    end
  end

  def display_flash_message(message, class_name)
    content_tag(:div, class: "alert centerize-text #{class_name}") do
      message
    end
  end

end


```

<p>Let's also update the root page:</p>

``` ruby app/views/static_pages/home.html.haml

= display_messages
- if current_user 
  %h1 Welcome
  = current_user.email

```
<p>Let's stick to the convention and name the helper method with current user the <code>current_user</code>. The signin process is already covered by acceptance test so we won't benefit much from writing controller's test. To keep track of current user, we will store it's id in a session. The implementation might be following:</p>

``` ruby app/controllers/sessions_controller.rb

class SessionsController < ApplicationController
  

  def create
    user = User.find_by(email: sign_in_params[:email])

    return wrong_combination_of_email_or_password if user.blank?
    return user_not_confirmed if !user.confirmed?

    if Authentication.authenticate(user.encrypted_password, sign_in_params[:password])
      sign_in(user)
      redirect_to root_path, notice: "You have successfully signed in"
    else
      wrong_combination_of_email_or_password
    end
  end


  private

    def sign_in_params
      params.require(:sign_in).permit(:email, :password)
    end

    def sign_in(user)
      session[:user_id] = user.id
    end

    def wrong_combination_of_email_or_password
      flash.now[:error] = "Wrong email/password combination"
      render :new
    end

    def user_not_confirmed
      flash.now[:error] = "You must confirm your account"
      render :new
    end

end


```

<p>And for the <code>current_user</code>:</p>

``` ruby app/controllers/application_controller.rb

class ApplicationController < ActionController::Base
  # Prevent CSRF attacks by raising an exception.
  # For APIs, you may want to use :null_session instead.
  protect_from_forgery with: :exception

  helper_method :current_user

  private

    def current_user
      @current_user ||= User.find(session[:user_id]) if session[:user_id].present?
    end
end



```

<p>The last step is to implement <code>Authentication</code> module with authenticate method, which compares encrypted password with plain password. Let's start with a test:</p>

``` ruby spec/usecases/authentication_spec.rb

require 'spec_helper'

describe Authentication do

  describe ".authenticate" do

    let(:encrypted_password) { "$2a$10$bcMccS3q2egnNICPLYkptOoEyiUpbBI5Q.GAKe0or2QB7ij6yCeOa" }

    it "returns true if encrypted password is specified password" do
      expect(Authentication.authenticate(encrypted_password,
        "password")).to eq true
    end

    it "returns false if encrypted password in not specified password" do
      expect(Authentication.authenticate(encrypted_password,
        "wrong_password")).to eq false
    end

  end
  
end


```

<p> I don't need to create an instance of <code>Authentication</code>, there is no need to make it a class. And to make all the tests green we just need to implement comparison of passwords using Bcrypt:</p>

``` ruby app/usecases/authentication.rb

module Authentication
  
  def self.authenticate(encrypted_password, password)
    BCrypt::Password.new(encrypted_password) == password
  end

end


```

<h2>Wrapping up</h2>

<p>That's all! All the tests now pass. And they run pretty fast (on Ruby 2.1.0), about 1.6 s. That was quite long: the user registration, confirmation and sign in features have been test drived and some not obvious design decisions were made. That gives some basic ideas how I apply Test Driven Development / Behavior Driven Development techniques in everyday Rails programming. The aim of these tests wasn't to have 100% coverage (e.g. I didn't test ActiveModel validations, using Reform DSL to make <code>UserRegistrationForm</code> composition, delegations in <code>User</code> model) but they give me sufficient level of confidence to assume that the application works correctly and they helped with some design choices, which is a great advantage of unit tests. When TDDing, keep in mind what Kent Beck says about his way of writing tests: 
  <blockquote>I get paid for code that works, not for tests so my philosophy is to test as little as possible to reach a given level of confidence (I suspect this level of confidence is high compared to industry standards but that could just be hubris). If I don't typically make a kind of mistake (like setting the wrong variables in a constructor), I don't test for it.</blockquote>
</p>


<p class="meta small-p">Changelog: 04-03-2013 - Add missing code for <code>UserRegistrationAdminNotification</code> implementation.</p>
