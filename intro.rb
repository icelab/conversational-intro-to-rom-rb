#!/usr/bin/env ruby

# # A conversational introduction to rom-rb: part 2
#
# _[See all parts](.)_ · _[View the source][gh]_ · _[Follow the blog][blog]_ · _[Say hi on Twitter][tw]_
#
# In [part 1](part-1.html), we took our first steps with rom-rb, setting up
# our basic persistence API and some repositories, then creating and reading
# back records in our database.
#
# This time, we'll return query results in domain-specific objects, fetch
# records with associations, and also look at updating records.
#
# [gh]: https://github.com/icelab/conversational-intro-to-rom-rb
# [blog]: http://icelab.com.au/articles/conversational-rom-rb-part-2-types-associations-and-update-commands/
# [tw]: http://twitter.com/timriley

require "bundler/setup"
require "rom-sql"
require "rom-repository"

# We're pulling in one new dependency this time: dry-types. dry-types works
# very well alongside rom-rb, and will allow us to build type-safe domain
# entites from our database records.
require "dry-types"

# ## Define our app's persistence API
#
# In part 1, we started with a simple articles relation and corresponding
# database table. Now we'll expand things a little: we want our articles to
# have many categories, so we'll add a categories relation and an
# articles_categories relation to join the two.

module Relations
  class Articles < ROM::Relation[:sql]
    schema(:articles) do
      attribute :id, Types::Serial
      attribute :title, Types::String
      attribute :published, Types::Bool

      # We'll be using rom-rb's new `associate` API to make building these
      # associations easy for us. Along with the `schema` API, this is new in
      # rom-rb's master branches and will be released later in June.
      #
      # Basic usage of the `associate` API is wonderfully simple. All we need
      # to do is declare the associations for this schema, and rom-rb will do
      # the work to connect things for us.
      #
      # In this case, articles will have many categories through our
      # articles_categories join table.
      associate do
        many :categories, through: :articles_categories
      end
    end

    def by_id(id)
      where(id: id)
    end

    def published
      where(published: true)
    end
  end

  # Our new Categories relation is straightforward: just an ID and a name.
  class Categories < ROM::Relation[:sql]
    schema(:categories) do
      attribute :id, Types::Serial
      attribute :name, Types::String
    end
  end

  # Now let's join records from these tables together.
  class ArticlesCategories < ROM::Relation[:sql]
    schema(:articles_categories) do
      attribute :id, Types::Serial

      # The schema definition here has a couple of interesting things: these
      # `ForeignKey` types. This is simply a way to leave some extra metadata
      # on the type annotations so rom-rb can know to use these foreign key
      # columns when it builds its associations.
      #
      # By default, rom-rb `ForeignKey` types are integers, but we can also
      # provide specific types like this:
      #
      # ```ruby
      # Types::ForeignKey(:articles, type: Types::String)
      # ```
      attribute :article_id, Types::ForeignKey(:articles)
      attribute :category_id, Types::ForeignKey(:categories)

      # And here we put these foreign keys to work by specifying the
      # associations for this join table: each record belongs to both an
      # article and a category.
      associate do
        belongs :articles
        belongs :categories
      end
    end
  end
end

# ## Define our app's types
#
# Type safety and shareable type definitions are an important pillar of any
# [dry-rb][dry-rb] app, and here we can get a little taste of it. We'll set up
# entity classes to model the results coming out of our databases. Using [dry-
# types][dry-types] structs here gives us a [number of benefits][benefits],
# including:
#
# - Giving us a place to decorate the raw results from the database and
#   provide any special behaviour important for our app.
# - Making it easy for us to consume these objects in various contexts, since
#   we can be 100% confident in the type of data they contain - a dry-types
#   struct cannot be initialized with invalid attributes.
#
# We can also feel free to pass these objects all around our app, since by
# convention we don't mutate them, and unlike objects coming from the active
# record pattern, there's no way to trigger far-reaching side effects, like
# database changes. These are also explicitly handled for us by rom-rb's
# dedicated query and commands objects, which we would never use accidentally.
#
# [dry-rb]: http://dry-rb.org/
# [dry-types]: http://dry-rb.org/gems/dry-types
# [benefits]: http://icelab.com.au/articles/inactive-records-the-value-objects-your-app-deserves/

# The first thing we need to do with dry-types is to give our app a `Types`
# module to include all of dry-type's out-of-the-box definitions, all the
# basic Ruby types like strings, integers, etc.
module Types
  include Dry::Types.module
end

# Now we can refer to this types module when we set up our struct subclasses.
# Our Category struct has attributes to contain each of the values we expect
# to get from rows in its corresponding database table.
class Category < Dry::Types::Struct
  attribute :id, Types::Strict::Int
  attribute :name, Types::Strict::String
end

# And Article is much the same, with one exception: we're going to fetch each
# article along with all of its associated categories, so we set up a
# categories attribute, which is an array of Category objects. Here we see how
# we can actually _build_ upon our existing struct classes to provide quite
# expressive, fully-featured type definitions.
class Article < Dry::Types::Struct
  attribute :id, Types::Strict::Int
  attribute :title, Types::Strict::String
  attribute :published, Types::Strict::Bool

  attribute :categories, Types::Strict::Array.member(Category)
