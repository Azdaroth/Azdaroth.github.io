---
layout: post
title: "Decoding Rails Magic: How Does ActiveJob work?"
date: 2016-09-25 23:45
comments: true
categories: [Ruby, Ruby on Rails, Design Patterns, Architecture, ActiveJob]
---

<p>Executing <strong>background jobs</strong> is quite a common feature in many of the web applications. Switching between different background processing frameworks used to be quite painful as most of them had different API for enqueuing jobs, enqueuing mailers and scheduling jobs. One of the great addition in <strong>Rails 4.2</strong> was a solution to this problem: <strong>ActiveJob</strong>, which provides extra layer on top of background jobs framework and unifies the API regardless of the queue adapter you use. But how exactly does it work? What are the requirements for adding new <strong>queue adapters</strong>? What kind of API does ActiveJob provide? Let’s dive deep into the codebase  and answer these and some other questions.</p>

<!--more-->

<h2>Anatomy of the job</h2>

<p>Let’s start with some simple job class, let it be <code>MyAwesomeJob</code>:</p>


``` ruby app/jobs/my_awesome_job.rb
class MyAwesomeJob < ActiveJob::Base
  def perform(user)
    User::DoSomethingAwesome.call(user)
  end
end
```

<p>To enqueue a job we could simply write: <code>MyAwesomeJob.perform_later(some_user)</code> or if we wanted to schedule a job in some time in the future we could write: <code>MyAwesomeJob.set(wait: 12.hours).perform_later(some_user)</code> or <code>MyAwesomeJob.perform_now(some_user)</code> for executing the job immediately without enqueuing. But we never defined these methods, so what kind of extra work <strong>ActiveJob</strong> performs to make it happen?</p>

<h2>Exploring internals of ActiveJob</h2>

<p>To answer this question, let’s take a look at the <a href="https://github.com/rails/rails/blob/5-0-stable/activejob/lib/active_job/base.rb" target="_blank">ActiveJob::Base class</a>:</p>


``` ruby active_job/base.rb
module ActiveJob
  class Base
    include Core
    include QueueAdapter
    include QueueName
    include QueuePriority
    include Enqueuing
    include Execution
    include Callbacks
    include Logging
    include Translation

    ActiveSupport.run_load_hooks(:active_job, self)
  end
end
```

<p>There are some interesting modules included in this class, which we will get to know in more details later, but let’s focus on the core API for now. Most likely this kind of logic would be defined in, well, <code>Core</code> module. Indeed, the <code>set</code> method is <a href="https://github.com/rails/rails/blob/5-0-stable/activejob/lib/active_job/core.rb#L59" target="_blank">there:</a></p>


``` ruby active_job/core.rb
module ActiveJob
  module Core
    def set(options={})
      ConfiguredJob.new(self, options)
    end
  end
end
```

<p>It returns an instance of <code>ConfiguredJob</code> passing the job instance itself and arguments to the constructor. Let’s check what <a href="https://github.com/rails/rails/blob/5-0-stable/activejob/lib/active_job/configured_job.rb" target="_blank">ConfiguredJob</a> class is responsible for:</p>


``` ruby active_job/configured_job.rb
module ActiveJob
  class ConfiguredJob #:nodoc:
    def initialize(job_class, options={})
      @options = options
      @job_class = job_class
    end

    def perform_now(*args)
      @job_class.new(*args).perform_now
    end

    def perform_later(*args)
      @job_class.new(*args).enqueue @options
    end
  end
end
```

<p>We have 2 methods available here: <code>perform_now</code> and <code>perform_later</code>. Both of them create a new job instance with arguments passed to the method and they either call <code>perform_now</code> method on the job instance or call <code>enqueue</code> passing the options which are the arguments from the <code>set</code> method. </p>

<p>Let’s go deeper and start with <code>perform_now</code> method: it’s defined inside <a href="https://github.com/rails/rails/blob/v5.0.0/activejob/lib/active_job/execution.rb#L15" target="_blank">Execution</a> module, which basically comes down to deserializing arguments if needed (there is <a href="https://github.com/rails/rails/blob/v5.0.0/activejob/lib/active_job/core.rb#L116" target="_blank">nothing</a> to deserialize when calling <code>perform_now</code> directly), and calling our <code>perform</code> method, which we defined in the job class. This logic is wrapped in <code>run_callbacks</code> block, which lets you define callbacks <code>before</code>, <code>around</code> and <code>after</code> the execution of <code>perform</code> method.</p>


