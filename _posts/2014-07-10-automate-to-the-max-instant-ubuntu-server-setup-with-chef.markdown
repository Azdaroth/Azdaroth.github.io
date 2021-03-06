---
layout: post
title: "Automate to the max: instant Ubuntu Server setup with Chef"
date: 2014-07-10 20:00
comments: true
categories: [Server, Chef, Deployment]
---

<p>You've started developing new app and need server to deploy it. You can choose hosting platform like <a href="https://www.heroku.com" target="_blank">Heroku</a> or <a href="https://shellycloud.com" target="_blank">Shelly</a> which may turn out to be quite expensive if you want to host multiple apps. You can also set up your own server. Going with the latter option can be quite time consuming, especially if sysadministration is not you main responsibility and you have multiple servers to provision. I that case automation beyond simple Bash scripts is a must - time to meet <strong>Chef</strong>.</p>

<!--more-->

<h2>What is Chef?</h2>
<p>Chef is the automation framework which uses Ruby DSL and helps provisioning new servers by automating the whole process. We are going to concentrate on Chef Solo where we set up all roles (like PostgreSQL server) on local machine and use them on our server, contrary to Chef Server which is a hub for configuration data that is automatically applied to all nodes (servers) connected with central server, quite useful when you need to manage serious amount of servers.</p>

<p>We will also be using some other utilities - <strong>Knife</strong> (solo) which is a command line utility helpings us interact with server and <strong>Berkshelf</strong> - a bundler-like utility for Chef recipes.</p>

<p>I'm not going to write another tutorial explaining every possible detail of entire Chef DSL. The <a href="http://docs.opscode.com" target="_blank">documentation</a> is pretty good and there are also plenty of other resources you can learn from. I'd rather like to explain the most important terms, show basic configuration, demonstrate how to write very simple recipe and at the end I am going to introduce my own cookbook that I use for servers' setup with <strong>Ubuntu Server 14.04</strong>. Why Ubuntu? Well, sysadministration is not my main responsibility and it's much easier to find solutions (or Chef cookbooks) for Ubuntu than any other distribution.</p>

<p>After reading this post you should be able to setup every server instantly and have some basic understanding of what's going on.</p>

<h2>Why use Chef?</h2>

<p>You may wonder what are the benefits of using Chef over the Bash scripts. Firstly, Chef provides extremely expressive DSL, just take a look at the code below:</p>

``` ruby
template "/etc/nginx/nginx.conf" do
  owner "root"
  group "root"
  mode "0644"
  source "nginx.conf.erb"
end
```
<p>You can have some general idea what it does, even if you don't know Chef. That way it's quite easy to find reusable recipes that you can customize to your requirements and write your own solutions.</p>

<p>Another huge benefit is <strong>idempotence</strong> - you can apply the same recipes multiple times on your server and the state of the server will be exactly the same as after running them for the first time. If you change something in eg. configuration files, only these changes will be applied. Try achieving the same using shell scripts only ;).</p>

<p>Once you understand Chef, provisioning new servers will be extremely easy and fast - it can be even limited to 2 commands if you use the same configuration for all servers.</p>

<h2>Chef basics</h2>

<h3>Terminology</h3>

<p><strong>Node</strong></p>

<p>A server (machine) we are going to set up and run Chef on.</p>

<p><strong>Recipe</strong></p>

<p>Basic unit in Chef for installing one thing, like PostgreSQL, ImageMagick, etc.</p>

<p><strong>Cookbook</strong></p>

<p>Collection of recipes, e.g. PostgreSQL cookbook.</p>

<p><strong>Role</strong></p>

<p>Combination of recipes that fulfill specific "feature" (or role) - PostgreSQL server role ,besides Postgres itself, may also require Monit configuration</p>

<p><strong>Data bags</strong></p>

<p>Files with data that may be required by some recipes, e.g. ssh keys that will be added to the authorized keys for deploy user.</p>

<h3>Getting started</h3>

<p>Let's start with creating directory for really simple chef recipe:</p>

```
mkdir chef-simple-recipe
cd chef-simple-recipe
```

<p>and create Gemfile with chef, knife-solo and berkshelf gems:</p>

