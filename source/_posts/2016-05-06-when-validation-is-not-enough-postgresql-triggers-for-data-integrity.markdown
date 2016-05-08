---
layout: post
title: "When validation is not enough: PostgreSQL triggers for data integrity"
date: 2016-05-06 19:45
comments: true
categories: [PostgreSQL, Database, ActiveRecord, Quick Tips, Patterns, Triggers]
---

<p>Is <strong>validation</strong> in your models or form objects enough to ensure <strong>integrity of the data</strong>? Well, seems like you can't really persist a record when the data is <strong>not valid</strong> unless you intentionally try to bypass validation using <code>save: false</code> option when calling <code>save</code> or using <code>update_column</code>. What about <strong>uniqueness validation</strong>?
A classic example would be a unique <code>email</code> per user. To make sure the email is truly unique we could add a unique index in database - not only would it prevent saving non-unique users when <strong>bypassing validation</strong>, but also it would raise extra error when 2 <strong>concurrent requests</strong> would attempt to save user with the same email. However, some validations are more complex that ensuring  a value is unique and index won't really help much. Fortunately, PostgreSQL is powerful enough to provide a perfect solution to such problem. Time to meet your new friend: <strong>PostgreSQL triggers</strong>.</p>

<!--more-->

<h2>Anatomy of PostgreSQL triggers and procedures</h2>

<p>PostgreSQL trigger is like a callback: it's a function that is called on specific event: <code>before</code> or </code>after</code> <code>insert</code>, <code>update</code>, <code>delete</code> or <code>truncate</code> in case of tables and views and for views you can also run a function <code>instead of</code> those events. Triggers can be run either <code>for each row</code> (tables only) and <code>for each statement</code> (both tables and views). The difference between them is quite simple: <code>for each row</code> is run for every modified row and <code>for each statement</code> is run only once per statement. The important thing to keep in mind regarding <code>for each row</code> is that you have a reference to the row being modified, which will be essential in upcoming example.</p>

<p>By running <code>\h CREATE TRIGGER;</code> from <strong>psql</strong> we can get a generalized syntax for creating triggers:</p>

```
Command:     CREATE TRIGGER
Description: define a new trigger
Syntax:
CREATE [ CONSTRAINT ] TRIGGER name { BEFORE | AFTER | INSTEAD OF } { event [ OR ... ] }
    ON table_name
    [ FROM referenced_table_name ]
    [ NOT DEFERRABLE | [ DEFERRABLE ] { INITIALLY IMMEDIATE | INITIALLY DEFERRED } ]
    [ FOR [ EACH ] { ROW | STATEMENT } ]
    [ WHEN ( condition ) ]
    EXECUTE PROCEDURE function_name ( arguments )

where event can be one of:

    INSERT
    UPDATE [ OF column_name [, ... ] ]
    DELETE
    TRUNCATE
```

<p>You can also add a <b>condition</b> for running <strong>triggers</strong> and timing option, which I'm not going to discuss in greater details, you can find more about them in official <a href="http://www.postgresql.org/docs/9.5/static/sql-createtrigger.html" target="_blank">docs</a>.</p>

<p>What about <code>function_name</code>? It's a user-defined function returning <code>trigger</code>. Here's a dummy example to give an idea about the syntax for defining functions:</p>

```
CREATE FUNCTION dummy() RETURNS trigger AS $$
DECLARE
    some_integer_variable int;
BEGIN
    some_integer_variable := 1;
    NEW.counter := some_integer_variable;
    RETURN NEW;
END;
$$ language plpgsql;
```

<p>We started with defining <code>dummy</code> function taking no arguments returning type of <strong>trigger</strong>. Next, we have a <code>DECLARE</code> block where we declare temporary variables, in our case it's <code>some_integer_variable</code> of type <code>int</code>. Within <code>BEGIN / END</code> block we define the actual function body: we assign a dummy value to <code>some_integer_variable</code> variable using <code>:=</code> operator and then we do some assignment using implicit <code>NEW</code> variable which is basically a row referenced by given statement. This variable is available only when running a trigger <code>for each row</code>, otherwise it will return <code>NULL</code>. Any trigger has to return either a <strong>row</strong> or <code>NULL</code> - in this example we return <code>NEW</code> row. At the end we have a declaration of writing function in <code>plpgsql</code> language.</p>

<p>Let's take a look at some real world code to see triggers in action.</p>

<h2>Using triggers for data integrity</h2>