``` ruby active_job/execution.rb
module ActiveJob
  module Execution
    module ClassMethods
      def perform_now(*args)
        job_or_instantiate(*args).perform_now
      end
    end

    # rest of the code which was removed for brevity

    def perform_now
      deserialize_arguments_if_needed
      run_callbacks :perform do
        perform(*arguments)
      end
    rescue => exception
      rescue_with_handler(exception) || raise
    end
  end
end
```

<p>These callbacks are defined inside <a href="https://github.com/rails/rails/blob/v5.0.0/activejob/lib/active_job/callbacks.rb" target="_blank">Callbacks</a> module, but its only responsibility is defining callbacks for <code>perform</code> and <code>enqueue</code> method, which help extend the behaviour of the jobs in a pretty unobtrusive manner. For example, if we wanted to log when the job is finished, we could add the following <code>after_perform</code> callback:</p>


``` ruby app/jobs/my_awesome_job.rb
class MyAwesomeJob < ActiveJob::Base
  after_perform do |job|
    Rails.logger.info "#{Time.current}: finished execution of the job: #{job.inspect}"
  end

  def perform(user)
    User::DoSomethingAwesome.call(user)
  end
end
```

<p>Let’s get back to <code>perform_later</code> method from <code>ConfiguredJob</code>. We could expect <code>enqueue</code> method to be defined  in <a href="https://github.com/rails/rails/blob/5-0-stable/activejob/lib/active_job/enqueuing.rb">Enqueuing</a> module, which seems to be the case here as well:</p>


``` ruby active_job/enqueuing.rb
module ActiveJob
  module Enqueuing
    def enqueue(options={})
      self.scheduled_at = options[:wait].seconds.from_now.to_f if options[:wait]
      self.scheduled_at = options[:wait_until].to_f if options[:wait_until]
      self.queue_name   = self.class.queue_name_from_part(options[:queue]) if options[:queue]
      self.priority     = options[:priority].to_i if options[:priority]
      run_callbacks :enqueue do
        if self.scheduled_at
          self.class.queue_adapter.enqueue_at self, self.scheduled_at
        else
          self.class.queue_adapter.enqueue self
        end
      end
      self
    end
  end
end
```

<p>We can pass several options here - <code>scheduled_at</code> attribute could be configured with <code>wait</code>  (which will schedule a job in specified amount of seconds from current time) and <code>wait_until</code> (which will schedule a job at exact specified time). We can also enforce <code>queue</code> used for the job execution and set the <code>priority</code>. At the end, the method call is delegated to <code>queue_adapter</code>. This logic is wrapped in <code>run_callbacks</code> block, which lets you define callbacks <code>before</code>, <code>around</code> and <code>after</code> the execution of this code. </p>

<p>In <code>Enqueueing</code> module we can also find  <a href="https://github.com/rails/rails/blob/v5.0.0/activejob/lib/active_job/enqueuing.rb#L17" target="_blank">perform_later</a> method, which is the part of most basic API of <strong>ActiveJob</strong> and it basically comes down to calling <code>enqueue</code> method without any extra <code>options</code> arguments.</p>


``` ruby active_job/enqueuing.rb
module ActiveJob
  module Enqueuing
    extend ActiveSupport::Concern

    module ClassMethods
      def perform_later(*args)
        job_or_instantiate(*args).enqueue
      end

      protected
        def job_or_instantiate(*args)
          args.first.is_a?(self) ? args.first : new(*args)
        end
    end
  end
end
```

<h2>Queue Adapters</h2>

<p>What is this <code>queue_adapter</code> to which we delegate the enqueueing? Let’s take a look at <a href="https://github.com/rails/rails/blob/5-0-stable/activejob/lib/active_job/queue_adapter.rb">QueueAdapter</a> module. Its responsibility is exposing reader and writer for <code>queue_adapter</code> accessor, which by default is <code>async</code> adapter. Assigning adapter is quite <a href="https://github.com/rails/rails/blob/5-0-stable/activejob/lib/active_job/queue_adapter.rb#L33" target="_blank">flexible</a> and we can pass here a string or a symbol (which will be used for the lookup of the proper adapter), instance of adapter itself or the class of the adapter (which is <a href="https://github.com/rails/rails/blob/5-0-stable/activejob/lib/active_job/queue_adapter.rb#L41" target="_blank">deprecated</a>).</p>