``` ruby
source 'https://rubygems.org'

gem 'knife-solo'
gem 'chef'
gem 'berkshelf'
```

<p>Now we can initialize our project using Knife utility:</p>

```
knife solo init .
```

<p>You should be familiar with the generated directory structure after going through <em>terminology</em> part. You may wonder what's the difference between cookbooks and site-cookbooks directory: cookbooks is for storing, well, cookbooks, installed by Berkshelf and site-cookbooks is for our own cookbooks.</p>

<p>Berskfile resembles closely Gemfile: to add new cookbooks just specify the name of cookbook:</p>

```
site :opscode

cookbook 'build-essential'
```

<p>In most cases I also specify git repository to have a quick reference to the cookbook:</p>

```
site :opscode

cookbook 'build-essential', git: 'https://github.com/opscode-cookbooks/build-essential
```

<p>To install all recipes use Berkshelf:</p>

```
berks install
```

<p>If you want cookbooks to be extracted to <code>cookbooks</code> directory:</p>

```
berks install --path cookbooks
```

<h3>Writing first Chef role - Nginx server</h3>

<p>To understand the general idea behind Chef we are going to write pretty simple role for Nginx. It will take care of installing Nginx with some specified attributes in configuration file and setup monitoring with Monit. We also need to check if everything works. Fortunately, we don't need real server, <a href="http://www.vagrantup.com" target="_blank">Vagrant</a> will be perfect to set up a virtual environment. Just download it and follow the instructions below:</p>

<p>Firstly, let's create directory for our server:</p>

```
mkdir ubuntu-server-14-04
cd ubuntu-server-14-04
```

<p>and install Ubuntu Server 14-04:</p>

```
vagrant init ubuntu-server-14-04 https://cloud-images.ubuntu.com/vagrant/trusty/current/trusty-server-cloudimg-amd64-vagrant-disk1.box
```

<p>As you can see, the <code>Vagrantfile</code> was created. You may check it out but it's not necessary.</p>

<p>To run Vagrant:</p>

```
vagrant up
```

<p>To check if everything works, ssh on the virtual machine with Ubuntu Server:</p>

```
vagrant ssh
```

<p>Now we have our node, let's prepare it for running Chef (the command below must be run within main Chef project directory):</p>


```
knife solo prepare vagrant@127.0.0.1 -p 2222 -i ~/.vagrant.d/insecure_private_key
```


<p>Remember to use real system user name.</p>

<p>Our virtual node can now run the Chef client. The command above has also generated <b>nodes/127.0.0.1.json</b> configuration file. Let's investigate the content: <code>run_list</code> is a list of all roles and recipes that will be applied on the node. You can add new roles/recipes just by specifying the name but it may be a good idea to be more explicit and specify whether it's a role or a recipe to avoid name collisions. In our case it will be:</p>

```
{
  "run_list": [
    "role[nginx]"
  ],
  "automatic": {
    "ipaddress": "127.0.0.1"
  }
}
```
<p>Note: If you want to play a bit with the entire configuration discussed in this blog post, you may check it out <a href="https://github.com/Azdaroth/conf-chef-nginx-monit" target="_blank">here</a>.</p>

<p>Let's create our nginx role:</p>

```
touch roles/nginx.json
```

<p>Here's a basic template for roles:</p>

``` json
{
  "name": "nginx",
  "description": "Nginx server with Monit configuration",
  "default_attributes": {},
  "json_class": "Chef::Role",
  "run_list": [],
  "chef_type": "role"
}
```

<p>The content is pretty self-explanatory: We need to specify name of the role and mark it to be role, so we use <code>Chef::Role</code> <code>json_class</code> and <code>role</code> as a <code>chef_type</code>. We can also provide some description. And what's the <code>default_attributes</code>? We will put there any configuration related parameters, once we set up basic template, you will know how it works.</p>

<p>Let's create our custom cookbook for Nginx in site-cookbooks directory. It will consist of:</p>

<ul>
  <li>metadata.rb file - where we can specify some details like dependencies, supported operating systems, author of the cookbook etc.</li>
  <li>recipes directory - with default.rb file which will contain all the commands that need to be executed to install Nginx.</li>
  <li>templates directory - place for configuration files etc., we will put nginx.conf.erb template in <code>default</code> subdirectory.</li>
