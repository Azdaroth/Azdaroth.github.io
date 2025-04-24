---
layout: post
title: "RDS Database Migration Series - Integrating Ruby on Rails Applications with RDS Proxy"
date: 2024-07-29 10:00
comments: true
categories: [Database, AWS, RDS, Migration, PostgreSQL, Ruby, Rails]
canonical_url: https://www.smily.com/engineering/rds-database-migration-series---integrating-ruby-on-rails-applications-with-rds-proxy
---

In the [previous blog post](https://www.smily.com/engineering/rds-database-migration-series---facing-the-giant-how-we-migrated-11-tb-database), we covered our story of migrating a giant database of almost **11 TB.** Here comes the last part of the series—making Ruby on Rails applications work with RDS Proxy.

*I originally published this article on the [Smily Engineering Blog](https://www.smily.com/engineering/rds-database-migration-series---integrating-ruby-on-rails-applications-with-rds-proxy).*

<!--more-->

## Why use RDS Proxy in the first place?

Before migration, we were using [PgBouncer](https://www.pgbouncer.org/). We hosted multiple databases (for multiple applications) per cluster, and it was often the case that a single application required 300 or even 400 hundred connections alone. Hence, the connection pooler was a natural solution to the issues we had. We were really happy with it as it was simple to integrate with, and it did the job, yet we decided not to use PgBouncer anymore as AWS does not offer it as a managed service, and the entire point of migration was to not self-host database anymore. We were left then with **RDS Proxy** as the only available solution. It looked pretty straightforward to add, and since it was the dedicated option for **RDS,** we expected that things would work out-of-box, assuming that we keep the same config as for *PgBouncer* (which mainly was disabling prepared statements and using transaction-level advisory locks over session level ones). Well, it turned out that we were wrong.

## First issues with RDS Proxy

After trying out the **RDS Proxy** with the first application, it looked like the connection pooling did not work. When inspecting logs, we saw tons of warnings that looked like this:

```ruby
The client session was pinned to the database connection [dbConnection=1189232136] for the remainder of the session. The proxy can't reuse this connection until the session ends. Reason: SQL changed session settings that the proxy doesn't track. Consider moving session configuration to the proxy's initialization query. Digest: "set client_encoding to $1".
```

Connection pinning means that the connection cannot be reused, which explains why it looked like the proxy didn't work, especially since the problem was the *initialization query*.

Thanks to some [available articles](https://medium.com/@andre.decamargo/rds-proxy-and-connection-pinning-d26efcadb53c) and existing [Github](https://github.com/ged/ruby-pg/issues/368) [issues](https://github.com/rails/rails/issues/40207), we figured out that we needed to move some config parts from the *pg* gem and Rails Postgres adapter to the RDS Proxy initialization query. "Moving" meant some heavy-monkey patching and adjusting some surprising [low-level config](https://github.com/ged/ruby-pg/issues/368) and setting *Encoding.default_internal* to a nil value, which *pg* gem depends on. However, it seems like the issue was fixed in *pg* 1.5.4, so making sure the gem is up-to-date will help avoid the problem.

## Fixing RDS Proxy - getting it right with the initialization query

We started addressing the issue one warning at at time, and it turned out that we had to adjust a couple of config parameters:

1. *client_encoding* - the one that was set in *pg* gem based on the *Encoding.default_internal*
2. *statement_timeout -* we used it as the extra config in *database.yml,* so we had to make sure that none of the *variables* were applied
3. *intervalstyle -* this one had to be adjusted in *ActiveRecord::ConnectionAdapters::PostgreSQLAdapter*
4. *client_min_messages -* same as above, we had to monkeypatch *ActiveRecord::ConnectionAdapters::PostgreSQLAdapter* and remove it
5. *standard_conforming_strings -* same as above
6. *timezone* again, same as above

This is what the final *init_query* looked like:

```ruby
init_query = "SET client_encoding TO unicode; SET statement_timeout TO 300000; SET intervalstyle TO iso_8601; SET client_min_messages TO warning; SET standard_conforming_strings TO on; SET timezone TO utc"
```

And it solved most of the issues!

## The remaining issue that we didn't address

There was only one problem remaining:

```

2023-09-06T08:28:13.685Z [WARN] [proxyEndpoint=default] [clientConnection=51706963] The client session was pinned to the database connection [dbConnection=973587044] for the remainder of the session. The proxy can't reuse this connection until the session ends. Reason: The connection ran a SQL query which exceeded the 16384 byte limit.

```

Unfortunately, there was no easy solution to that problem as it is a known limitation of RDS Proxy. However, the number of database connections was acceptable for us, so we stopped at this point.

## The final config for Rails applications

We've put everything into the single initializer and added some extra ENV variables for the more straightforward release and potential rollback if something goes wrong.

```ruby
# frozen_string_literal: true

return unless ENV.fetch("APPLY_CONFIG_FOR_RDS_PROXY", "false") == "true"

Encoding.default_internal = nil # for pg version >= 1.5.4 it's not necessary

class ActiveRecord::ConnectionAdapters::PostgreSQLAdapter
  private

  def exec_no_cache(sql, name, binds, async: false)
    materialize_transactions
    mark_transaction_written_if_write(sql)

    # make sure we carry over any changes to ActiveRecord.default_timezone that have been
    # made since we established the connection
    update_typemap_for_default_timezone

    type_casted_binds = type_casted_binds(binds)
    log(sql, name, binds, type_casted_binds, async:) do
      ActiveSupport::Dependencies.interlock.permit_concurrent_loads do
        # -- monkeypatch --
        # to use async_exec instead of exec_params if prepared statements are disabled

        if ActiveRecord::Base.connection_db_config.configuration_hash.fetch(:prepared_statements, "true").to_s == "true"
          Retryable.perform(times: 3, errors: [PG::ConnectionBad, PG::ConnectionException], before_retry: ->(_) { reconnect! }) do
            @connection.exec_params(sql, type_casted_binds)
          end
        else
          Retryable.perform(times: 3, errors: [PG::ConnectionBad, PG::ConnectionException], before_retry: ->(_) { reconnect! }) do
            @connection.exec(sql)
          end
        end
        # -- end of monkeypatch --
      end
    end
  end

  protected

  def configure_connection
    # if @config[:encoding]
    #   @connection.set_client_encoding(@config[:encoding])
    # end
    # self.client_min_messages = @config[:min_messages] || "warning"
    self.schema_search_path = @config[:schema_search_path] || @config[:schema_order]
    #
    # # Use standard-conforming strings so we don't have to do the E'...' dance.
    # set_standard_conforming_strings
    #
    # variables = @config.fetch(:variables, {}).stringify_keys
    #
    # # If using Active Record's time zone support configure the connection to return
    # # TIMESTAMP WITH ZONE types in UTC.
    # unless variables["timezone"]
    #   if ActiveRecord::Base.default_timezone == :utc
    #     variables["timezone"] = "UTC"
    #   elsif @local_tz
    #     variables["timezone"] = @local_tz
    #   end
    # end
    #
    # # Set interval output format to ISO 8601 for ease of parsing by ActiveSupport::Duration.parse
    # execute("SET intervalstyle = iso_8601", "SCHEMA")
    #
    # # SET statements from :variables config hash
    # # https://www.postgresql.org/docs/current/static/sql-set.html
    # variables.map do |k, v|
    #   if v == ":default" || v == :default
    #     # Sets the value to the global or compile default
    #     execute("SET SESSION #{k} TO DEFAULT", "SCHEMA")
    #   elsif !v.nil?
    #     execute("SET SESSION #{k} TO #{quote(v)}", "SCHEMA")
    #   end
    # end
  end
end
```

The initializer works with Rails 6.0+ versions.

Also, we added some extra *retryable* behavior as it turned out that for whatever reason (likely killing some idle connections), the RDS Proxy was randomly closing some connections. Reconnecting to the database seemed to solve most of the issues (although not all). Here is the code behind *Retryable* class:

```ruby
# frozen_string_literal: true

class Retryable
  def self.perform(times:, errors:, before_retry: ->(_error) {})
    executed = 0
    begin
      executed += 1
      yield
    rescue *errors => e
      if executed < times
        before_retry.call(e)
        retry
      else
        raise e
      end
    end
  end
end
```

## Conclusions

While integrating **Ruby on Rails applications** with **RDS Proxy** turned out to be way more complex than doing it with popular **connection poolers** such as [PgBouncer](https://www.pgbouncer.org/),* we managed to solve most (but not all) the issues we encountered with a single initializer on the applications' side and by fine-tuning the initialization query on the **RDS Proxy side**.
