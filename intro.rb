#!/usr/bin/env ruby

# # A conversational introduction to rom-rb
#
# _[View the source][gh]_ · _[Follow the blog][blog]_ · _[Say hi on Twitter][tw]_
#
# [gh]: https://github.com/icelab/conversational-intro-to-rom-rb
# [blog]: http://icelab.com.au/articles/a-conversational-introduction-to-rom-rb/
# [tw]: http://twitter.com/timriley
#
# ### Persistence matters
#
# We've spent a few weeks now exploring a [next-generation web app
# architecture][arch] for Ruby, but we're yet to cover one very important
# thing: **database persistence**.
#
# How we choose to build our app's persistence support will have a profound
# impact on its overall design.
#
# We could follow the active record pattern and wind up with a select few
# models [deeply intertwined][ar] with every aspect of our application's
# functionality.
#
# Or we could build a clean separation of responsibilities and make an app
# that remains easy to change. **This is where [rom-rb][rom] can help.**
#
# [arch]: http://icelab.com.au/articles/a-change-positive-ruby-web-application-architecture/
# [ar]: http://icelab.com.au/articles/inactive-records-the-value-objects-your-app-deserves/
# [rom]: http://rom-rb.org/
#
# ### rom-rb helps
#
# rom-rb is a flexible persistence and data mapping toolkit for Ruby. It
# separates queries and commands and offers [powerful, workable
# abstractions][philosophy] at every point between our app and the data store.
# This mean there are a few concepts to learn, but the payoff is significant:
# a persistence layer that can be perfectly tailored to our app's needs.
#
# Let's get started, then: follow the code and commentary below for an
# introduction to rom-rb and a playground for making your own experiments.
#
# [philosophy]: http://rom-rb.org/learn/introduction/philosophy/
#
# <hr>

# ## Install the rom-rb gems

# Over in the `Gemfile`, we're installing the rom-rb gems from their master
# branches, since we'll be looking at some major improvements that are slated
# for release later this month.
require "bundler/setup"

# Require the gems we need.
#
# One thing to note here is that rom-rb is a _multi-adapter_ toolkit. It
# supports many kinds of data sources (and even allows you to use them
# together!). For today, though we'll stick to SQL. Apart from the "rom-sql"
# adapter, the only other `require` we need is "rom-repository", which will
# act as our app's primary persistence interface.
require "rom-sql"
require "rom-repository"

# ## Define our app's persistence API
#
# In this playground, we'll be using rom-rb to work with _articles_ in our
# database.

# ### Relations
#
# The first thing we need to define is a **Relation**. Relations are the
# interface to a particular collection in our data source, which in SQL terms
# is either a table or a view.
module Relations
  # This relation is for the `articles` table.
  class Articles < ROM::Relation[:sql]
    # Define a canonical schema for this relation. This will be used when we
    # use commands to make changes to our data. It ensures that only
    # appropriate attributes are written through to the database table.
    schema(:articles) do
      attribute :id, Types::Serial
      attribute :title, Types::String
      attribute :published, Types::Bool
    end

    # Define some composable, reusable query methods to return filtered
    # results from our database table. We'll use them in a moment.
    def by_id(id)
      where(id: id)
    end

    def published
      where(published: true)
    end
  end
end

# ### Repositories
#
# Now, let's define a **Repository**. Repositories are the primary persistence
# interfaces in our app. Responsitories contribute a couple of important things
# to a well-designed app:
#
# 1. They hide low-level persistence details, ensuring the rest of our app
#    doesn't have any accidental or unnecessary coupling to the implementation
#    details for our data source.
# 2. They return objects that are appropriate for our app's domain. The data
#    for these objects may come from one or more relations, may be transformed
#    into a different shape, and may be returned as objects that are designed
#    to be passed around the other components in our app.
module Repositories
  # This simple repository uses articles as its main relation.
  class Articles < ROM::Repository[:articles]
    # Define a command to create new articles.
    commands :create

    # Define methods to return the article objects we want to use within our
    # app. Each of these can access the relation via `articles` and use its
    # query methods.
    #
    # Unlike the query methods inside the relations, these ones should not be
    # chainable. Their purpose is to return a set of articles for each
    # distinct use case within our app. This means that our repository API
    # (and therefore our persistence API in general) is a perfect reflection
    # of our app's persistence requirements.
    def [](id)
      articles.by_id(id).one!
    end

    def published
      articles.published.to_a
    end
  end