<p>A good example where we could use a trigger for more complex validation could be a calendar event: we need to ensure that no other event exists between some <code>begins_at</code> time and <code>finishes_at</code> time. We should also scope it only to a given calendar and exclude id of event being updated - when creating new events it wouldn't matter, but without excluding id we wouldn't be able to update any event. So what we actually want to achieve is to create a trigger that will be run <code>before insert or update</code> on <b>events</b> table <code>for each row</code>.</p>

<p>Let's start with generating <code>Calendar</code> model and <code>Event</code> model with reference to <code>calendar</code> and <code>begins_at</code> and <code>finishes_at</code> attributes:</p>

```
rails generate model Calendar
rails generate model Event calendar_id:integer begins_at:datetime finishes_at:datetime
```

<p>and also generate extra migration adding <strong>trigger</strong> and <strong>procedure</strong> ensuring that only one event can be created for given period of time for a calendar:</p>

```
rails generate migration add_validation_trigger_for_events_availability
```

<p>add the SQL code :</p>

``` ruby
class AddValidationTriggerForEventsAvailability < ActiveRecord::Migration
  def change
    execute <<-CODE
      CREATE FUNCTION validate_event_availability() returns trigger as $$
      DECLARE
        events_count int;
      BEGIN
        events_count := (SELECT COUNT(*) FROM events WHERE (
          events.calendar_id = NEW.calendar_id AND events.begins_at < NEW.finishes_at AND events.finishes_at > NEW.begins_at AND events.id != NEW.id
        ));
        IF (events_count != 0) THEN
          RAISE EXCEPTION 'Period between % and % is already taken', NEW.begins_at, NEW.finishes_at;
        END IF;
        RETURN NEW;
      END;
      $$ language plpgsql;

      CREATE TRIGGER validate_event_availability_trigger BEFORE INSERT OR UPDATE ON events
      FOR EACH ROW EXECUTE PROCEDURE validate_event_availability();
    CODE
  end
end
```

<p>Our <code>validate_event_availability</code> function performs query to count all events that are between given time period for specified calendar excluding own id (so that the row being updated is not considered here, which would prevent updating any event). If any other event is found, the exception is raised with an error message - <code>%</code> characters are used for interpolation of <code>begins_at</code> and <code>finishes_at</code> attributes. If no other event is found, we simply return the row.</p>

<p>We want to define a trigger running this function before creating any new event or updating existing ones, so we need to run it <code>BEFORE INSERT OR UPDATE</code> <code>FOR EACH ROW</code>.</p>

<p>It might be a good idea to switch also to <code>:sql</code> schema format - the standard <code>:ruby</code> format can't handle triggers at this point. Add this line in <code>config/application.rb</code>:</p>


``` ruby
# config/application.rb
config.active_record.schema_format = :sql
```

<p>Now we can run migrations:</p>

```
rake db:migrate
```

<p>After changing the schema format, new <code>structure.sql</code> file should be created. It's not going to look that nice like <code>schema.rb</code>, but at least it contains all the details. Let's try creating some events from <code>rails console</code>:</p>

``` ruby
calendar = Calendar.create
begins_at = "2016-05-02 12:00:00"
finishes_at =  "2016-05-02 16:00:00"
Event.create(calendar_id: calendar.id, begins_at: begins_at, finishes_at: finishes_at)
```

<p>Creating first event obviously works, but what's going to happen when we try to create an event with exactly the same dates?</p>

``` ruby
Event.create(calendar_id: calendar.id, begins_at: begins_at, finishes_at: finishes_at)

ActiveRecord::StatementInvalid: PG::RaiseException: ERROR:  Period between 2016-05-02 12:00:00 and 2016-05-02 16:00:00 is already taken
```

<p>Awesome (haha, doesn't happen that often to be happy when an error occurs ;)), that's exactly what we wanted to achieve - the trigger keeps our data safe making sure that we won't have any duplicated events or events covering the same time period. The last thing we should do is to mimic such validation and add it to form object or model for better user experience, but it's beyond the scope of this article. It's going to duplicate some logic between the code in the application and the database, but in this case there's no way to <strong>DRY</strong> it up.</p>

<h2>Wrapping up</h2>

<p>PostgreSQL triggers and procedures are not something that you will often want to use in Rails applications, but sometimes there's no other solution, especially when you have more complex rules for data integrity. In such cases, triggers and procedures are the right tool for the job.</p>