</ul>

<p>Why <code>default.rb</code> file name? You can write multiple recipes and specify their names, e.g. <code>monit-configuration::postgres</code>, <code>monit-configuration::nginx</code> but in our case we need just one recipe so the <code>default.rb</code> will be sufficient. Using <code>nginx::default</code> and <code>nginx</code> won't make any difference in this case. The same applies to the template files, that's why <code>nginx.conf.erb</code> is located in <code>templates/default/nginx.conf.erb</code>, not <code>templates/nginx.conf.erb</code></p>

<p>Out metadata.rb can look like that:</p>

``` ruby
# site-cookbooks/nginx/metadata.rb
name              "Nginx"
maintainer        "Karol Galanciak"
maintainer_email  "karol.galanciak@gmail.com"
description       "Installs Nginx"
version           "0.0.1"

recipe "nginx", "Installs Nginx"

supports "ubuntu"
```

<p>What about the configuration file? We need some basic template and decide which attributes will be hardcoded and where we want to have an ability to customize them within our roles. Here's an example, based on <a href="https://library.linode.com/web-servers/nginx/configuration/basic" target="_blank">that one</a>:</p>

```
user www-data;
worker_processes 4;

pid /var/run/nginx.pid;

events {
  worker_connections 768;
}

http {

  sendfile on;
  tcp_nopush on;
  tcp_nodelay on;
  keepalive_timeout 65;
  types_hash_max_size 2048;
  server_names_hash_bucket_size  64;

  include /etc/nginx/mime.types;
  default_type application/octet-stream;

  access_log /var/log/nginx/access.log;
  error_log /var/log/nginx/error.log;

  gzip on;
  gzip_disable "msie6";

  include /etc/nginx/conf.d/*.conf;
  include /etc/nginx/sites-enabled/*;
}
```

<p>Just to keep it as simple as possible let's assume that we will want only <code>user</code> and <code>worker_processes</code> attributes to be customizable and <code>www-data</code> user will be our default with 4 worker processes. We can achieve that using <strong>erb</strong> templates and specifying default attributes for our <code>default.rb</code> recipe. Using attributes is pretty straight-forward: we need to create file for our recipe (in that case<code>default.rb</code>) file in attributes directory and use hash syntax on <code>default</code> object where <code>nginx</code> will be our namespace:</p>

``` ruby
# attributes/default.rb
default['nginx']['user']      = 'www-data'
default['nginx']['worker_processes'] = '4'
```

<p>And how to access these values within our <code>nginx.conf.erb</code> template? The same way, hash syntax but with <code>node</code> object. So our template will look like this:</p>

``` ruby
# templates/default/nginx.conf.erb
user <%= node['nginx']['user'] %>;
worker_processes <%= node['nginx']['worker_processes'] %>;

pid /var/run/nginx.pid;

events {
  worker_connections 768;
}

http {

  sendfile on;
  tcp_nopush on;
  tcp_nodelay on;
  keepalive_timeout 65;
  types_hash_max_size 2048;
  server_names_hash_bucket_size  64;

  include /etc/nginx/mime.types;
  default_type application/octet-stream;

  access_log /var/log/nginx/access.log;
  error_log /var/log/nginx/error.log;

  gzip on;
  gzip_disable "msie6";

  include /etc/nginx/conf.d/*.conf;
  include /etc/nginx/sites-enabled/*;
}
```
<p>We will be able to customize these attributes from our role and/or node definition.</p>

<p>So we are left with the last part of installing Nginx: the recipe itself. Let's think how we want to this: we probably want to install <strong>Nginx</strong> - before that we may add <strong>ppa:nginx/stable</strong> repository to download the latest version, extract our template for configuration file and restart Nginx to use the new configuration. Fortunately, it looks very similar in Chef DSL:</p>

``` ruby
# recipes/default.rb
bash 'add repo for Nginx' do
  user 'root'
  code <<-CODE
    add-apt-repository ppa:nginx/stable
    apt-get update
  CODE
end

package "nginx"

template "/etc/nginx/nginx.conf" do
  owner "root"
  group "root"
  mode "0644"
  source "nginx.conf.erb"
  notifies :run, "execute[nginx-restart]", :immediately
end

execute "nginx-restart" do
  command "/etc/init.d/nginx restart"
  action :nothing
end
```
<p>What's going on here?</p>