end

# ## Define our app's repositories
#
# With these types in place, we can revisit our repositories. One thing to
# note here is that, within this script, these repositories have now moved a
# little _further away_ from the relations that they use. This is actually a
# fairer representation of how they should sit within a larger app:
# repositories are not part of the basic persistence layer, but are rather a
# way for your app to _hide away_ the nitty-gritty details of persistence. In
# this way, they're part of your app's collection of core objects.
#
# We'll take this a step further today by configuring these repositories to
# return results wrapped up in the domain entities we defined just above.

module Repositories
  # While we've added 3 extra relations above, we'll still be keeping only one
  # repository, which is another reflection of the different roles these two
  # things serve. Repositories are the sole interfaces through which our apps
  # work with persisted data, and in the case of this playground, all we need
  # to get are articles.
  class Articles < ROM::Repository[:articles]
    # This repository can already access its root articles relation. Now we
    # need to make the categories relation accessible to it, so it can take
    # care of the association of articles to categories.
    relations :categories

    # We're also adding one new command to the repository: `update`, combining
    # it with a `by_id` _restriction_. `by_id` is the query method we defined
    # in the articles relation, and it means here that the update command will
    # require an article ID to be provided, to ensure we only update a single
    # record and not every article in our database!
    commands :create, update: :by_id

    # We're making 2 important changes to both of our repo's query methods:
    #
    # Firstly, we're adding `aggregate(:categories)`, which will combine each
    # article result with all of its categories, using the associations we
    # declared back up in the relations.
    #
    # Then we're adding `.as(Article)`, which will see the data from each of
    # the results being passed to the constructor of our `Article` class.
    # Because this class is already configured to expect an array of
    # categories attributes, it will receive all the information it needs to
    # be initialized with valid data.
    def [](id)
      aggregate(:categories)
        .by_id(id)
        .as(Article)
        .one!
    end

    def published
      aggregate(:categories)
        .published
        .as(Article)
        .to_a
    end
  end
end

# ## Initialize rom-rb
#
# We're registering our two extra relations here. Again, this is something
# that would be taken care of for us when using rom-rb in a larger app, but
# it's nice that rom-rb gives us all the setup hooks we need to make a little
# playground script like this work too.
config = ROM::Configuration.new(:sql, "sqlite::memory")
config.register_relation Relations::Articles
config.register_relation Relations::Categories
config.register_relation Relations::ArticlesCategories
container = ROM.container(config)

# ## Prepare our database
#
# We're adding the migrations for our two extra tables here, and using the
# `foreign_key` support from [Sequel's migration API][fk] for proper database
# integrity.
#
# [fk]: http://sequel.jeremyevans.net/rdoc/files/doc/schema_modification_rdoc.html#label-foreign_key
container.gateways[:default].tap do |gateway|
  migration = gateway.migration do
    change do
      create_table :articles do
        primary_key :id
        string :title, null: false
        boolean :published, null: false, default: false
      end

      create_table :categories do
        primary_key :id
        string :name, null: false
      end

      create_table :articles_categories do
        primary_key :id
        foreign_key :article_id, :articles, null: false
        foreign_key :category_id, :categories, null: false
      end
    end
  end
  migration.apply gateway.connection, :up
end

# ## Let's play!
#
# Alright, everything's in place. Let's try out these changes!


# First, get a repo to use.
repo = Repositories::Articles.new(container)

# Let's just manually seed our database with some data. We need to make some
# articles, categories and their associations via the join table. Next week
# we'll look at how we can do this nicely with rom-rb, but for now  we need to
# sneak in a couple of lines of SQL.
repo.create(title: "Hello rom-rb", published: true)

connection = container.gateways[:default].connection
connection.execute "INSERT INTO categories (name) VALUES ('dry-rb')"
connection.execute "INSERT INTO categories (name) VALUES ('rom-rb')"
connection.execute "INSERT INTO articles_categories (article_id, category_id) VALUES (1, 1)"
connection.execute "INSERT INTO articles_categories (article_id, category_id) VALUES (1, 2)"

# Now we should be able to see some results.
#
# And look! Here we are: our article, wrapped up in a proper domain object,
# including both of its associated categories:
#
# ```ruby
# repo.published
# # => [#<Article id=1 title="Hello rom-rb" published=true categories=[#<Category id=1 name="dry-rb">, #<Category id=2 name="rom-rb">]>]
# ```
puts "Published articles?"
published_articles = repo.published
puts published_articles.inspect

# And with our repo's new `update` command, we should be able to modify that
# article.
repo.update(published_articles.first.id, title: "rom-rb and dry-rb, sitting in a tree")

# Has it worked? Yes!
#
# ```ruby
# repo.published.first.title
# # => "rom-rb and dry-rb, sitting in a tree"
# ```
puts "Updated title?"
puts repo.published.first.title.inspect

# ## Next steps
#
# We've seen a few more features of the upcoming rom-rb release, but our
# journey isn't complete. We'll come back for one more part, in which we'll
# look at a command graph to create both articles and categories at the same
# time.
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
