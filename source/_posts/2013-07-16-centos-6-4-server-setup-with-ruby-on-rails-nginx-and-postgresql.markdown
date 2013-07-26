---
layout: post
title: "CentOS 6.4 server setup with Ruby On Rails, Nginx and PostgreSQL"
date: 2013-07-19 14:02
comments: true
categories: [Ruby, Rails, Server, PostgreSQL, Deployment, Unix]
---

<p>Server setup with the entire environment for Rails applications can be quite tricky, especially when you do it for the first time. Here is step by step guide how to setup CentOS 6.4 server with a basic environment for deploying Rails applications. I encourage you to choose CentOS Linux - it is a reliable distro (well, based on Red Hat Enterprise Linux), easy to handle and doesn't require advanced Unix knowledge like Gentoo (especially while updating system related stuff).</p>

<h2>Initial setup</h2>

<p>You need to ssh on your server:</p>

``` bash
ssh root@your-ip
```

<p>Start with creating new user deploy:</p>

``` bash
adduser deploy
```

<p>And create password for the new user:</p>
``` bash
passwd deploy
```
<p>You shouldn't use root user often, but you will need root privileges for performing many tasks, like installing stuff, so it is quite useful to edit sudo configuration - it will give deploy user an ability to perform all tasks which require root privileges by preceding command with sudo. Run:</p>

``` bash
visudo
```
<p>find section that looks like that:</p>

``` bash
## Allow root to run any commands anywhere
root    ALL=(ALL)       ALL
```

<p>and add the following line:</p>

``` bash
deploy    ALL=(ALL)       ALL
```

<p>If you are not familiar with Vi editor, you have to press a, and then you can type :). When you finish hit escape and type :wq! .</p>

<h2>Enhance security - configure SSH</h2>

<p>You can easily make your server more secure by editing SSH configuration. Type:</p>

``` bash
vi /etc/ssh/sshd_config
```

<p>Here are some default options which you may change:</p>

``` bash
#Port 22
#PermitRootLogin yes
```

<p>Default 22 port for SSH is not insecure, but changing it to some other value will make it more difficult to compromise your server by automated attacks. Pick any number less than 65536 and uncomment this line.</p>

<p>Another option is PermitRootLogin - change it to no to disable logging as root through ssh. You have root privileges by using sudo, so you don't need to login as root anyway.</p>

<p>If you are going to create some more users, but you don't want them to login through ssh, add following line:</p>

``` bash
AllowUsers deploy
```

<p>When you are finished type:</p>

``` bash
/etc/init.d/sshd reload
```

<p>Now, open <b>NEW</b> terminal window and check if everything works:</p>

``` bash
ssh -p new-port deploy@your-ip
```

<h2>Uhh, what was that IP?</h2>

<p>You can avoid typing your IP number on every login by using named hosts, which is quite simple: create or edit ~/.ssh/config (on your local machine, not server) and add:</p>

``` bash
Host some-awesome-server-name
Hostname your-ip-number
User deploy
Port your-port
```

<p>Now you can login on your server by:</p>

``` bash
ssh some-awesome-server-name
```

<p>Amazing!</p>

<p>But you can also skip password - you have to generate authentication keys on your local machine:</p>

``` bash 
ssh-keygen -t rsa
```

<p>And that's the entire output:</p>

``` bash
Generating public/private rsa key pair.
Enter file in which to save the key (/home/azdaroth/.ssh/id_rsa):
Created directory '/home/azdaroth/.ssh'.
Enter passphrase (empty for no passphrase):
Enter same passphrase again:
Your identification has been saved in /home/azdaroth/.ssh/id_rsa.
Your public key has been saved in /home/azdaroth/.ssh/id_rsa.pub.
The key fingerprint is:
d9:1c:0b:76:60:56:e0:af:cd:f3:93:c7:15:f5:dc:dc azdaroth@abyss
The key's randomart image is:
+--[ RSA 2048]----+
|        =o.      |
|       + .      .|
|        + o    o=|
|       . B o   .E|
|        S =     .|
|         +      .|
|        . +  o . |
|           oo o  |
|            .o   |
+-----------------+
```

<p>What about the passphrase? It's up to you. If you leave it blank, you can ssh on your server by just entering: ssh server-name and that's all. Pretty nice, but if your local machine gets stolen, something really bad may happen with your server. So, you should enter a passphrase, at least on your laptop. The only downside of passphrase is that you will be asked to enter it on each login.</p>