<ol>
  <li>We start with adding Nginx repository using <code>bash</code> method which is used for executing Bash scripts (as the name implies). We want to run in as <code>root</code> user and the script for adding repository is in <code>code</code> body.</li>
  <li>In next step we tell Chef to install Nginx itself using package manager.</li>
  <li>Then we want Chef to use our template file for configuration. Most of the parameters are pretty self-explanatory: root user will be the owner of the file, the file will belong to root group, we set permissions for the file, specify source in <code>templates</code> directory and we use notifications to take some action <code>immediately</code> (the other option is <code>delayed</code> taking action at the end of chef-client run). To specify action to take place we use <code>resource[name]</code> syntax.</li>
  <li>In last step we define our action for restarting Nginx using Chef Execute provider: we specify the command to be run and action, which can be <code>:run</code>(will run the command) and <code>:nothing</code>(prevents from running the command - we use <code>:nothing</code> in this case as we use it in <code>notifies</code> method in <code>template</code>).</li>
</ol>


<p>And that's it. We are left with Monit config. We've already written our own recipe for Nginx so let's use <a href="https://github.com/TalkingQuickly/monit-tlq" target="_blank">this</a> recipe for Monit itself and <a href="https://github.com/TalkingQuickly/monit_configs-tlq" target="_blank">that one</a> for Nginx configuration. Copy these two cookbooks to <code>Berksfile:</code></p>

``` ruby
cookbook 'monit_configs-tlq', git: 'git@github.com:TalkingQuickly/monit_configs-tlq.git', branch: 'master'
cookbook 'monit-tlq', git: 'git@github.com:TalkingQuickly/monit-tlq.git', branch: 'master'
```

<p>And run:</p>

```
berks install
```

<p>Let's get back to our <code>nginx.json</code> role definition. We need to specify attributes for nginx namespace: the default <code>user</code> as www-data is ok, so we will just set <code>worker_processes</code> to 2 and also add Monit configuration for Nginx. At the end the role will look like that:</p>

``` 
// roles/nginx.json
{
  "name": "nginx-server",
  "description": "Nginx server",
  "default_attributes": {
    "nginx": {
      "worker_processes": "2"
    }
  },
  "json_class": "Chef::Role",
  "run_list": [
    "nginx",
    "monit_configs-tlq::nginx"
  ],
  "chef_type": "role"
}
```

<p>We will also need to install Monit itself. To check if everything works as it should, we will include email notifications. Let's define <code>monit</code> role:</p>

```
// roles/monit.json
{
  "name": "monit",
  "description": "Monit",
  "default_attributes": {
    "monit": {
      "notify_emails" : ["email@example.com"],
      "enable_emails" : true,
      "mailserver" : {
        "host" : "smtp.gmail.com",
        "port" : "587",
        "username" : "email@example.com",
        "password" : "password",
        "hostname" : "hostname"
      }
    }
  },
  "json_class": "Chef::Role",
  "run_list": [
    "monit-tlq"
  ],
  "chef_type": "role"
}
```

<p>Don't forget to put real data there ;). You may be wondering how did I know what attributes should I specify - in most cases these are documented but sometimes you will have to read the template files and check what kind of attributes you can customize and which are hardcoded.</p>

<p>We have our roles defined, the last thing we need to do is to include them in node definition:</p>

``` json
// nodes/127.0.0.1.json
{
  "run_list": [
    "role[monit]",
    "role[nginx]"
  ],
  "automatic": {
    "ipaddress": "127.0.0.1"
  }
}
```

<p>So here is the final step - applying recipes on our node:</p>

```
knife solo cook vagrant@127.0.0.1 -p 2222 -i /Users/system_user_name/.vagrant.d/insecure_private_key
```

<p>The great thing about Chef is that you can change the values of attributes, apply them on the node and the chef-client will pick that change up. Just change <code>worker_processes</code> to 3 and watch what happens - Chef client will change the value of the attribute and restart Nginx.</p>

