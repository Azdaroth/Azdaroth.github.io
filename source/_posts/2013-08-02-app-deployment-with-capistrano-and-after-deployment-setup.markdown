---
layout: post
title: "Rails applications deployment with Capistrano and after deployment setup"
date: 2013-08-02 14:15
comments: true
categories: [Capistrano, Deployment]
---


<p>You've just setup your production server, but still haven't deployed your app? Then this the right place for you. You are going to learn how to deploy your app to remote server, deal with some config files, create staging environment and setup monitoring tools.</p>

<h2>Introducing Capistrano</h2>

<p>Capistrano is an excellent tool to automate your deployment process using Rake DSL. It allows you to deploy applications using various source control management systems like Git, run migrations on remote server, restart application and many more.</p>

<h2>Application setup</h2>

<p>Let's start with creating Rails application: </p>

``` bash
rails new dummy_app
```

<p>add capistrano, capistrano-ext, rvm-capistrano (for RVM integration) and pg gems(for Postgres database) to your Gemfile:</p>

``` ruby Gemfile
gem 'pg'
gem 'capistrano'
gem 'rvm-capistrano'
gem 'capistrano-ext'
```

<p><b>NOTE:</b> When writing this article, the current Capistrano version was 2.15.5 which I believe is buggy as I had some problems with authentication while deploying. If you have the same problem, use 2.15.3 version instead.</p>

<p>You should also uncomment this line: </p>

``` ruby Gemfile
gem 'therubyracer', platforms: :ruby
```

<p>And run bundle install.</p>

<h2>Is my app secure?</h2>

<p>Well, it depends. If you are the only person working on it, then you are safe. But if you aren't, then your session secret is available to other people, which makes your app vulnerable to <a href="http://robertheaton.com/2013/07/22/how-to-hack-a-rails-app-using-its-secret-token/">carefully crafted attacks</a> and you should exclude it from your code repository. Initialize git repository in your application:</p>

``` bash
git init
``` 

<p>And add to your .gitignore file the following line:</p>

``` bash .gitignore
/config/initializers/secret_token.rb
```

<h2>Database and staging environment config</h2>

<p>Now, edit database configuration file (config/database.yml), so it looks similar to this:</p>

``` yaml config/database.yml
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
  adapter: postgresql
  host: localhost
  database: dummy_app_production
  username: dummy_app_user
  password: my-secret-password
```

<p>There is one extra thing in this config: the staging environment. We are going to use pre-production environment for testing purposes. If you want to share the same database between production and staging, then leave this config as it is.</p>

<p>Don't forget to to create specified databases for all environments.</p>

<p>You should also exclude database.yml from your code repository, not only for keeping your passwords secret, but also to prevent overriding local configuration when fetching code from repository - add to .gitignore file:</p>

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

``` ruby Capfile
load 'deploy/assets'
```

<p>Next, open the deploy.rb remove the default content, copy & paste the script below and adjust it according to the comments.</p>

``` ruby config/deploy.rb
require "bundler/capistrano"
require 'capistrano/ext/multistage'
require "rvm/capistrano"

# General

set :keep_releases, 5 # or any other number of releases you would like to keep
ssh_options[:port] = 12345 # if you haven't changed anything in SSH config, set it to 22
ssh_options[:forward_agent] = true # forward ssh keys
default_run_options[:pty] = true # set for the password prommpt

set :application, "dummy_app" # set the name of you application here
set :user, "deploy" # and the server user name

set :stages, ["staging", "production"] # Set staging and production environment
set :default_stage, "staging" # Use staging environment as the default one to prevent accidentally deploying to production


set :deploy_via, :remote_cache # it will only fetch from the repository on server, not clone the entire repository from scratch

set :use_sudo, false # do not use sudo

# Git

set :scm, :git # set git as a Source Code Manager
set :repository,  "ssh://deploy@your.ip.goes.here:port/home/#{user}/repos/#{application}.git" # point your repository here

set :branch, "master" # set git branch here

# Server

role :web, "server.ip.goes.here" # HTTP Server
role :app, "server.ip.goes.here" # server with your app
role :db,  "server.ip.goes.here", :primary => true # database server
role :db,  "server.ip.goes.here"

# Passenger

namespace :deploy do
 task :start do ; end
 task :stop do ; end
 task :restart, :roles => :app do # restart your app after finalizing deployment
   run "touch #{current_path}/tmp/restart.txt"
 end
end

# Symlinking

namespace :deploy do
  task :symlink_db, :roles => :app do
    run "ln -nfs #{deploy_to}/shared/config/database.yml #{release_path}/config/database.yml" # This file is not included repository, so we will create a symlink 
  end
  task :symlink_secret_token, :roles => :app do
    run "ln -nfs #{deploy_to}/shared/config/initializers/secret_token.rb #{release_path}/config/initializers/secret_token.rb" # This file is not included repository, so we will create a symlink 
  end
end

before 'deploy:assets:precompile', 'deploy:symlink_db' # callback: run this task before deploy:assets:precompile
before 'deploy:assets:precompile', 'deploy:symlink_secret_token' # # callback: run this task before deploy:assets:precompile
after "deploy", "deploy:cleanup" # delete old releases
```
<p>Now, create <i>deploy</i> directory in <i>config</i> directory and add production.rb and staging.rb files there. You have to specify paths, where the production and staging app instance will be deployled. Let's edit the production.rb file:</p>

