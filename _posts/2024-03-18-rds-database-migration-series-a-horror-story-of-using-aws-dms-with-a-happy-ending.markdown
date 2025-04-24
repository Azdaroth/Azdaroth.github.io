---
layout: post
title: "RDS Database Migration Series - A Horror Story of Using AWS DMS with a Happy Ending"
date: 2024-03-18 10:00
comments: true
categories: [Database, AWS, RDS, Migration, PostgreSQL, DMS]
canonical_url: https://www.smily.com/engineering/rds-database-migration-series---a-horror-story-of-using-aws-dms-with-a-happy-ending
---

In the [previous blog post](https://www.smily.com/engineering/a-story-of-a-spectacular-success-intro-to-aws-rds-database-migration-series), an intro to our **database migration series**, we promised to tell the story of our challenges with [AWS Database Migration Service](https://aws.amazon.com/dms/), which turned out to be far from all sunshine and rainbows as it might initially seem after skimming through the documentation.

When we started using it, it went significantly downhill compared to expectations, with all the errors and unexpected surprises. Nevertheless, we made the migration possible and efficient with extra custom flows outside DMS.

*I originally published this article on the [Smily Engineering Blog](https://www.smily.com/engineering/rds-database-migration-series---a-horror-story-of-using-aws-dms-with-a-happy-ending).*

<!--more-->

## AWS Database Migration Service - what is it and how it works?

If you already have data in any storage system (within or outside AWS) and want to move it to the Amazon-managed service, using Database Migration Service is the way to go. That implies that it's not a tool just for migrating from self-managed PostgreSQL to AWS RDS as we used it - it's just one of the possible paths. In fact, AWS DMS supports an impressive list of [sources](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_Introduction.Sources.html) and [targets](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_Introduction.Targets.html), including non-obvious ones such as Redshift, S3 or Neptune.

For example, it's possible to migrate data from [PostgreSQL to S3](https://docs.aws.amazon.com/dms/latest/sbs/postgresql-s3datalake.html) and use AWS DMS for that purpose, which already gives an idea of how powerful the service can be.

Essentially, we can have two types of migrations:

1. **Homogenous** when the source and the target database are equivalent, e.g., migration from self-hosted PostgreSQL to AWS RDS PostgreSQL.
2. **Heterogenous -** when the source and the target database are different, e.g., migrating from Oracle to PostgreSQL

In our case, that was a homogenous migration (from PostgreSQL to PostgreSQL), which sounds way simpler compared to the heterogenous one (which is likely to require tricky schema conversions, among other things).

When performing the migration via AWS DMS, we also need a middleman between the source and target databases responsible for reading data from the source database and loading it into the target database.

There are two ways how we can work with that middleman:

1. AWS DMS Serverless - in that approach, AWS will take care of provisioning and managing the replication instance for us.
2. Replication instance - the management of the replication instance is entirely up to us in this case.

On top of that, we have three types of homogenous PostgreSQL migrations:

1. **Full load** AWS DMS uses native *pg_dump/pg_restore* for the migration process
2. **Full load + Change Data Capture (CDC) -** In the first stage**,** AWS DMS performs Full load (so pg_dump/pg_restore) and then switches to ongoing logical replication.
3. **CDC -** the process is based entirely on logical replication.

The choice here comes down mainly to the trade-off between simplicity and downtime. If you can tolerate some downtime (depending on the database size and type of data stored), a Full Load sounds like a preferential option, as fewer things can go wrong here—it's simpler. If it doesn't sound like a possible option, using CDC (with or without Full Load) is the only way to achieve near-zero downtime. However, the complexity might be a big concern here.

**The initial plan for migration and the first round of apps**

Our initial plan assumed that for applications where we can afford a downtime outside of business hours (like 3 or 4 AM UTC+1), we would proceed with the Full Load approach, and for applications where we cannot tolerate the downtime, that would be required to perform the entire migration, we would likely go with Full Load and CDC.

DMS Serverless also looked appealing as it would remove the overhead of managing the replication instance.

We tested that approach with staging apps, and all migrations were smooth - there were no errors, and the process was fast. The databases were tiny, which helped with the speed, but in the end, the entire process looked promising and frictionless.

So, we started with the migration of the production apps. The first few small ones were relatively fast yet substantially longer than the staging. But that made sense as the size was significantly greater - it was no longer a few hundred megabytes in size but rather a few gigabytes or tens of gigabytes.

Then, we got into far bigger databases, reaching over 100 GB. And this is where the severe issues began.

## AWS DMS Serverless nightmare

Before migrating any database, it's necessary to perform test migrations to get an idea of whether it will work at all and how much time it might take. It's even more critical for big databases to benchmark the process a few times to tell how long it will take. So, we did exactly that for the bigger databases and achieved promising and consistent results. The migrations were supposed to take quite a while, but that was still acceptable, so we proceeded and scheduled the longer migrations.

Then, we ran into the first significant issue. According to the previous benchmark, we consistently achieved a migration time below 1 hour while the database was under normal load during tests. And then, out of nowhere, with no traffic on the source database, it was taking almost 2 hours with no sign of being closed to finish! Based on the expected size of the target database that we knew from the test migrations, there was still a long way to go.

Sadly, we had to stop the migration process, bring the app back up and running on the original database cluster, and think about what went wrong. Overall, waking up after 5 AM and the extended downtime went for nothing. We tried to replicate the issue with another test migration, but it was working just fine, so we considered this an isolated incident and committed to performing another migration the next day, although for a different application, as we wanted to avoid extended downtime for two days in a row.

However, it wasn't any better during the next day. Even though the process took more or less what was expected based on the test, the database shrank from 267 GB to... 5332 MB! We expected the bloat there, but the bloat couldn't take the majority of the size. And it was a very different result from what we achieved during test runs.

The *migration status* inside AWS DMS UI was *Load Complete*, but after checking the number of records in the tables, it turned out all were empty!

That was another failed migration, the second in a row, without any apparent reason why it failed.

## Moving to Replication Instance

At that point, we concluded that the Serverless approach was not an option. It proved unreliable for bigger databases, and the lack of control over the process became an issue.

Fortunately, we had one more option left for the *Full Load* strategy - doing it via *Replication Instance*. It looked more complex, but at the same time, we had more control over the process.

We attempted the first migration, and wow, that was fast! It was way faster than Serverless, and all the records were there! That looked very promising. Except for the fact that all secondary indexes were missing! And foreign key constraints... And other constraints... And the sequences for generating numeric IDs! Literally everything was missing except for the actual rows...

We double-checked the configuration, and there was nothing about excluding constraints. Also, the config for *LOBs* was correct—a config param that one needs to be very careful about, as AWS DMS makes it easy for many data types to either not be migrated at all or truncated beyond a specific limit. And apparently, it's not only about *JSON* or *array* types but also *text* types*!*

We re-read the documentation to see what happens to the indexes during the migration, and we found very conflicting information, especially after our previous *Serverless* migrations, which migrated the indexes and constraints without any issues.

Let's see what AWS DMS documentation says about indexes:

- "AWS DMS supports basic schema migration, including the creation of tables and primary keys. However, AWS DMS doesn't automatically create secondary indexes, foreign keys, user accounts, and so on, in the target database." - how come it worked with Serverless then? Based on the documetation, this recommendation doesn't seem to apply to Replication Instance only.
- "For a full load task, we recommend that you drop primary key indexes, secondary indexes, referential integrity constraints, and data manipulation language (DML) triggers. Or you can delay their creation until after the full load tasks are complete." - here, it looks like indexes are indeed created automatically but it's recommended to drop them before loading the data.
- "AWS DMS creates tables, primary keys, and in some cases unique indexes, but it doesn't create any other objects that aren't required to efficiently migrate the data from the source. For example, it doesn't create secondary indexes, non-primary key constraints, or data defaults." - *some cases?* What does it even mean? And how does it match the behavior of the serverless approach?

Anyway, we found a reason why the migration was so fast. We also had to find a way to recreate all the missing constraints, indexes, and other things.

Fortunately, native tools helped us a lot. To get all the indexes and constraints, we used *pg_dump* with the *--section=post-data* option and then inlined the content of the dump and ran it directly from the Postgres console to have better visibility and control of the process. To bring back sequences, we used [this script](https://github.com/sinwoobang/dms-psql-post-data/blob/main/sequences_generator.sql). It was very odd that AWS DMS does not have any option to handle this—it's capable of migrating Oracle to Neptune, yet it's not capable of smoothly handling indexes for the Replication Instance strategy, even though it's a trivial operation.

After recreating all these items, the state of the application database looked correct according to our post-migration check script (which will be shared later)—all the indexes and constraints were there, and the record counts matched for all tables.

At that point, we concluded that we were ready for another migration. And it looked smooth this time! It went fast, and the state of the source and target databases looked correct. We could bring back the application using a new database.

It looked just perfect! At least until we started receiving very unexpected errors from Sentry: *PG::StringDataRightTruncation: ERROR: value too long for type character varying(8000) (ActiveRecord::ValueTooLong)*. Why did it stop working correctly after the migration? And where is this *8000* number coming from? Did AWS DMS convert the schema without saying anything about this?

We quickly modified the database schema to remove the limit, and everything returned to normal. However, we had to find out what had happened.

Let's see what the documentation says about schema conversion: "AWS DMS doesn't perform schema or code conversion". That clearly explains what happened! Another time where the documentation does not reflect the reality.

We couldn't find anything in the AWS DMS docs regarding the magic *8000* number for *character varying* type. However, we found [this](https://help.qlik.com/en-US/replicate/May2023/Content/Replicate/Main/Google%20Cloud%20SQL%20for%20PostgreSQL_Source/postgresql_data_types_source.htm) - docs for *Qlik* and the mapping between PostgreSQL types and Qlik Replicate data types. And it was there: *"CHARACTER VARYING - If no length is specified: WSTRING (8000)"*, which was precisely the case! More conversions were also mentioned, for example, `NUMERIC` -> `NUMERIC(28,6)`, which also happened for a couple of columns in our case.

It's not clear if the services are related anyhow but this finding is definitely an interesting one.

We haven't been able to confirm with 100% certainty why this exact magic number (8000) was applied here, but it's likely related to PostgreSQL page size, which is commonly 8 kB.

That was not the end of our problems, though. The content of the affected columns got truncated! To fix this, we had to look for all records with content over 8000 characters and backfill the data from the source database to the target database if it hadn't been updated yet on the new database.

We also had to do 3 more things:

1. Review all columns using *character varying* type and convert them to *text* type if any row contains over 8000 characters.
2. We no longer allow DMS to load the schema from the source database. Instead, we use *pg_dump* with the -*section=pre-data* option to have the proper schema.
3. Update our post-migration verification script to ensure that the schema stays the same.

## Establishing the flow that works

Until that point, the AWS DMS experience had been a horror story. Fortunately, this is where it stopped. We finally found a strategy that worked! The subsequent migrations were smooth, and I haven't experienced any issues after that. Even the migrations of databases closer to 1 TB went just fine - although they were a bit slow and required a few hours of downtime.

We could have achieved way better results in terms of minimizing the downtime by using CDC, but after our experience with a *Full Load*, which is the most straightforward approach, we didn't want to enable logical replication and let AWS DMS handle it to find out that yet another disaster happened - we lost trust in DMS and we wanted to stick to something that we know it works.

This approach worked well almost until the very end. The only friction we experienced with this final flow was the migration of the biggest database. We ran into a specific scenario where performance for one of the tables was far from acceptable, so we developed a simple custom service to speed up the migration. Yet, the other tables were perfectly migratable via DMS. Before the migration to RDS, that database was almost 11 TB, so it also required a serious effort to shrink its size before moving it to RDS.

We will cover everything we've done to prepare that database for the migration in the upcoming blog post, along with the custom database migration service.

The story might look chaotic, but that's for the purpose - even though we found a couple of negative opinions about AWS DMS, the magnitude of the problems wasn't apparent, so this is the article we wished we had read before all the migrations. Hopefully, it will help clarify that AWS DMS is a tool that looks magnificent, but at the time of writing this article, the quality in a lot of areas is closer to the open beta service rather than a production one that is supposed to deal with the business-critical assets - the data. Especially since AWS DMS proved incapable of handling the homogenous migration - we had to use *pg_dump*/*pg_restore* to make it work.

Nevertheless, if we were to migrate self-managed PostgreSQL clusters to AWS RDS one more time, we would use Database Migration Service again—we mastered the migration flow and understood the service's limitations to the extent that we would feel confident that we could make it work. And we developed a post-migration verification script that performs a thorough check to ensure that the target database's state is correct. Hopefully, after reading this article, you will be able to do the same thing without the problems we encountered in our migration journeys.

Here is the final list of hints and recommendations for using AWS DMS when performing homogenous migration from self-managed PostgreSQL to AWS RDS PostgreSQL:

1. Do not use AWS DMS Serverless for large databases. At the time of writing this article (before March 2024), it didn't prove to be a production-ready service. However, this might change in the future.
2. Use the AWS DMS Replication Instance approach, which you can manage on your own.
3. Execute the following steps for the migration:
    1. Use *pg_dump* with *-section=pre-data* to load the schema - do not allow AWD DMS to load the schema, or you will end up with unexpected schema conversions.
    2. Use Replication Instance only to copy the rows between the source and the target database.
    3. Use *pg_dump* with *-section=post-data* to load the indexes and constraints after loading all the rows.
    4. Rebuild sequences (for numeric IDs - it doesn't apply to UUIDs) by running [this script](https://github.com/sinwoobang/dms-psql-post-data/blob/main/sequences_generator.sql) on the source database and running the output on the target database.
4. Test the migration result with the following [Ruby/Rails script](https://gist.github.com/Azdaroth/1394e77eeb8eee59d80437642b18a549)—this is the final version of the script after all the problematic migrations.
5. Use either *Full LOB* mode or *Inline LOB* mode, or you will **lose** **data** for many columns, especially with *JSON, array, or text* types. We've managed to achieve the best performance using *Inline LOB* mode. [This script](https://gist.github.com/Azdaroth/1c4f6f5f1988f92413c7c7296c40da17) was quite handy for determining the config threshold size.
6. Use *parallel load*. The *range* type works especially well for large tables using numeric IDs, as it allows you to divide the rows into segments by the range of IDs.
7. If the source database can survive the high load during migration and there are many tables, aim for the highest value of *MaxFullLoadSubTasks* (maximum 49), which determines the number of tables that can be loaded in parallel.

## Conclusions

[Amazon Database Migration Service](https://aws.amazon.com/dms/) might initially seem like a perfect tool for a smooth and straightforward migration to [RDS](https://aws.amazon.com/rds/). However, our overall experience using it turned out to be closer to an open beta product rather than a production-ready tool for dealing with a critical asset of any company, which is its data. Nevertheless, with the extra adjustments, we made it work for almost all our needs.

Stay tuned for the next part of the series, where we will focus on preparing the enormous database for the migration and a very particular use case where our custom simple database migration tool was far more efficient than DMS (even up to 20x faster in a benchmark!) allowing us to migrate one of the databases simultaneously using both AWS DMS and our custom solution for different tables.