``` ruby active_job/queue_adapter.rb
module ActiveJob
  module QueueAdapter #:nodoc:
    extend ActiveSupport::Concern

    included do
      class_attribute :_queue_adapter, instance_accessor: false, instance_predicate: false
      self.queue_adapter = :async
    end

    module ClassMethods
      def queue_adapter
        _queue_adapter
      end

      def queue_adapter=(name_or_adapter_or_class)
        self._queue_adapter = interpret_adapter(name_or_adapter_or_class)
      end

      private

      def interpret_adapter(name_or_adapter_or_class)
        case name_or_adapter_or_class
        when Symbol, String
          ActiveJob::QueueAdapters.lookup(name_or_adapter_or_class).new
        else
          if queue_adapter?(name_or_adapter_or_class)
            name_or_adapter_or_class
          elsif queue_adapter_class?(name_or_adapter_or_class)
            ActiveSupport::Deprecation.warn "Passing an adapter class is deprecated " \
              "and will be removed in Rails 5.1. Please pass an adapter name " \
              "(.queue_adapter = :#{name_or_adapter_or_class.name.demodulize.remove('Adapter').underscore}) " \
              "or an instance (.queue_adapter = #{name_or_adapter_or_class.name}.new) instead."
              name_or_adapter_or_class.new
          else
            raise ArgumentError
          end
        end
      end

      QUEUE_ADAPTER_METHODS = [:enqueue, :enqueue_at].freeze

      def queue_adapter?(object)
        QUEUE_ADAPTER_METHODS.all? { |meth| object.respond_to?(meth) }
      end

      def queue_adapter_class?(object)
        object.is_a?(Class) && QUEUE_ADAPTER_METHODS.all? { |meth| object.public_method_defined?(meth) }
      end
    end
  end
end
```

<p>All supported queue adapters are defined in <a href="https://github.com/rails/rails/tree/v5.0.0/activejob/lib/active_job/queue_adapters" target="_blank">queue_adapters</a> directory. There are quite a lot of adapters here, so let’s pick some of them.</p>

<h3>Async Adapter</h3>

<p>Let’s start with <a href="https://github.com/rails/rails/blob/v5.0.0/activejob/lib/active_job/queue_adapters/async_adapter.rb" target="_blank">AsyncAdapter</a> which is the default one. What is really interesting about this queue adapter is that it doesn’t use any extra services but runs jobs with an in-process thread pool. Under the hood it uses <a href="https://github.com/ruby-concurrency/concurrent-ruby" target="_blank">Concurrent Ruby</a>, which is a collection of modern tools for writing concurrent code, I highly recommend to check it further. We can pass <code>executor_options</code> to constructor, which are then used to create a new instance of <code>Scheduler</code>.</p>


``` ruby active_job/queue_adapters/async_adapter.rb
module ActiveJob
  module QueueAdapters
    class AsyncAdapter
      def initialize(**executor_options)
        @scheduler = Scheduler.new(**executor_options)
      end

      def enqueue(job) #:nodoc:
        @scheduler.enqueue JobWrapper.new(job), queue_name: job.queue_name
      end

      def enqueue_at(job, timestamp) #:nodoc:
        @scheduler.enqueue_at JobWrapper.new(job), timestamp, queue_name: job.queue_name
      end

      def shutdown(wait: true) #:nodoc:
        @scheduler.shutdown wait: wait
      end

      def immediate=(immediate) #:nodoc:
        @scheduler.immediate = immediate
      end

      class JobWrapper #:nodoc:
        def initialize(job)
          job.provider_job_id = SecureRandom.uuid
          @job_data = job.serialize
        end

        def perform
          Base.execute @job_data
        end
      end

      class Scheduler #:nodoc:
        # code removed for brevity
      end
    end
  end
end
```

