Hapi.js simple ORM
==================

Small library used to reflect database tables in Hapi based applications. It provides DAO layer, as well as Model's instances serialization for routing.
It also can generate routing objects, that can be passed to `server.route()` method, for every model (basic operations GET, PUT, POST, DELETE). Strongly inspired by Django framework and django-rest-framework library.

## Installation

  `npm install hapi-simple-orm --save`

## Usage of the ORM

  First install required dependencies with `npm install`

  This package requires `knex` module. In order to provide integration with the database, it is necessary to create
  `knexfile.js/coffee` in root folder of the project which would look as follows:

  ```coffee
  # example configuration for PostgreSQL
  module.exports =
    development:
      client: 'pg'
      connection:
        database: 'database_dev'
        user:     'postgres'
        password: 'postgres'
      migrations:
        tableName: 'migrations'

    test:
      client: 'pg'
      connection:
        database: 'database_test'
        user:     'postgres'
        password: 'postgres'
      migrations:
        tableName: 'migrations'
  ```

  Then, depending on the `NODE_ENV`, proper configuration is used afterwards, the package is ready to use.

  ```coffee
  BaseModel     = require('hapi-simple-orm').models.BaseModel

  BaseField     = require('hapi-simple-orm').fields.BaseField
  ForeignKey    = require('hapi-simple-orm').fields.ForeignKey

  Joi           = require 'joi'

  AccountCategory = require './accountCategory'

  # model's attributes definition does not reflect the database tables
  # it is necessary to create own knex migration files in order to create corresponding tables

  # this package assumes that database fields are 'snake_case', but attributes
  # used within the Hapi based project are 'camelCase' - stick to that concept

  userAttributes =
    id: new BaseField(
      schema: Joi.number().integer().positive()
      primaryKey: true
    )

    username: new BaseField(
      schema: Joi.string().max(256)
      required: true
      name: 'username'
    )

    # if you want to ForeignKey field to be named differently than referenceModel name
    # you need to specify the 'name' attribute to the ForeignKey constructor
    accountCategory: new ForeignKey(
      referenceModel: AccountCategory
      required: true
      errorMessages:
        foreignKey: 'Selected category does not exist'
    )

  class User extends baseModel

    @include userAttributes
    ###
    # here we extend with empty object {}, due to the fact that there is no need
    # to pass any additional parameters that will be used in Meta attributes of the Model
    # the '.extend()' method generates 'metadata' class attribute of the User model
    # which specifies the 'tableName', 'primaryKey', whether to use 'timestamp' fields
    # as well as the Model's name itself
    # exemplary 'metadata' object could look like follow:
    {
      tableName: 'users',
      singular: 'user',
      primaryKey: 'id',
      model: 'User',
      timestamps: true
    }
    # the 'timestamps' attribute's default value is set to true when not specified
    ###
    @extend {}

    toString: =>
      @get 'name'


  module.exports = User
  ```

  Every model obtain's basic DAO extension, however it is possible to define DAO for every model separately:

  ```coffee
  BaseDAO       = require('hapi-simple-orm').daos.BaseDAO

  class UserDAO extends BaseDAO

    config:
      lookupField: 'id'
      returning:
        basic: [
          'id'
          'username'
        ]

  module.exports = UserDAO
  ```

  From now on the User model has it's own DAO class, which can be used by accessing the '.objects()' function of the User Class:

  ```coffee
  User.objects().all().then (users) ->
    console.log users
    ###
    [
      {
        id: 1,
        username: 'tom'
      },
      {
        id: 2,
        username: 'john'
      }
    ]
    ###
  .catch (error) ->
    throw error
  ```

  Example create:

  ```coffee
  data =
    username: 'tom'

  # direct attribute is set to 'true' because '.create()' method is called
  # directly from the User's model DAO
  User.objects().create({ payload: data, direct: true }).then (user) ->
    console.log user
  .catch (error) ->
    throw error

  # it can also be done in such a way:
  user = new User data
  user.save().then (result) ->
    console.log result
    ###
    {
      id: 1
      username: 'tom'
    }
    ###
  .catch (error) ->
    throw error
  ```

  Every DAO has several default operations that can be performed on every Model:
  * `getById` - find one instance of Model by specifying value of it's primary key
  * `get` - find one instance of Model by specifying lookup values
  * `all` - return all instances of Model
  * `filter` - filter Model instances by specified lookup values
  * `create` - create and save new instance of Model
  * `bulkCreate` - create and save multiple instances of Model at once
  * `update` - update specified instance of Model
  * `delete` - delete specified instance of Model

## Serializers based on Models

  It is possible to use serializers in order to serialize the payload when sending model's instances via REST. It is possible to define nested relations with use of `ModelSerializer`

  ```coffee
  ModelSerializer           = require('hapi-simple-orm').serializers.modelSerializer

  User                      = require './../models/user'
  AccountCategorySerializer = require './accountCategory'

  class UserSerializer extends ModelSerializer

    @config:
      model: User
      fields: [
        'id'
        'username'
        accountCategory: new AccountCategorySerializer
      ]

  module.exports = UserSerializer

  # then it is possible to combine DAO with serializers:

  User.objects().getById({ val: 1 }).then (user) ->
    serializer = new UserSerializer data: user
    serializer.getData().then (serializerData) ->
      console.log serializerData
      ###
      {
        id: 1
        username: 'tom'
        accountCategory: {
          id: 1
          name: 'admin'
        }
      }
      ###
  .catch (error) ->
    throw error
  ```

## Model views

  ORM provides also the possibility to generate routing objects that can be passed to `server.route()` method of Hapi. This creates default handlers for basic HTTP operations like GET, PUT, POST, DELETE. Below is usage example:

  ```coffee
  ModelView       = require('hapi-simple-orm').views.ModelView

  User            = require './../models/user'
  UserSerializer  = require './../serializers/user'

  class UserModelView extends ModelView

    config:
      model: User
      tag: 'auth'
      serializer: UserSerializer
      errorMessages:
        notFound: 'Specified user does not exit'


  module.exports = UserModelView

  # afterwards, the 'UserModelView' can be used in such a way:
  UserModelView   = require './../views/user'

  userRoutes = (server, options, next) ->

    userModelView = new UserModelView server, options

    server.route userModelView.list()   # GET /users
    server.route userModelView.get()    # GET /users/{id}
    server.route userModelView.create() # POST /users
    server.route userModelView.update() # PUT /users/{id}
    server.route userModelView.delete() # DELETE /users/{id}

    next()

  exports.register = userRoutes
  ```

## Tests
  TODO

## Release History
* 0.0.2
  * Added `.extend()` method to BaseModel which simplifies specifying Meta attributes of Model.
  * Now ModelSerializer can obtain M2M/M2O related field in 'fields' attribute, which will return array of IDs.
  * Small issues.
* 0.0.1 Initial release