<p>To finish setup on your server, enter the following commands:</p>

``` bash
mkdir ~/.ssh
touch ~/.ssh/authorized_keys
chmod 700 ~/.ssh
chmod 600 ~/.ssh/authorized_key
```

<p>Setting these permissions is essential and ssh will stop working if StrictModes is set in configuration (and probably is by default). Now, copy your <b>PUBLIC</b> key to authorized_keys file on your server:</p>

``` bash
  cat ~/.ssh/id_rsa.pub | ssh server-name "cat >> ~/.ssh/authorized_keys"
```

<h2>Installing prerequisites</h2>

<p>You will need to install some libraries. Start with updates:</p>

``` bash
  sudo yum update
```

<p>You will probably want to install some extra repositories (like Fedora Epel) to get some up-to-date packages. Run:</p>
  
``` bash
wget http://dl.fedoraproject.org/pub/epel/6/x86_64/epel-release-6-8.noarch.rpm
wget http://rpms.famillecollet.com/enterprise/remi-release-6.rpm
sudo rpm -Uvh remi-release-6*.rpm epel-release-6*.rpm
```

<p>And enable remi repository:</p>

``` bash
sudo vi /etc/yum.repos.d/remi.repo
```

<p>In [remi] section set the enabled option to 1.</p>

``` bash 
[remi]
name=Les RPM de remi pour Enterprise Linux 6 - $basearch
#baseurl=http://rpms.famillecollet.com/enterprise/6/remi/$basearch/
mirrorlist=http://rpms.famillecollet.com/enterprise/6/remi/mirror
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-remi
```

<p>Now, you are going to install some packages, like RVM dependencies and other stuff.</p>

``` bash
sudo yum install git-core openssl openssl-devel subversion curl curl-devel gcc-c++ patch readline readline-devel zlib zlib-devel libyaml-devel libffi-devel  make bzip2 autoconf automake libtool bison sqlite-devel libxml2 libxml2-devel libxslt libxslt-devel libtool
```

<h2>RVM, Ruby and Rails</h2>

<p>Now you can proceed to installing Ruby. We will use RVM - command-line tool, which makes managing multiple Ruby versions really easy. Some developers prefer Rbenv, but I've never had any issues with RVM. To install RVM enter:</p>

``` bash
\curl -L https://get.rvm.io | bash -s stable
```

<p>Carefully read generated output. If everything is ok, run</p>

``` bash
source /home/deploy/.rvm/scripts/rvm
source ~/.bashrc
```

<p>Make sure you have following lines in your ~/.bashrc file :</p>

``` bash
[[ -s "$HOME/.rvm/scripts/rvm" ]] && . "$HOME/.rvm/scripts/rvm"
PATH=$PATH:$HOME/.rvm/bin # Add RVM to PATH for scripting
```

<p>To check if everything was installed properly enter:</p>

``` bash
type rvm | head -1
```

<p>It should return something like: rvm is a function. If not, reload terminal session (simply log out and log in again).</p>


<p>And now you can install specified Ruby Version:</p>

``` bash
rvm install 2.0.0
```

<p>Use installed Ruby version as the default one:</p>

``` bash
rvm use 2.0.0
rvm use 2.0.0 --default
```

<p>Nice! You've successfully installed Ruby. Now, you can install Bundler and Rails.</p>

```
gem install bundler rails
```

<h2>Nginx and Passenger</h2>

<p>You will need an http server to run your applications. Nginx is fast, lightweight and easy to configure and Phusion Passenger module makes Nginx and Rails integration painless. Firstly, install Passenger gem:</p>

``` bash
gem install passenger
```

<p>and then, install Nginx with compiled Passenger module:</p>

``` bash
rvmsudo passenger-install-nginx-module
```

<p>Choose the recommended install mode.</p>

