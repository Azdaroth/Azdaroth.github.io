---
layout: post
title: "RDS Database Migration Series - Facing the Giant: How We Migrated 11 TB Database"
date: 2024-05-13 10:00
comments: true
categories: [Database, AWS, RDS, Migration, PostgreSQL]
canonical_url: https://www.smily.com/engineering/rds-database-migration-series---facing-the-giant-how-we-migrated-11-tb-database
---

In the [previous blog post](https://www.smily.com/engineering/rds-database-migration-series---a-horror-story-of-using-aws-dms-with-a-happy-ending), we covered our story of migrating to **AWS** **RDS** using **AWS Database Migration Service (DMS)**, a complex initiative with multiple issues we had to address.

Nevertheless, almost all the migrations we did could have been generalized to the same strategy - in the end, we found a way to use **DMS** that works fine, even for mid-size databases.

One database, though, required some extra preparation - the 11 TB giant (10.9 TB to be exact). Despite all the steps we took, it was not possible to migrate via **AWS DMS** via full load within an acceptable time, even when applying parallel load. In that case, we had to develop our custom migration script, which turned out to be almost **20 times faster** than **AWS DMS.**

Even more surprising is that the database shrunk to **3.1% of its original size** after the migration!

Let's review all the steps we took to prepare this giant database for the migration and what our custom migration script exactly looked like.

*I originally published this article on the [Smily Engineering Blog](https://www.smily.com/engineering/rds-database-migration-series---facing-the-giant-how-we-migrated-11-tb-database).*

<!--more-->

## How did we get to 11 TB of Postgres database in the first place?

Before we get into the details, let's start by explaining how we got to the point where the database was so massive.

The primary culprits were **two tables** (and their huge indexes) that contributed approximately **90%** to the total size of the database. One of them was an audit trail ([paper trail](https://github.com/paper-trail-gem/paper_trail) versions, to be exact), and the second one was more domain-specific for short-term rentals. It's a pre-computed cache of prices for properties depending on various conditions so that they don't need to be computed each time on the fly and can be easily distributed to other services.

In both cases, the origin of the problem is the same, just with a slightly different flavor—trying to store as much as possible in the Postgres database without defining any reasonable retention policy.

The tricky part is that we couldn't just delete some batch records after a certain period defined by a retention policy. We had to keep some paper trail versions forever. And for the computed cache, we still had to preserve many computation results for an extended period to debug potential problems.

That doesn't mean we had to keep them in the Postgres database, e.g., **AWS S3.** Pulling data on demand (and removing them once no longer needed) is an alternative that may take some extra time to develop, but it's much more efficient.

This is what we did to a considerable extent for the records representing pre-computed prices; we started archiving shortly after they were no longer applicable by pushing them to S3, deleting them from the Postgres database, and pulling data on demand when debugging was needed (and deleting them again when no longer required).

We also applied a retention policy for paper trail versions and archived the records by uploading them to S3 and deleting them from the Postgres database. However, we also decided to split the giant unpartitioned table into several tables (one generic one as a catch-all/default table and a couple of model-specific tables for the most important models), essentially introducing partitioning by model type. Due to that split/partitioning, we temporarily increased the total size of the database. Still, we could ignore the original table during the migration and, at the same time, make migration via **AWS DMS** faster by simplifying parallelization during the *full load*.

The interesting realization is that the majority of the data we stored were historical records, which are not critical business data.

Overall, we deleted a massive amount of records from the Postgres database. However, the database size didn't change at all. Not even by a single gigabyte!

What happened?

## I have a massive database. Now what?

If you are in a similar situation, you will likely have a big issue to solve. This is due to a few reasons:

1. Deleting records from Postgres does not make the table smaller (and neither *vacuum* does, at least not a normal one).
2. While there are multiple ways to shrink table size after deleting many records, they are usually complex.
3. Even if you manage to shrink the size of massive tables or even delete them completely, you are still likely to keep paying the same price for the storage - if you use, e.g., **AWS EBS** volumes, you cannot shrink them; you can only increase their size.
4. At that point, you will likely need to migrate to a new **EBS** volume (or equivalent). If you don't use a managed service, you could solve the problem like we did and migrate to **AWS RDS.**

Let's look at all these issues closer.

It is essential to remember that deleting records in the Postgres database does nothing to reduce the table size—it only makes the records no longer available. However, running *vacuum* marks the internal tuples from deleted rows as reusable for the future. So, it does slow down the table's growth (as a part of already allocated storage is reusable), yet we can't expect the size to go down.

Nevertheless, there are multiple ways to shrink the table size:

1. Use *vacuum full -* the most straightforward option (as it's a matter of running a single command), yet the most dangerous one. Not only does it require an exclusive lock for the entire table for a potentially very long time, but it also requires more disk space initially, as it will create a copy of the table without the deleted records.
2. Using an extension that provides similar functionality but does not acquire an exclusive lock on the entire table - [pg_repack](https://reorg.github.io/pg_repack/) is a popular solution.
3. Copy the data to the new table and delete the old one - that one cannot be solved by running a single simple command but is potentially the safest one and offers the most flexibility as there are many ways how you can import the data from one table to another, keep them in sync for a while and delete the previous table.

While we have several solutions to the problem, the sad reality is that if we use block-storage services such as **AWS EBS**, we will still pay the same price for the allocated storage, which cannot be deallocated.

If the price is an issue, the options we could consider at this point would be moving data to a smaller EBS volume or migrating to a new cluster. We went with the second option as it naturally fit our plan to move from self-managed clusters to the AWS-managed service (**AWS RDS**).

## Benchmarking the migration with AWS DMS - not that smooth this time.

After all the hard work in preparing the database for migration, we did a test benchmark to see how long it would take. And it looked very promising initially - almost all the tables migrated in approximately 3 hours. All except the one - the table that stored the results of computed prices. After close to 5.5 hours, we gave up, as this was an unacceptable time for just a single table. 5 hours would be fine for the entire downtime window, including the indexes re-creation, not just migrating a single table on top of 3 hours that it took to migrate the rest of the database.

That was a big surprise - the original table was huge (2.6 TB), but we deleted over 90% of the records, so we expected the migration to be really fast. Especially with the *parallel load*!

However, most of the storage space was occupied by *LOBs—*the array of decimals (prices)—which could have been the primary cause behind the slowness. Most likely, the massive bloat after deleting such a big part of the table didn't help. And probably the most crucial reason is that there is a limit to how much we can parallelize the process. The maximum full load subtasks number allowed on **AWS DMS** is 49.

At that point, we had to figure out some custom solution, as we didn't want to change the migration strategy from just the *full load* to the combination of *full load* and *CDC.* The good news was that we had already been using something that could be very useful in designing a custom solution - performing a bulk insert (using [activerecord-import](https://github.com/zdennis/activerecord-import)) of the archived records. It proved to be fast enough to restore a significant number of records. Also, nothing was preventing us from having a way higher parallelization degree than **DMS.** This could be our solution.

## Custom migration script to the rescue

We had to do a couple of tweaks to reuse the functionality we implemented to restore the archived records. Not only the source of the data would be different (from S3 to Postgres database), but there were also important considerations:

- The entry point for running the process would be scheduling a Sidekiq job from the *rails console*.
- We had to make it easily parallelizable by allowing a huge number of Sidekiq workers to process independent migration jobs.
- To make it happen, the optimal way would be using ID ranges as arguments per job, especially if the table had a numeric (*bigint*) primary key (that would not be so simple when using *uuid*)
- However, given the massive number of records, we could not afford to have a single process scheduling jobs sequentially one by one for the consecutive ranges. That way, scheduling these jobs could become a bottleneck.
- To satisfy the requirement from the previous point, we could take the range between minimum and maximum ID from the table and split it into giant buckets. By further dividing these buckets, we could have jobs that would schedule other jobs.
- In the end, we would have two types of jobs:
    1. Schedulers - operating on huge batches that would be splitting them into smaller ones, and each of the sub-buckets would be used as an argument for the second type of job
    2. Migrators - the jobs that would be calling the actual operation that knows how to perform the migration

And this is how we did it:

1. The scheduler job:

``` rb
# frozen_string_literal: true

class DatabaseMigration::ScheduleIdsRangeMigrationStrategyJob
  include Sidekiq::Worker

  sidekiq_options queue: :default

  def self.enqueue(table_name, id_column, source_db_uri_env_var_name, target_db_uri_env_var_name, min_id, max_id,
    sub_range_size_for_data_migration, batch_size_per_job)

    current_index = 0
    current_min_id = 0
    while current_min_id <= max_id
      current_min_id = (min_id + (batch_size_per_job * current_index))
      maximum_possible_end_id = current_min_id + batch_size_per_job - 1
      current_max_id = [maximum_possible_end_id, max_id].min

      perform_async(table_name, id_column, source_db_uri_env_var_name, target_db_uri_env_var_name, current_min_id,
        current_max_id, sub_range_size_for_data_migration)
      current_index += 1
    end
  end

  def perform(table_name, id_column, source_db_uri_env_var_name, target_db_uri_env_var_name, start_id, end_id,
    sub_range_size_for_data_migration)
    DatabaseMigration::IdsRangeMigrationStrategyJob.enqueue(table_name, id_column, source_db_uri_env_var_name,
      target_db_uri_env_var_name, start_id, end_id, sub_range_size_for_data_migration)
  end
end
```

2. The migration job:

``` rb
# frozen_string_literal: true

class DatabaseMigration::IdsRangeMigrationStrategyJob
  include Sidekiq::Worker

  sidekiq_options queue: :default

  def self.enqueue(table_name, id_column, source_db_uri_env_var_name, target_db_uri_env_var_name, min_id, max_id,
    sub_range_size = 1000)

    (min_id..max_id).each_slice(sub_range_size).lazy.each do |range|
      perform_async(table_name, id_column, source_db_uri_env_var_name, target_db_uri_env_var_name, range.first,
        range.last)
    end
  end

  def perform(table_name, id_column, source_db_uri_env_var_name, target_db_uri_env_var_name, start_id, end_id)
    DatabaseMigration::IdsRangeMigrationStrategy
      .new(id_column: id_column, table_name: table_name, source_database_uri: ENV.fetch(source_db_uri_env_var_name),
        target_database_uri: ENV.fetch(target_db_uri_env_var_name))
      .migrate(start_id, end_id)
  end
end
```

3. The operation performing the actual migration:

``` rb
class DatabaseMigration::IdsRangeMigrationStrategy
  attr_reader :id_column, :table_name, :source_database_uri, :target_database_uri, :batch_size
  private     :id_column, :table_name, :source_database_uri, :target_database_uri, :batch_size

  def initialize(id_column:, table_name:, source_database_uri:, target_database_uri:)
    @id_column = id_column
    @table_name = table_name
    @source_database_uri = source_database_uri
    @target_database_uri = target_database_uri
    @batch_size = ENV.fetch("DMS_IDS_RANGE_STRATEGY_BATCH_SIZE", 1000).to_i
  end

  def migrate(start_id, end_id)
    source_model.where(id_column => [start_id..end_id]).in_batches(of: batch_size).lazy.each do |records_batch|
      target_model.import(records_batch.map(&:attributes), on_duplicate_key_ignore: true)
    end
  end

  private

  def source_model
    @source_model ||= Class.new(ApplicationRecord) do
      def self.name
        "SourceModelForIdsRangeMigrationStrategy"
      end
    end
      .tap { |klass| klass.table_name = table_name }
      .tap { |klass| klass.establish_connection(source_database_uri) }
  end

  def target_model
    @target_model ||= Class.new(ApplicationRecord) do
      def self.name
        "TargetModelForIdsRangeMigrationStrategy"
      end
    end
      .tap { |klass| klass.table_name = table_name }
      .tap { |klass| klass.establish_connection(target_database_uri) }
  end
end
```

Take a few minutes to analyze how things work exactly.

Running the entire process was limited to merely executing this code:

``` rb
table_name = TABLE_NAME
id_column = "id"
source_db_uri_env_var_name = DMS_SOURCE_DATABASE_URL
target_db_uri_env_var_name = DMS_TARGET_DATABASE_URL
min_id = MIN_ID # from YourSourceModel.minimum(:id)
max_id = MAX_ID # from YourSourceModel.maximum(:id)
batch_size_per_job = 100_000_000 # the big batch size
sub_range_size_for_data_migration = 500_000 # the sub-batch size

DatabaseMigration::ScheduleIdsRangeMigrationStrategyJob.enqueue(table_name, id_column, source_db_uri_env_var_name, target_db_uri_env_var_name, min_id, max_id, sub_range_size_for_data_migration, batch_size_per_job) ; nil
```

And it was really that simple to implement an alternative solution to **AWS DMS!** We did a test benchmark, and it turned out that with a comparable parallelization (50 Sidekiq workers), it took close to 45 minutes, so it was perfectly fine for our needs! Even more interesting was that there was no significant database load increase, even while running it on the production database actively processing standard workload. The potential for parallelization was even greater, which we wanted to see in action during the last migration.

## Performing the final migration

And this day finally came - facing the 11 TB giant. Fortunately, the migration went perfectly fine! The entire process took approximately 5 hours (the actual downtime). And there were even more things to celebrate!

The migration of the troublesome table took merely **18 minutes** with **125 Sidekiq workers**! We haven't tried going beyond 5.5 hours for this table using **AWS DMS,** but even assuming that it would be the final load time, our custom migration script that took a few hours to build turned out to be **almost 20x faster** (18.3, to be precise). And there was plenty of room to optimize it even further - for example, we could play with different buckets sizes' and also run the process with 200 Sidekiq workers. Furthermore, we don't know how long it would take **AWS DMS** to finish the process - maybe it could be 6 or 7 hours. It would not be impossible then to have a custom process that would be 30x or even 40x faster.

And there was one more thing—the database size after the migration turned out to be merely **347 GB,** which is **3% of the original size**! Reducing all the bloat definitely paid off.

## Conclusions

Ultimately, we managed to migrate the colossus, which started as an **11 TB giant** and became a mid-size and well-maintained database of **347 GB** (**3.1% of the original size**). That was a challenging initiative, yet thanks to all the steps we took, we managed to shrink it massively and migrate it during a reasonable downtime window. However, it wouldn't have been possible without our custom migration script, which we used together with **the AWS DMS full load**.

Stay tuned for the next part, as we will provide a solution for making [AWS RDS Proxy](https://aws.amazon.com/rds/proxy/) work with Rails applications, which was not that trivial.
