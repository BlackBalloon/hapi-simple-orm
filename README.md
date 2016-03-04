Hapi.js simple ORM
==================

Small library used reflect database tables in Hapi.js based applications.
Provides DAO for every Model, as well as generates routing objects for every Model.

## Installation

  `npm install hapi-simple-orm --save`

## Usage of the ORM

  First install required dependencies with `npm install`

  This package requires `knex` module. In order to provide integration with the database, it is necessary to create
  `knexfile.coffee` in root folder of the project which would look as follows:

  ```coffee
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
  BaseModel = require('hapi-simple-orm').model
  BaseField = require('hapi-simple-orm').fields.baseField

  Joi       = require 'joi'

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

    # in case of ForeignKey it is recommended to use 'camelCase' version of referenced Model's name
    accountCategory: new ForeignKey(
      referenceModel: AccountCategory
      required: true
      errorMessages:
        foreignKey: 'Selected category does not exist'
    )

  class User extends baseModel

    @include(userAttributes);

    @metadata =
      tableName: 'users'
      singular: 'user'
      model: 'User'
      primaryKey: 'id'
      timestamps: true

    toString: =>
      @get 'name'


  module.exports = User
  ```

  Then it is able to perform DAO operations

  ```coffee
  User.objects().all().then (users) ->
    console.log users
  .catch (error) ->
    throw error
  ```

  Example create:

  ```coffee
  data =
    username: 'tom'

  User.objects().create({ payload: data, direct: true }).then (user) ->
    console.log user
  .catch (error) ->
    throw error
  ```

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

## Release History

* 0.0.1 Initial release
