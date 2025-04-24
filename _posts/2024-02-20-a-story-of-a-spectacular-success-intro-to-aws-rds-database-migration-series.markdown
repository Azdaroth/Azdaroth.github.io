---
layout: post
title: "A Story of a Spectacular Success - Intro to AWS RDS Database Migration Series"
date: 2024-02-20 10:00
comments: true
categories: [Database, AWS, RDS, DMS, Migration, PostgreSQL]
canonical_url: https://www.smily.com/engineering/a-story-of-a-spectacular-success-intro-to-aws-rds-database-migration-series
---

In recent months, one of our most significant initiatives was migrating from our self-managed PostgreSQL clusters to the managed service on Amazon - AWS RDS. Overall, we managed to migrate 5 database clusters of 54 applications (including staging ones), several of which had a size of close to 1 TB, and one giant cluster with a single database of a massive size - 11 TB, which required a lot of extra work to make it migratable - otherwise, it would have taken an unacceptably long time to migrate it. Not to mention the cost of keeping that storage

Overall, we migrated a considerable amount of data, and the initiative turned out to be way more complex than anticipated. We've received very little support from AWS Developer Support service, and what is the trickiest part - the docs for Database Migration Service (AWS DMS) seemed to be  poorly written - some parts were vague or it was not clear to which type of a strategy of migration they are referring to ("AWS DMS creates only the objects required to efficiently migrate the data: tables, primary keys, and in some cases, unique indexes." - *some cases*? ). Some migration strategies rarely ever worked (*AWS DMS Serverless* - I'm looking at you) - they often ended up with errors that didn't say anything about what went wrong, and the way to deal with it was to try enough times - not exactly the smoothest path for migrating a production database! And that is just for the Database Migration Service - we had to make our Rails applications also work with AWS RDS Proxy, which was another challenge!