<p>Remember how we could assign <code>queue adapter</code> for ActiveJob in multiple ways? That’s exactly the use case for assigning specific instance of the queue adapter, besides just passing a string / symbol (or class, but that way is deprecated). The <code>Scheduler</code> instance acts in fact like a queue backend and but specifics of how it works are beyond the scope of this article. Nevertheless, the thing to keep in mind is that it exposes two important methods: <a href="https://github.com/rails/rails/blob/v5.0.0/activejob/lib/active_job/queue_adapters/async_adapter.rb#L90">enqueue</a> and <a href="https://github.com/rails/rails/blob/v5.0.0/activejob/lib/active_job/queue_adapters/async_adapter.rb#L94" target="_blank">enqueue_at</a>:</p>


``` ruby active_job/queue_adapters/async_adapter.rb
module ActiveJob
  module QueueAdapters
    class AsyncAdapter
      class Scheduler #:nodoc:
        DEFAULT_EXECUTOR_OPTIONS = {
          min_threads:     0,
          max_threads:     Concurrent.processor_count,
          auto_terminate:  true,
          idletime:        60, # 1 minute
          max_queue:       0, # unlimited
          fallback_policy: :caller_runs # shouldn't matter -- 0 max queue
        }.freeze

        attr_accessor :immediate

        def initialize(**options)
          self.immediate = false
          @immediate_executor = Concurrent::ImmediateExecutor.new
          @async_executor = Concurrent::ThreadPoolExecutor.new(DEFAULT_EXECUTOR_OPTIONS.merge(options))
        end

        def enqueue(job, queue_name:)
          executor.post(job, &:perform)
        end

        def enqueue_at(job, timestamp, queue_name:)
          delay = timestamp - Time.current.to_f
          if delay > 0
            Concurrent::ScheduledTask.execute(delay, args: [job], executor: executor, &:perform)
          else
            enqueue(job, queue_name: queue_name)
          end
        end

        def shutdown(wait: true)
          @async_executor.shutdown
          @async_executor.wait_for_termination if wait
        end

        def executor
          immediate ? @immediate_executor : @async_executor
        end
      end
    end
  end
end
```

<p>The main difference between these two methods is a timestamp (or lack of it) used for executing the job later. </p>

<p>Let’s get back to top-level <code>AsyncAdapter</code> class. The primary interface that is required for all queue adapters to implement is two methods: <code>enqueue</code> and <code>enqueue_at</code>. For <code>Async</code> adapter, these methods simply pass instance of <code>JobWrapper</code> with <code>queue_name</code> and <code>timestamp</code> (only for <code>enqueue_at</code>):</p>


``` ruby active_job/queue_adapters/async_adapter.rb
module ActiveJob
  module QueueAdapters
    class AsyncAdapter
      def initialize(**executor_options)
        @scheduler = Scheduler.new(**executor_options)
      end

      def enqueue(job) #:nodoc:
        @scheduler.enqueue JobWrapper.new(job), queue_name: job.queue_name
      end

      def enqueue_at(job, timestamp) #:nodoc:
        @scheduler.enqueue_at JobWrapper.new(job), timestamp, queue_name: job.queue_name
      end
    end
  end
end
```

<p>And what is this <code>JobWrapper</code>? It’s a simple abstraction for passing something that can serialize jobs and knows how to execute them:</p>


``` ruby active_job/queue_adapters/async_adapter.rb
module ActiveJob
  module QueueAdapters
    class AsyncAdapter
      class JobWrapper #:nodoc:
        def initialize(job)
          job.provider_job_id = SecureRandom.uuid
          @job_data = job.serialize
        end

        def perform
          Base.execute @job_data
        end
      end
    end
  end
end
```


<h2>Serialization and deserialization</h2>

<p>Let’s take a closer look how it works: <a href="https://github.com/rails/rails/blob/v5.0.0/activejob/lib/active_job/execution.rb#L20" target="_blank">execute</a> method is defined in <code>Execution</code> module and it basically comes down to deserializing job data (which was serialized in <code>JobWrapper</code> so that it can be enqueued)  and calling <code>perform_now</code>. This logic is wrapped with <code>run_callbacks</code> block so we can extend this logic by performing some action <code>before</code>, <code>around</code> or <code>after</code> execution logic:</p>