end

# ## Initialize rom-rb
#
# rom-rb is built to be non-intrusive. When we initialize it here, all our
# relations and commands are bundled into a single container that we can
# inject into our app.
#
# In any kind of framework, this setup will be taken care of for us, but
# because rom-rb is flexible, explicit setup for our playground is still nice
# and easy.

# Configure rom-rb to use an in-memory SQLite database via its SQL adapter,
# register our articls relation, then build and finalize the persistence
# container.
config = ROM::Configuration.new(:sql, "sqlite::memory")
config.register_relation Relations::Articles
container = ROM.container(config)

# ## Prepare our database
#
# Since this is a standalone playground, run a migration to give us a database
# table to work with.
container.gateways[:default].tap do |gateway|
  migration = gateway.migration do
    change do
      create_table :articles do
        primary_key :id
        string :title, null: false
        boolean :published, null: false, default: false
      end
    end
  end
  migration.apply gateway.connection, :up
end

# ## Let's play!
#
# Alright, everything's in place. Let's try some things!

# First, get a repo to use.
repo = Repositories::Articles.new(container)

# Let's see if we have any published articles
#
# Nope, nothing. We've just created this table, after all!
#
# ```ruby
# repo.published
# # => []
# ```
puts "Published articles?"
puts repo.published.inspect

# It's time to create an article then. We can do this via the repo too. rom-rb
# will give it back to us in a convenient struct for accessing the attributes
# of the new article.
#
# ```ruby
# repo.create(title: "Hello rom-rb")
# # => #<ROM::Struct[Article] id=1 title="Hello rom-rb" published=false>
# ```
first_article = repo.create(title: "Hello rom-rb")
puts "\nCreate an article:"
puts first_article.inspect

# Can we fetch this article in a list? Not yet, because it's not published.
#
# ```ruby
# repo.published
# # => []
# ```
puts "\nPublished articles?"
puts repo.published.inspect

# But we can find it by ID, because we've built our repo's `#[]` method to
# find an article regardless of published status.
#
# ```ruby
# repo[first_article.id]
# # => #<ROM::Struct[Article] id=1 title="Hello rom-rb" published=false>
# ```
puts "\nFind first article by ID"
puts repo[first_article.id].inspect

# Let's create a published article now.
#
# ```ruby
# repo.create(title: "Hello world", published: true)
# # => #<ROM::Struct[Article] id=2 title="An alien or sutin" published=true>
# ```
published_article = repo.create(title: "An alien or sutin", published: true)
puts "\nCreate a published article:"
puts published_article.inspect

# This article should be in our list now!
#
# ```ruby
# repo.published
# # => [#<ROM::Struct[Article] id=2 title="An alien or sutin" published=true>]
# ```
puts "\nPublished articles?"
puts repo.published.inspect

# ## Next steps
#
# This is the end of our first little foray into the world of rom-rb. I hope
# you've enjoyed it! Next week we'll look at a few more advanced features.
#
# Until then, if you can [clone this playground from GitHub][gh] and
# experiment:
#
# ```
# git clone https://github.com/icelab/conversational-intro-to-rom-rb
# cd conversational-intro-to-rom-rb
# bundle
# ./intro.rb
# ```
#
# Feel free to extend the playground, make your own changes and see how things
# work!
#
# And if you want to learn more, check out the [helpful documentation][docs]
# on the rom-rb website, and join the [gitter chat][chat] if you have any
# questions!
#
# [gh]: https://github.com/icelab/conversational-intro-to-rom-rb
# [docs]: http://rom-rb.org/learn/
# [chat]: https://gitter.im/rom-rb/chat