*I originally published this article on the [Smily Engineering Blog](https://www.smily.com/engineering/a-story-of-a-spectacular-success-intro-to-aws-rds-database-migration-series).*

<!--more-->

Although many things didn't go well, we managed to figure out a very robust and stable migration process, even for databases close to 1 TB in size. The end outcome turned out to be way beyond expectations. Not only did we substantially decrease the costs for AWS infra, which may seem counter-intuitive, but few databases were 50% of the pre-migration size - thanks to getting rid of all the bloat that had been accumulated for years, especially prior to introducing retention policies. And the biggest one, after the deep rework, turned out to be... slightly over 3% of its original size! Yes, from 10.9 TB to  347 GB! And all of this is on top of the great advantages that RDS brings!

There is much to share and learn from these migrations. Hopefully, you will find this series helpful and will be able to assess whether migration to AWS RDS could be a good choice for you and what to expect from the process, which can play a massive role here.

This article will focus on why we decided to migrate to AWS RDS with an extra overview of our infrastructure, its scale, and the challenges we used to have. In the next ones, we are going to move on to the following cases:

1. **AWS DMS (Database Migration Service)** - all the issues we've faced, strategies we tried and one that worked for us most of the time, odd things in the documentation we encountered, and the final script we used to verify if the migration went as expected (why we even needed it in the first place is also going to be covered)
2. **Our custom Database Migration service** - AWS DMS, is a general-purpose tool that will be adequate for most use cases but not all of them. We ran into two very specific scenarios where a self-built service allowed us to achieve a way better result (even 20x faster than AWS DMS!).
3. **RDS Proxy and how to make it work Ruby on Rails** - don't expect things to work out of the box, even if everything was perfectly fine when using *pgbouncer* as a connection pooler. There are extra things you will need to do to make it work, including monkey patching that looks highly questionable at first glance. Fortunately, it works without any issues.
4. **How to prepare for the migration of the almost 11 TB Postgres database** - ideally, you would never have a single PostgreSQL database that is as huge, but if that happens, there are certain things you might consider doing or what to prevent knowing that you can also end up in a similar situation. We will show what was enough for us and also discuss potential alternatives we considered.
5. **Extra insights from our infrastructure team** - what it took to integrate RDS with the rest of the infrastructure, how we made the RDS proxy work (and debugged its issues), and a couple of extras, like a more detailed integration with Datadog for low-level metrics.

For now, let's discuss how we ended up here.

## **Our infrastructure before (not only) AWS RDS migration**

Before discussing self-managed PostgreSQL clusters, let's look back even further to the past to gain more context about our experience with self-managed services.

We've been using AWS EC2 instances with self-managed components (Redis, PostgreSQL, Kubernetes...) for years, all bound by Chef, with occasional exceptions such as AWS MSK for Kafka or CloudAMQP for RabbitMQ. We had been quite satisfied with that approach, mainly when operating on a much smaller scale. As we grew, we started to experience various issues that kept getting worse.

The greatest source of problems used to be our platform based on [Deis/Hephy Workflow](https://github.com/teamhephy/workflow), backed by Kubernetes. Not only did we have a lot of maintenance burden when it came to Kubernetes itself, especially upgrading it - and this matters a lot for a tiny infrastructure team that has a lot of other components to maintain - but we also significantly outgrew Deis itself, and working with it became a nightmare. Deployments for bigger applications with over 100 Docker containers were randomly failing, which is quite a big issue if the deployment takes over 30 minutes. Sometimes, the only way to make it work was to add extra computing power via provisioning an extra EC2 node. Since we didn't have autoscaling capabilities back then, you can only imagine how painful it was. On top of that, we had issues with [etcd](https://etcd.io/) that used to cause the greatest problems in the middle of the night, triggering Pager Duty, especially when it was under a high load, and the way to deal with it was to significantly over-provision resources for the potential load spikes.

The conclusion was clear - we had to migrate from both self-managed Kubernetes and Deis/Hephy. Given the complexity of our ecosystem of apps, keeping Kubernetes as an orchestrator was a natural choice. So was AWS EKS - Elastic Kubernetes Service. To our surprise, not only was the maintenance simpler, but it also seemed to be significantly cheaper compared to self-managed one on EC2 nodes (especially when considering overprovisioned instances for *etcd* as well). That's how we managed to finish the migration in March 2023 to our new platform based on [EKS](https://aws.amazon.com/eks/), [Helm](https://helm.sh/), [ArgoCD](https://argo-cd.readthedocs.io/en/stable/), and [Jenkins](https://www.jenkins.io/), and the results have been amazing.

## PostgreSQL clusters prior to migration

Even though we achieved significant success with that massive initiative, that was not the end of our problems. PostgreSQL cluster maintenance started becoming a huge issue (sound familiar already?). Since we were hosting multiple databases on a single cluster, we are talking about several terabytes per cluster. Plus, one single application, which at that time started to get close to 10 TB. Performing any version upgrade was a challenging experience because we were afraid of doing maintenance work there - if it's not broken, better not touch it. Especially after one of the incidents when *the pg_wal* directory started to grow uncontrollably due to the archiver getting stuck without any exit code, reaching over 1 TB size. Fortunately, it eventually self-healed, yet that made a decision for us clear - we were at the scale where managing massive PostgreSQL clusters by a tiny infrastructure team was no longer an option, and we prioritized a migration to managed PostgreSQL service under AWS RDS, especially that doing so for Kubernetes turned out to be an ideal choice.

If that wasn't enough, there were even more reasons why the migration was a good idea. Our monthly AWS invoices were huge! Not only for EC2 instances but mostly the parts concerning Data Transfer (between regions) and EBS volumes. Things started to get interesting when we began estimating the costs of RDS clusters. The results were very promising - it turned out that RDS won't be more expensive! If anything, it had a great potential to be significantly cheaper - especially knowing that we had a vast database bloat in most of the applications, so migrating to a new database could be a solution. You might think that performing *vacuum full* (which would require an extended downtime of the application or a part of it) or using [pg_repack](https://github.com/reorg/pg_repack) **(doesn't require exclusive locks but using it for enormous tables might not be trivial) **would also solve the problem with the bloat even without any migration but not necessarily - yes, the bloat would be gone. But we would still be paying for the allocated EBS volumes as the storage cannot be deallocated - it only goes up. If we tried hard enough, we could figure out a migration path to a new EBS volume and copy the existing data after reducing the bloat and replacing the original one, but this would merely address one of the items in the long list of problems (without considering the complexity of doing that).

What is more, we could start using instances powered by AWS Graviton processors, so there was also a good chance that the costs would be even lower as we would be likely able to use a smaller size of the instance compared to the legacy infra.

There is also one more thing that is not considered very often - Disaster Recovery.

## Disaster Recovery

Disaster recovery is a critical aspect of database maintenance that is neglected way too often. Putting aside the incident response plan for such occasions, it gets tricky when you have tens of terabytes of data, tens of databases, and multiple clusters. At that scale, it will most likely involve a combination of taking EBS snapshots (e.g., once or twice per day) and storing WAL files to be replayed to get the latest possible state of the database.

A key question at that point: how easy it could be for a small team of infra developers (who also need to maintain a lot of other components) who are not Postgres experts to maintain backups properly and test and improve the procedure often enough to achieve a decent Recovery Point Objective (RPO - how much data we can lose, measured by time) and Recovery Time Objective (RTO - how much time it takes to bring the database back)? Let's say that it would be challenging.

It would ideally be something where we could minimize our involvement. Clearly, it cannot be fully "delegated" to a managed service - even if it took just one click from UI to recover, it would still require an intervention, so using a managed service doesn't remove a necessity to maintain a proper Disaster Recovery plan. However, AWS RDS massively simplifies it.

First of all, we don't need to know the deep details of restoring from the EBS snapshot and replay WAL Files or any low-level procedures like that - AWS has our back here and provides proper tools for that purpose and a convenient interface so that we can focus on a bigger picture.

It also makes it trivial to achieve a very decent RPO - with *automated backups,* it would be at most 5 minutes. For less drastic scenarios (like an outage of the master database instance), we have options such as [Multi-AZ](https://aws.amazon.com/rds/features/multi-az/) offering a standby instance.

Disaster Recovery with RDS could use a separate article, and I would definitely recommend the [one from AWS blog](https://aws.amazon.com/blogs/database/implementing-a-disaster-recovery-strategy-with-amazon-rds/). Nevertheless, the conclusion is clear - with minimum involvement, we can have a decent Disaster Recovery plan and make it excellent with an extra effort.

That was yet another reason why we should consider AWS RDS.

## Final decision and the results

The final decision was made: perform a homogenous (from PostgreSQL to PostgreSQL) migration to AWS RDS. We were also considering using a different engine, such as [Aurora](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/CHAP_AuroraOverview.html), which is compatible with PostgreSQL. It offers interesting benefits but would likely be more expensive than RDS PostgreSQL. It would also potentially increase the complexity of the migration and make a vendor lock-in even stronger, so sticking to PostgreSQL seemed like the most optimal choice.

And that was definitely the case! In the end, with migration to RDS, we achieved the following results:

1. Drastically **simpler maintenance**
2. **Superior** Disaster Recovery
3. Significantly smaller databases' size - for some of them, approximately **40%-50% smaller** thanks to eliminating the database bloat and, in one of the cases, a reduction by close to 97%, **from almost 11 TB to less than 350 GB**.
4. Overall **reduction** of AWS **costs** by close to **30%** - yes, it's better and so much cheaper!

Sounds exciting? If so, stay with us for the rest of the story.

## Wrapping Up

Moving **terabytes of data** and **tens of PostgreSQL databases** to **AWS RDS** service was a massive and complex initiative. As per our research and post-migration metrics, the effort was indeed proven worth it, with certain outcomes greatly exceeding our expectations - the **result is superior** in many aspects compared to self-managed clusters, including way **lower infrastructure costs**! Follow this series to learn if this might be a good choice for you and what to expect along the way.