``` ruby active_job/execution.rb
module ActiveJob
  module Execution
    module ClassMethods
      def execute(job_data) #:nodoc:
        ActiveJob::Callbacks.run_callbacks(:execute) do
          job = deserialize(job_data)
          job.perform_now
        end
      end
    end
  end
end
```

<p><code>deserialize</code> class method is defined inside <a href="https://github.com/rails/rails/blob/v5.0.0/activejob/lib/active_job/core.rb#L35" target="_blank">Core</a> module and what it does is creating a new instance of the job, deserializing data and returning the job:</p>


``` ruby active_job/core.rb
module ActiveJob
  module Execution
    module ClassMethods
      # Creates a new job instance from a hash created with +serialize+
      def deserialize(job_data)
        job = job_data['job_class'].constantize.new
        job.deserialize(job_data)
        job
      end
    end
  end
end
```

<p>Before explaining what happens during the deserialization we should know how the serialized data look like -  it’s a hash containing name of the job class, job id, queue name, priority, locale and serialized arguments:</p>


``` ruby active_job/core.rb
module ActiveJob
  module Core
    def serialize
      {
        'job_class'  => self.class.name,
        'job_id'     => job_id,
        'queue_name' => queue_name,
        'priority'   => priority,
        'arguments'  => serialize_arguments(arguments),
        'locale'     => I18n.locale.to_s
      }
    end
  end
end
```

<p><code>serialize_arguments</code> method delegates the serialization process to <a href="https://github.com/rails/rails/blob/v5.0.0/activejob/lib/active_job/arguments.rb#L43" target="_blank">ActiveJob::Arguments.serialize</a> method, which is mainly responsible for mapping ActiveRecord models from arguments to global ids:</p>

``` ruby active_job/core.rb
module ActiveJob
  module Core
    private

    def serialize_arguments(serialized_args)
      Arguments.serialize(serialized_args)
    end
  end
end
```

<p> Here’s an example how serialized arguments may look like:</p>


``` ruby
> ActiveJob::Arguments.serialize([User.find(1), [123, User.find(2)], { "current_user" => User.find(3)}])
=> ["gid://app-name/User/1", [123, "gid://app-name/User/2"], {"value"=>"gid://app-name/User/3"}]
```

<p>This format can easily be used for enqueuing jobs in different queues.</p>

<p>Just before the execution of the job, the data needs to be deserialized. Like <code>serialize</code> method, <code>deserialize</code> is defined in <a href="https://github.com/rails/rails/blob/v5.0.0/activejob/lib/active_job/core.rb#L106" target="_blank">Core</a> module and it assigns job id, queue name, priority, locale and serialized arguments to the job using its accessors. But the arguments are not deserialized just yet, so how does the execution with <code>perform_now</code> work?</p>

<p>Remember how I mentioned before that there is nothing to be deserialized when using <code>perform_now</code> directly? In this case it will be a bit different as we operate on serialized arguments. Deserialization happens just before executing <code>perform</code> method in <a href="https://github.com/rails/rails/blob/v5.0.0/activejob/lib/active_job/core.rb#L115" target="_blank">deserialize_arguments_if_needed</a>.</p>


``` ruby activejob/lib/active_job/core.rb
module ActiveJob
  module Core
    private

    def deserialize_arguments_if_needed
      if defined?(@serialized_arguments) && @serialized_arguments.present?
        @arguments = deserialize_arguments(@serialized_arguments)
        @serialized_arguments = nil
      end
    end
  end
end
```

<p>Again, the deserialization is delegated to <a href="https://github.com/rails/rails/blob/v5.0.0/activejob/lib/active_job/arguments.rb#L50" target="_blank">Arguments</a> module and its primary responsibility is turning global ids into real models, so <code>gid://app-name/User/3</code> would be in fact a User record with id equal to 3.</p>

<h2>Exploring more queue adapters</h2>

<h3>Inline Adapter</h3>

<p>Let’s explore some more adapters. Most likely you were using <a href="https://github.com/rails/rails/blob/v5.0.0/activejob/lib/active_job/queue_adapters/inline_adapter.rb">InlineAdapter</a> in integration tests for testing the side effects of executing some job. Its logic is very limited: since it’s for the inline execution, it doesn’t support enqueueing jobs for the future execution and <code>enqueue</code> method for performing logic merely calls <code>execute</code> method with serialized arguments:</p>