``` ruby config/deploy/production.rb
set :deploy_to, "/home/deploy/rails_projects/dummy_app"
```

<p>and staging.rb:</p>


``` ruby config/deploy/production.rb
set :deploy_to, "/home/deploy/rails_projects/dummy_app_staging"
```

<p>That's a basic configuration that should be sufficient in most cases. But Capistrano is a really sophisticated tool, you can specify diffrent servers for staging and production environment, diffrent git branches, diffrent repositories and many more. Just specify diffrent settings in production.rb and staging.rb if you need to.</p>

<h2>Deployment</h2>

<p>Before deploying your app, you have to setup git repository. We will create just an empty repo in <i>/home/deploy/repos</i> directory on remote server: </p>

``` bash 
ssh your-server "mkdir /home/deploy/repos && mkdir /home/deploy/repos/dummy_app.git  && git init --bare /home/deploy/repos/dummy_app.git"
```

<p>Keeping the Git repositories on deploy user might not be the best idea, especially when you want to give other people access to the repo, but it sufficient for demonstration purposes. In other cases, you should rather create seperate git user with a limited shell (git-shell) or use some sophisticated tools like Gitolite if you need to.</p>

<p>Now we can commit all changes and deploy our application:</p>

``` bash 
git add --all
git commit -am "Setup deployment configuration"
git remote add origin ssh://deploy@your.ip.goes.here:port/home/deploy/repos/dummy_app.git
git push origin master
```

<p>You are ready to deploy our application, but before that you need to setup databases and http server configuration. If you have any problem, check <a hre"http://karolgalanciak.com/blog/2013/07/19/centos-6-4-server-setup-with-ruby-on-rails-nginx-and-postgresql/">this one</a> out (remember about specifying appropriate rails_env). Firstly, let the Capistrano deal with creating all the neccessary directories in both staging and production environments:</p>

``` bash
cap deploy:setup
cap production deploy:setup
```
<p>Then check if directory permissions, utilities and other dependencies are correct:</p>

``` bash
cap deploy:check
cap production deploy:check
```

<p>In both cases you should have output ending with: <i>You appear to have all necessary dependencies installed.</i></p>

<p>The last thing before deployment: we haven't included <i>secret_token.rb</i> and <i>database.yml</i> files in repo, so we have to copy them on remote server:</p>

``` bash
scp config/database.yml you-server:/home/deploy && scp config/initializers/secret_token.rb your-server:/home/deploy
ssh your_server "mkdir /home/deploy/rails_projects/dummy_app/shared/config && mkdir /home/deploy/rails_projects/dummy_app_staging/shared/config"
ssh your_server "mkdir /home/deploy/rails_projects/dummy_app/shared/config/initializers && mkdir /home/deploy/rails_projects/dummy_app_staging/shared/config/initializers"
ssh you_server "cp /home/deploy/database.yml /home/deploy/rails_projects/dummy_app/shared/config/database.yml && mv /home/deploy/database.yml /home/deploy/rails_projects/dummy_app_staging/shared/config/database.yml"
ssh you_server "cp /home/deploy/secret_token.rb /home/deploy/rails_projects/dummy_app/shared/config/initializers/secret_token.rb && mv /home/deploy/secret_token.rb /home/deploy/rails_projects/dummy_app_staging/shared/config/initializers/secret_token.rb"
```

