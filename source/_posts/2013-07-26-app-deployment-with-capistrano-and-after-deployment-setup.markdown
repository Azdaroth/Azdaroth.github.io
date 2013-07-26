---
layout: post
title: "Rails applications deployment with Capistrano and after deployment setup"
date: 2013-07-26 09:15
comments: true
categories: [Capistrano, Deployment]
---


<p>You've just setup your production server, but still haven't deployed your app? Then this the right place for you. You are going to learn how to deploy your app to remote server, deal with some initial security issues, create staging environment and setup monitoring tools.</p>

<h2>Introducing Capistrano</h2>

<p>Capistrano is an excellent tool to automate your deployment process using Rake DSL. It allows you to deploy applications using various source control management systems like Git, run migrations on remote server, restart application and many more.</p>

<h2>Application setup</h2>

<p>Let's start with creating Rails application: </p>

``` bash
rails new dummy_app
```

<p>add capistrano, capistrano-ext and pg gems(for Postgres database) to your Gemfile:</p>

``` ruby
gem 'pg'
gem 'capistrano'
gem 'capistrano-ext'
```

<p>And run bundle install.</p>

<h2>Is my app secure?</h2>

<p>Well, it depends. If it isn't going to be an open-source app, then you are safe. But if it is, then your session secret is publicly available which makes your app vulnerable to carefully crafted attacks and you should exclude it from your code repository. Initialize git repository in your application:</p>

``` bash
git init
``` 

<p>And add to your .gitignore file the following line:</p>

``` bash
/config/initializers/secret_token.rb
```

<h2>Database and staging environment config</h2>

<p>Now, edit database configuration file (config/database.yml) so it looks like this:</p>

``` yaml
development:
  adapter: postgresql
  host: localhost
  database: dummy_app_test
  username: dummy_app_user
  password: my-secret-password

test:
  adapter: postgresql
  host: localhost
  database: dummy_app_test
  username: dummy_app_user
  password: my-secret-password

production:
  adapter: postgresql
  host: localhost
  database: dummy_app_production
  username: dummy_app_user
  password: my-secret-password

staging:
  production
```

<p>There is one extra thing in this config: the staging environment. We are going to use pre-production environment for testing purposes. If you want to share the same database between production and staging, then leave this config as it is. If not, specify staging database:</p>

``` yaml
staging:
  adapter: postgresql
  host: localhost
  database: dummy_app_staging
  username: dummy_app_user
  password: my-secret-password
```

<p>Don't forget to to create specified databases for all environments.</p>

<p>You should also exclude database.yml from your code repository, not only for keeping your passwords secret, but also to prevent overriding your local configuration when fetching code from repository - add to .gitignore file:</p>

``` bash
/config/database.yml
```

<p>Staging environment should be close to production as much as possible, so copy the production.rb file and rename it to staging.rb: </p>

``` bash
cp config/environments/production.rb config/environments/staging.rb
```

<p>Capistrano configuration</p>

<p>To create configuration files, run</p>

``` bash
capify .
```

<p>It will create two files: config/deploy.rb and Capfile. Start with editing Capfile and uncomment this line:</p>

``` ruby
load 'deploy/assets'
```

<p>Next, open the deploy.rb and remove the default content.</p>

``` ruby
require "bundler/capistrano"

set :keep_releases, 5 # or any other number of releases you would like to keep

ssh_options[:port] = ssh-port # if you haven't changed anything in SSH config, set it to 22

# General

set :application, "dummy_app" # set the name of you application here
set :user, "deploy" # and the server user name

set :deploy_to, "/home/#{user}/applications/#{application}" # here goes path to you application
set :deploy_via, :remote_cache # it will fetch from the repository on server, not clone the entire repository

set :use_sudo, false # do not use sudo

# Git

set :scm, :git # set git as a Source Code Manager
set :repository,  "ssh://deploy@your.ip.goes.here:port/home/#{user}/repos/#{application}.git" # point your repository here

set :branch, "master" # set git branch here

# Server

role :web, "server.ip.goes.here"
role :app, "server.ip.goes.here"
role :db,  "server.ip.goes.here", :primary => true
role :db,  "server.ip.goes.here"

# Passenger

namespace :deploy do
 task :start do ; end
 task :stop do ; end
 task :restart, :roles => :app do
   run "touch #{current_path}/tmp/restart.txt"
 end
end

namespace :deploy do
  task :symlink_db, :roles => :app do
    run "ln -nfs #{deploy_to}/shared/config/database.yml #{release_path}/config/database.yml" # This file is not included repository, so we will create a symlink 
  end
  task :symlink_secret_token, :roles => :app do
    run "ln -nfs #{deploy_to}/shared/config/initializers/secret_token.rb #{release_path}/config/initializers/secret_token.rb" # This file is not included repository, so we will create a symlink 
  end
end

before 'deploy:assets:precompile', 'deploy:symlink_db'
before 'deploy:assets:precompile', 'deploy:symlink_secret_token'
after "deploy", "deploy:cleanup"

```