<p>Note: applying the cookbooks on a real server is almost the same as working with Vagrant:</p>

```
knife solo prepare root@ip
knife solo cook root@ip
```

<h2>Setting up complete server for Rails apps with Chef</h2>

<p>Composing Chef cookbooks for your server can take a long time: reading all recipes / cookbooks, checking configuration etc. may be quite tedious, especially when doing if for the first time, so I decided to share with <a href="https://github.com/Azdaroth/chef-server-setup-template" target="_blank">my own</a> configuration which I'm going to describe in this section (heavily inspired by <a href="https://github.com/TalkingQuickly" target="_blank"></a> Ben Dixon's recipes, author of <a href="https://leanpub.com/deploying_rails_applications" target="_blank">Reliably Deploying Rails Applications</a>).</p>

<p>Let's take a look at the <a href="https://github.com/Azdaroth/chef-server-setup-template/blob/master/nodes/put_your_ip_address_here.json" target="_blank">node definition</a>. We have some new parameters: <code>environment</code> set to production - I will explain in a minute what is it for - and Debian <code>platform_family</code>. Next we've got some recipes-related attributes. It could also be put in role definitions but I like keeping sensitive data in node definition:</p>

<ul>
  <li><strong>authorization</strong> - these attributes are related to <code>sudo</code> recipe - we assume that we are going to use <strong>deploy</strong> user which is going to have sudo access enabled. Also, the entire <strong>sysadmin</strong> group is going to have sudo access. We set <code>passwordless</code> to be false - the password will alwaus be required.</li>
  <li><strong>monit</strong> - configuration for Monit concerning sending notifications and accessing via web interface. I would suggest having them enabled. However, if you decide not to enable them, just delete this section.</li>
  <li><strong>postgresql</strong> - you must specify password hash for <code>postgres</code> user. You can generate it easily using openssl: <code>openssl passwd -1 "yourpassword"</code></li>
  <li><strong>security</strong> - we can set ssh port here. The important thing is that you will have to restart ssh service, even if you don't change the value. Restarting using Chef caused some exceptions that I couldn't handle so far, so remember to restart the service while sshing on your server after running Chef for the first time: <code>/etc/init.d/ssh restart</code></li>
</ul>

<p>And the last thing is <code>run_list</code>:</p>

<ul>
  <li><strong>role[server]</strong> - responsible for basic server setup</li>
  <li><strong>role[postgres-server]</strong> - install PostgreSQL and related stuff</li>
  <li><strong>role[rails-app]</strong> - Ruby / Rails related components, like RVM, Rubies</li>
  <li><strong>role[mongo-server]</strong> - installs MongoDB and sets up Monit monitoring</li>
  <li><strong>role[redis-server]</strong> - installs Redis and sets up Monit monitoring</li>
  <li><strong>role[memcached-server]</strong> - installs Elasticsearch and sets up Monit monitoring</li>
  <li><strong>role[nginx]</strong> - installs Nginx with Passenger and sets up Monit monitoring.</li>
</ul>

<p>If you don't want to install some components, simply remove them from <code>run_list</code>.</p>

<p>One more thing before we move to more detailed description of the roles: <code>data_bags</code> directory. It will be used for creating user (<strong>deploy</strong>), setting up password (again, password hash, not the plain password) and uploading ssh key. The <strong>deploy</strong> user is already specified in <code>deploy.json</code> file, so just paste your ssh key from <code>id_rsa.pub</code> and the password hash generated by:</p>

```
openssl passwd -1 "yourpassword"
```