<p>And you can deploy your application. Instead of cap deploy, use cap deploy:cold and cap production deploy:cold - it will deploy the app, run all migrations and run deploy start instead of cap:restart.</p>

``` bash
cap deploy:cold
cap production deploy:cold
```

<p>Done! You have just deployed your application. Next time use cap deploy or cap deploy:migrations to run migrations.</p>

<h2>Monitoring with Monit</h2>

<p>How do you know if everything is running correctly after deployment? Well, you don't know, unless you install a monitoring tool. Monit is a great and easy to configure utility for managing and monitoring processes. Let's start with installing Monit on remote server (I use CentOS Linux, there are some differences between distros, so the location of the files might be diffrent, e.g. on Debian, the configuration file is in /etc/monit/monit.rc):</p>

``` bash
sudo yum install monit
```

<p>and edit the configuration file:</p>

``` bash
sudo vi /etc/monit.conf
```
<p>Read carefully all the comments to get familiar with Monit. Then specify your configuration, e.g.:</p>

``` bash

# check services every minute
set daemon 60


# monitor nginx
check process nginx with pidfile /opt/nginx/logs/nginx.pid
  start program = "/etc/init.d/nginx start"
  stop program  = "/etc/init.d/nginx stop"

# monitor postgres
check process postgres with pidfile /var/lib/pgsql/9.2/data/postmaster.pid
  start program = "/etc/init.d/postgresql start"
  stop  program = "/etc/init.d/postgresql stop"

# web interface setup
set httpd port 2812 and
  use address localhost
  allow username:"password" # specify username and password for http basic authentication
  allow localhost
  allow @monit
```

<p>There are a lot of available Monit recipies, e.g. <a href="http://mmonit.com/wiki/Monit/ConfigurationExamples">here</a>, so it is quite easy do setup. When you finish, restart Monit:</p>

``` bash
sudo monit reload
```

<p>Or if you haven't started it yet:</p>

``` bash
sudo monit
```

<p>To check status of processes being monitored, run: </p>

``` bash
sudo monit status
```

<p>You don't have to ssh on your server everytime you want to check the status, Monit comes with a very nice web interface. Here is a simple Nginx configuration, so that you will be able to access Monit via your-ip:1111/monit address:</p>

``` bash
server {
  listen 1111;
  server_name localhost;

  location /monit/ {
    proxy_pass http://127.0.0.1:2812/; # pass query to backend, replace /monit/ uri part to just /
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
  }
}
``` 

<p>Use password and username specified in Monit configuration.</p>


<h2>Logrotate</h2>

<p>After some time your Rails app logs and especially Nginx logs might be really large, so it is a good idea to somehow manage them. Fortunately, you can use system-built utility called Logrotate. Just open <i>/etc/logrotate.conf</i> and paste the configuration below (remember about changing path to your application):</p>


``` bash


/home/deploy/rails_projects/your_app_name/shared/log/*.log { 
  daily
  rotate 30
  missingok
  compress
  notifempty
  delaycompress
  sharedscripts
  copytruncate
}
￼￼￼￼￼￼￼￼￼￼￼￼

/opt/nginx/logs/*.log { 
  daily
  rotate 30
  compress
  missingok
  notifempty
  delaycompress
  sharedscripts

  postrotate
    [ ! -f /var/run/nginx.pid ] || kill -USR1 `cat /var/run/nginx.pid`
  endscript }

```

<p>Here is the options explanation:</p>

<ul>
<li><b>daily</b> - rotate the logs every day</li>
<li><b>rotate 30</b> - rotate logs 30 times, after that delete the oldest</li>
<li><b>missingok</b> - ignore if the file doesn't exist</li>
<li><b>compress</b> - compress logs with gzip</li>
<li><b>notifempty</b> - leave file if the logs are empty</li>
<li><b>delaycompress</b> - postpone compression of the file to the next cycle</li>
<li><b>sharedscripts</b> - tell only once that the logs have been rotated, not rach time for every group</a></li>
<li><b>copytruncate</b> - copy the log file and and truncate the original one</li>
<li><b>postrotate [ ! -f /var/run/nginx.pid ] || kill -USR1 `cat /var/run/nginx.pid` endscript</b> - tell Nginx that the logs have been rotated and use the new ones.</li>
</ul>

<p>And that's is it! Cron by default runs logrotate every day.</p>