``` ruby activejob/queue_adapters/inline_adapter.rb
class InlineAdapter
  def enqueue(job) #:nodoc:
    Base.execute(job.serialize)
  end

  def enqueue_at(*) #:nodoc:
    raise NotImplementedError, "Use a queueing backend to enqueue jobs in the future. Read more at http://guides.rubyonrails.org/active_job_basics.html"
  end
end
```

<h3>Sidekiq Adapter</h3>

<p>Let’s check a queue adapter for one of the most commonly used frameworks for background processing - <a href="https://github.com/mperham/sidekiq" target="_blank">Sidekiq</a>. Sidekiq requires defining a class implementing <code>perform</code> instance method executing the logic of the job and inclusion of <code>Sidekiq::Worker</code> module to be enqueued in its queue. Just like <code>AsyncAdapter</code>, <code>SidekiqAdapter</code> uses internal <code>JobWrapper</code> class, which includes <code>Sidekiq::Worker</code> and implements <code>perform</code> method taking <code>job_data</code> as an argument and its logic is limited to delegating execution of the logic to <code>ActiveJob::Base.execute</code> method:</p>


``` ruby activejob/queue_adapters/sidekiq_adapter.rb
class SidekiqAdapter
  def enqueue(job) #:nodoc:
    #Sidekiq::Client does not support symbols as keys
    job.provider_job_id = Sidekiq::Client.push \
      'class'   => JobWrapper,
      'wrapped' => job.class.to_s,
      'queue'   => job.queue_name,
      'args'    => [ job.serialize ]
  end

  def enqueue_at(job, timestamp) #:nodoc:
    job.provider_job_id = Sidekiq::Client.push \
      'class'   => JobWrapper,
      'wrapped' => job.class.to_s,
      'queue'   => job.queue_name,
      'args'    => [ job.serialize ],
      'at'      => timestamp
  end

  class JobWrapper #:nodoc:
    include Sidekiq::Worker

    def perform(job_data)
      Base.execute job_data
    end
  end
end
```

<p>Again, like every other adapter, <code>SidekiqAdapter</code> implements <code>enqueue</code> and <code>enqueue_at</code> methods and both of them push jobs to Sidekiq’s queue by passing some meta info that is later used for identifying proper job class, executing in specific queue and of course the serialized arguments. As an extra argument, <a href="https://github.com/rails/rails/blob/v5.0.0/activejob/lib/active_job/queue_adapters/sidekiq_adapter.rb#L33" target="_blank">enqueue_at</a> passes timestamp for executing the job at specific time. Pushing a job to Sidekiq queue returns internal job id which is then assigned to <code>provider_job_id</code> attribute.</p>

<h3>DelayedJob Adapter</h3>

<p>Let’s take a look at adapter for arguably most common choice backed by application’s database - DelayedJob. The pattern is exactly the same as for Sidekiq Adapter: We have <code>enqueue</code> and <code>enqueue_at</code> methods and both of them push the job to the queue with extra info about queue name, priority and, for <code>enqueue_at</code> method, the time to run the job at. Just like <code>SidekiqAdapter</code>, it wraps serialized job with internal <code>JobWrapper</code> instance which delegates execution of the logic to <code>ActiveJob::Base.execute</code>. At the end, the internal job id from DelayedJob’s queue is assigned to <code>provider_job_id</code> attribute:</p>


``` ruby activejob/queue_adatpers/delayed_job_adapter.rb
class DelayedJobAdapter
  def enqueue(job) #:nodoc:
    delayed_job = Delayed::Job.enqueue(JobWrapper.new(job.serialize), queue: job.queue_name, priority: job.priority)
    job.provider_job_id = delayed_job.id
    delayed_job
  end

  def enqueue_at(job, timestamp) #:nodoc:
    delayed_job = Delayed::Job.enqueue(JobWrapper.new(job.serialize), queue: job.queue_name, priority: job.priority, run_at: Time.at(timestamp))
    job.provider_job_id = delayed_job.id
    delayed_job
  end

  class JobWrapper #:nodoc:
    attr_accessor :job_data

    def initialize(job_data)
      @job_data = job_data
    end

    def perform
      Base.execute(job_data)
    end
  end
end
```