<p>Now, open the Nginx configuration file (/opt/nginx/cong/nginx.conf if you haven't changed it during installation).</p>


``` bash
sudo vi /opt/nginx/conf/nginx.conf
```
<p>Let's change some default config. Change worker_processes to be equal to number of CPU cores. You can also enable gzip compression. Just add following lines:</p>


``` bash
gzip on;
gzip_vary on;
gzip_types text/plain text/css application/json application/x-javascript text/xml application/xml application/xml+rss text/javascript;
```

<p>Now setup your Rails application:</p>

``` bash
server {
  listen       80;
  server_name  some-example.com;

  root /path-to-your-application/current/public;
  client_max_body_size 128M;
  passenger_enabled on;
  rails_env production;

  location ~ ^/(assets|images|javascripts|stylesheets|system)/ {
    expires max;
    add_header Cache-Control public;
  }
}
```

<p>At the end it should look like that:</p>

``` bash
#user  nobody;
worker_processes  4;

#error_log  logs/error.log;
#error_log  logs/error.log  notice;
#error_log  logs/error.log  info;

#pid        logs/nginx.pid;


events {
  worker_connections  1024;
}


http {
  passenger_root /home/azdaroth/.rvm/gems/ruby-2.0.0-p247/gems/passenger-4.0.10;
  passenger_ruby /home/azdaroth/.rvm/wrappers/ruby-2.0.0-p247/ruby;

  include       mime.types;
  default_type  application/octet-stream;

  #log_format  main  '$remote_addr - $remote_user [$time_local] "$request" '
  #                  '$status $body_bytes_sent "$http_referer" '
  #                  '"$http_user_agent" "$http_x_forwarded_for"';

  #access_log  logs/access.log  main;

  sendfile        on;
  #tcp_nopush     on;

  #keepalive_timeout  0;
  keepalive_timeout  65;


  gzip on;
  gzip_vary on;
  gzip_types text/plain text/css application/json application/x-javascript text/xml application/xml application/xml+rss text/javascript;

  server {
    listen           80;
    server_name      localhost;

    location / {
      root   html;
      index  index.html index.htm;
    }

    error_page       500 502 503 504  /50x.html;
    location = /50x.html {
      root   html;
    }
         
  }

  server {
    listen       80;
    server_name  some-example.com;

    root /path-to-your-application/current/public;
    client_max_body_size 128M;
    passenger_enabled on;
    rails_env production;

    location ~ ^/(assets|images|javascripts|stylesheets|system)/ {
      expires max;
      add_header Cache-Control public;
    }
  }
}

```

<p>You should also use a neat little script for easier Nginx management. Open the following file:</p>

``` bash
sudo vi /etc/init.d/nginx
```

<p>copy & paste script below:</p>

``` bash
#!/bin/sh
#
# nginx - this script starts and stops the nginx daemin
#
# chkconfig:   - 85 15 
# description:  Nginx is an HTTP(S) server, HTTP(S) reverse \
#               proxy and IMAP/POP3 proxy server
# processname: nginx
# config:      /opt/nginx/conf/nginx.conf
# pidfile:     /opt/nginx/logs/nginx.pid

# Source function library.
. /etc/rc.d/init.d/functions

# Source networking configuration.
. /etc/sysconfig/network

# Check that networking is up.
[ "$NETWORKING" = "no" ] && exit 0

nginx="/opt/nginx/sbin/nginx"
prog=$(basename $nginx)

NGINX_CONF_FILE="/opt/nginx/conf/nginx.conf"

lockfile=/var/lock/subsys/nginx

start() {
    [ -x $nginx ] || exit 5
    [ -f $NGINX_CONF_FILE ] || exit 6
    echo -n $"Starting $prog: "
    daemon $nginx -c $NGINX_CONF_FILE
    retval=$?
    echo
    [ $retval -eq 0 ] && touch $lockfile
    return $retval
}

stop() {
    echo -n $"Stopping $prog: "
    killproc $prog -QUIT
    retval=$?
    echo
    [ $retval -eq 0 ] && rm -f $lockfile
    return $retval
}

restart() {
    configtest || return $?
    stop
    start
}

reload() {
    configtest || return $?
    echo -n $"Reloading $prog: "
    killproc $nginx -HUP
    RETVAL=$?
    echo
}

force_reload() {
    restart
}

configtest() {
  $nginx -t -c $NGINX_CONF_FILE
}

rh_status() {
    status $prog
}

rh_status_q() {
    rh_status >/dev/null 2>&1
}

case "$1" in
    start)
        rh_status_q && exit 0
        $1
        ;;
    stop)
        rh_status_q || exit 0
        $1
        ;;
    restart|configtest)
        $1
        ;;
    reload)
        rh_status_q || exit 7
        $1
        ;;
    force-reload)
        force_reload
        ;;
    status)
        rh_status
        ;;
    condrestart|try-restart)
        rh_status_q || exit 0
            ;;
    *)
        echo $"Usage: $0 {start|stop|status|restart|condrestart|try-restart|reload|force-reload|configtest}"
        exit 2
esac
```

<p>and make it executable:</p>

``` bash
sudo chmod +x /etc/init.d/nginx
```

<p>Now you can control Nginx by few commands:</p>

``` bash
sudo service nginx start
sudo service nginx stop
sudo service nginx reload
sudo service nginx restart
sudo service nginx status
sudo service nginx configtest
```

<p>To add Nginx to the default run levels, enter:</p>

``` bash
sudo /sbin/chkconfig nginx on
```

<h2>ImageMagick</h2>

<p>This part is optional, but you will probably need ImageMagick in some applications - it is a powerful software for creating, editing and converting images. The ImageMagick version available in repositories is probably outdated, so we will compile it from source.</p>

<p>Start with installing some delegates (you have to install them before compiling ImageMagick).</p>

``` bash
sudo yum install libjpeg libjpeg-devel libpng-devel libpng-devel freetype freetype-devel libtiff-devel jasper-devel bzip2-devel giflib-devel ghostscript-devel
```

<p>And compile it:</p>

``` bash
wget http://www.imagemagick.org/download/ImageMagick.tar.gz
tar xvfz ImageMagick.tar.gz
cd ImageMagick-6.8.6-6
./configure
make 
sudo make install
sudo ldconfig /usr/local/lib
make check
``` 

<p>Export PATH variable:</p>

``` bash
export PATH=$PATH:/usr/local/bin
``` 

<p>And check if everything works:</p>

``` bash
convert -version
```

<p>You should get output similar to this:</p>

``` bash
Version: ImageMagick 6.8.6-6 2013-07-18 Q16 http://www.imagemagick.org
Copyright: Copyright (C) 1999-2013 ImageMagick Studio LLC
Features: DPC OpenMP
Delegates: bzlib freetype jng jp2 jpeg png ps tiff xml zlib
```

<h2>PostgreSQL</h2>

<p>So, the last step is installing PostgreSQL. Firstly, you have to modify /etc/yum.repos.d/CentOS-Base.repo file:</p>

``` bash
sudo vi /etc/yum.repos.d/CentOS-Base.repo
```

<p>and in both [base] and [updates] sections add the following line:</p>

``` bash
exclude=postgresql*
```
<p>Now, install  PostgreSQL repository and PostgreSQL itself:</p>

``` bash
sudo rpm -Uvh http://yum.postgresql.org/9.2/redhat/rhel-6-x86_64/pgdg-redhat92-9.2-7.noarch.rpm
sudo yum install postgresql92 postgresql92-devel postgresql92-server postgresql92-libs postgresql92-contrib 
```

<p>You have to initialize database cluster before doing anything:</p>

``` bash
sudo /etc/init.d/postgresql-9.2 initdb
```

<p>And you can start Postgres and add it do default run levels:</p>

``` bash
sudo service postgresql-9.2 start
sudo chkconfig --levels 235 postgresql-9.2 on
```

<p>The very first thing you should do with Postgres is setting password for postgres user:</p>

``` bash 
sudo su postgres
psql
```
<p>Now, you are in psql console. To change password, enter:</p>

``` bash
alter user postgres with password 'postgres-user-password';
```
<p>Logout from postgres user and modify /var/lib/pgsql/9.2/data/pg_hba.conf:</p>

``` bash
sudo vi /var/lib/pgsql/9.2/data/pg_hba.conf
```

<p>At the bottom of the file change authentication method to md5:</p>

``` bash
# TYPE  DATABASE        USER            ADDRESS                 METHOD

# "local" is for Unix domain socket connections only
local   all             all                                     md5
# IPv4 local connections:
host    all             all             127.0.0.1/32            md5
# IPv6 local connections:
host    all             all             ::1/128                 md5
``` 

<p>and restart Postgres:</p>

``` bash
sudo service postgresql-9.2 restart
```

<p>To run psql console as deploy user just enter:</p>

``` bash
psql postgres postgres
```

<p>and create a new user and database:</p>


``` bash
create user username with password 'secretPassword';
create database testdb owner=username;
``` 

<p>And that's it! Enjoy your server.</p>