<p>As the attributes set in the node definition take precedence over the ones defined in roles, the important part in the server role is the <code>run_list</code>:</p>
<ul>
  <li><code>openssl</code> is responsible for managing passwords></li>
  <li><code>build-essential</code> installs build-essential</li>
  <li><code>chef-solo-search</code> - library related to data bags which helps with searching</li>
  <li><code>sudo</code> and <code>users::sysadmins</code> were already discussed - they are responsible for creating users with specified password and giving sudo access</li>
  <li><code>ssh_key_gen</code> generated ssh key for deploy user</li>
  <li><code>basic-security-tlq</code> - based on <a href="https://github.com/TalkingQuickly/basic_security-tlq" target="_blank">this</a> recipe - deals with security. It installs fail2ban, ufw (firewall), unattended-upgrades packages and installs security updates automatically each day. It also modifies ssh settings (X11Forwarding is set to no, UsePAM to no and ssh port to specified value in node definition). It also enables 22, 80 (for Nginx) and specified ssh port in firewall and disables any other. You can add some rules for firewall using <code>firewall_allow</code> attributes in the following format:  {"port": "x", "ip": "xxx.xxx.xxx.xxx"}</li>
  <li><code>look-and-feel-tlq</code> - based on <a href="https://github.com/TalkingQuickly/look_and_feel-tlq" target="_blank">this</a> recipe (I had to comment out restarting ssh service) - installs htop, vim, unzip packages. Remeber that <code>environment</code> parameter? If set to <code>production</code>, it will display beautiful "PRODUCTION" banner while sshing ;).</li>
  <li><code>monit-tlq</code> - installs Monit</li>
  <li><code>monit_configs-tlq::system</code> - sets up Monit configuration for system. You should check <a href="https://github.com/TalkingQuickly/monit_configs-tlq/blob/master/templates/default/system.conf.erb" target="_blank">it</a> out and decide if you want to include it, you may receive some occasional spam about on eg. small VPS instances, which is not a good sign. Monit notifications shouldn't be neglected.</li>
</ul>

<p>Let's move to another role - Postgres server: basically it installs PostgreSQL (9.3), changes <code>pg_hba.conf</code> configuration using specified attributes, uses <strong>pgtune</strong> utility to provide better configuration parameters (based on the hardware) and thus performance and sets up Monit monitoring. If you need more customization, refer to the <a href="https://github.com/hw-cookbooks/postgresql" target="_blank">docs</a>.</p>

<p>Next role deals with Ruby and Rails environment. The most important thing here is that it installs system-wide RVM, which is in my opinion much more convenient to work with on servers (development machine is a different story). Next, <code>deploy</code> user is added to rvm group, default Ruby version is specified and Rubies are installed. We also install Bundler and Passenger gems. You can check the <a href="https://github.com/fnichol/chef-rvm" target="_blank">docs</a> if you need further customization. And what about <code>rails_gem_dependencies-tlq</code> recipe? It installs some packages that you will probably need: curl, libcurl3, libcurl3-dev, <strong>imagemagick</strong>, libmagickwand-dev and nodejs. And one more thing: there might be a problem with RVM permissions (at time of writing this post, <a href="https://github.com/fnichol/chef-rvm/pull/257" target="_blank">this</a> pull request haven't been merged yet), so it may be a good idea to run: <code>rvm fix-permissions system</code> when sshing to your server for the first time.</p>

<p>Another role is Mongo server - it installs Mongodb, sets up Monit monitoring and uses <strong>/home/data/mongodb</strong> directory for db, you may delete it if you want the default value.</p>

<p>Next three roles are quite similar: they install Redis, Memcached and Elasticsearch and set up Monit configuration for each of them. Also, in case of Elasticsearch, it installs OpenJDK and gives possibility to customize the amount of allocated memory - you will probably  want to remove it, I keep it in a template, just to remember that it's a customizable attribute.</p>

<p>And the last one role: Nginx role, which installs Nginx with Passenger and sets up monitoring with Monit. There were some problems with using RVM Ruby when dealing with Passenger so it required helper recipe for <code>rake</code> package. There are a lot of hardcoded values (Ruby version, Passenger version) so make sure they match the ones specified in Rails App role. If you want more customization, refer to the <a href="https://github.com/miketheman/nginx" target="_blank">docs</a>.</p>

<h2>Wrapping up</h2>

<p>That was pretty quick introduction to <strong>Chef</strong> and there might be a lot things that weren't made perfectly clear. Again, it was not the purpose of this post to explain every possible detail but to give you the general idea. I hope that after reading this blog post you will have some basic understanding how Chef and related utilities work, how to write your own recipes, fork other cookbooks and modify them to your taste and never again do the manual server setup. You also have pretty nice starting point - just clone the repo of my server template and apply to the nodes ;).</p>