<h3>TestAdapter</h3>

<p>Have you ever needed to test which jobs were enqueued or performed when executing some specs? There’s a good change you were using test helpers provided by ActiveJob or <a href="https://github.com/gocardless/rspec-activejob" target="_blank">rspec-activejob</a> for that. All these assertions are quite easy to handle thanks to <a href="https://github.com/rails/rails/blob/v5.0.0/activejob/lib/active_job/queue_adapters/test_adapter.rb" target="_blank">TestAdapter</a> which exposes some extra API for keeping track of enqueued and performed jobs adding <code>enqueued_jobs</code> and <code>peformed_jobs</code> attributes, which are populated when calling <code>enqueue</code> and <code>enqueue_at</code> methods. You can also configure if the jobs should be actually executed by changing <code>perform_enqueued_jobs</code> and <code>perform_enqueued_at_jobs</code> flags.  You can also whitelist which jobs could be enqueued with <code>filter</code> attribute.</p>


``` ruby activejob/queue_adapters/test_adapter.rb
class TestAdapter
  attr_accessor(:perform_enqueued_jobs, :perform_enqueued_at_jobs, :filter)
  attr_writer(:enqueued_jobs, :performed_jobs)

  # Provides a store of all the enqueued jobs with the TestAdapter so you can check them.
  def enqueued_jobs
    @enqueued_jobs ||= []
  end

  # Provides a store of all the performed jobs with the TestAdapter so you can check them.
  def performed_jobs
    @performed_jobs ||= []
  end

  def enqueue(job) #:nodoc:
    return if filtered?(job)

    job_data = job_to_hash(job)
    enqueue_or_perform(perform_enqueued_jobs, job, job_data)
  end

  def enqueue_at(job, timestamp) #:nodoc:
    return if filtered?(job)

    job_data = job_to_hash(job, at: timestamp)
    enqueue_or_perform(perform_enqueued_at_jobs, job, job_data)
  end

  private

  def job_to_hash(job, extras = {})
    { job: job.class, args: job.serialize.fetch('arguments'), queue: job.queue_name }.merge!(extras)
  end

  def enqueue_or_perform(perform, job, job_data)
    if perform
      performed_jobs &lt;&lt; job_data
      Base.execute job.serialize
    else
      enqueued_jobs &lt;&lt; job_data
    end
  end

  def filtered?(job)
    filter &amp;&amp; !Array(filter).include?(job.class)
  end
end
```

<h2>Wrapping up</h2>

<p>We’ve learned quite a lot how <code>ActiveJob</code> works under the hood - what kind of public API is available and how to extend it with custom queue adapters.  Even though understanding the internals of Rails may require some effort and time, it’s worth going deeper and exploring the architecture of the framework we use for everyday development. Here are some key takeaways:</p>

<ul>
  <li>You can provide the exact instance of queue adapter for ActiveJob, not only a string or symbol, which lets you pass some extra configuration options</li>
  <li>Adapter pattern is a great choice when we have several services with different interfaces but we want to have one unified interface for using all of them</li>
  <li>Most of the ActiveJob's logic is divided into modules (which seems to be a common pattern in other layers of Rails), but benefits of doing so are unclear: why Execution is a separate module from Core? What kind of benefits does splitting queue-related logic to QueuePriority, QueueName and QueueAdapter give? I don’t really see it as a way to decouple code as e.g. <code>Enqueuing</code> module depends on logic from QueueName, yet it’s not required explicitly, it just depends on existence of <code>queue_adapter</code> attribute. It would be more clear if Base or Core module acted like a facade and delegated responsibilities to some other classes. If anyone knows any reason behind this kind of design, please write it in a comment, I’m really curious about it.</li>
  <li>To support another background jobs execution framework, you just need to add a queue adapter class implementing <code>enqueue</code> and <code>enequeue_at</code> methods which under the hood would push the job to the queue and delegate  execution of the logic to <code>ActiveJob::Base.execute</code> method passing the serialised job as an argument.</li>
  <li>Rails internals are not that scary :)</li>
</ul>

<p>If there’s any particular part of Rails that seems "magical" and you would like to see it decoded, let me know in the comments, I want to make sure I cover the needs of my readers.</p>
