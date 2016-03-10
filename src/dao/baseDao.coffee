'use strict'

knexConf    = require process.cwd() + '/knexfile'
knex        = require('knex')(knexConf[process.env.NODE_ENV])
_           = require 'underscore'
Promise     = require 'bluebird'


class BaseDAO

  constructor: (model) ->
    @config.model = model

    # set default lookupField to 'primaryKey' of current model
    # if none was specified
    if not @config.lookupField?
      @config.lookupField = @config.model.metadata.primaryKey

    # set default 'returning' attribute of 'config'
    # and it's 'basic' value to ['*'] - return all fields
    if not @config.returning?
      @config.returning = {}
      @config.returning['basic'] = ['*']

    # check if '@config.returning.basic' array contains '*'
    # if it does, it means that each query using this returning
    # should return all attributes of given model
    if _.contains @config.returning.basic, '*'
      returningArray = _.map @config.model::attributes, (val, key) =>
        if not (key of @config.model::timestampAttributes) and not val.attributes.abstract?
          "#{val.getDbField(key)} AS #{key}"
      @config.returning.basic = _.without returningArray, undefined

  # return specified instance of given Model by it's 'primaryKey' attribute
  # @param [Any] val value of the primary key
  # @param [Array] returning array of fields to be returned from the DB
  # @param [Boolean] toObject boolean defining if result should be translated to Model instance
  getById: ({ val, returning, toObject } = {}) ->
    # we set default value for 'toObject' parameter as true
    # which means that if it is not passed, query will always return Model instances
    toObject ?= true

    if not val?
      throw new Error "Value of the ID is required"

    returning ?= @config.returning.basic

    knex(@config.model.metadata.tableName)
      .where(@config.model.metadata.primaryKey, val)
      .andWhere('is_deleted', false)
      .select(returning)
      .then (rows) =>
        # throw error if query returned more than 1 row - it definitely should not do that
        if rows.length > 1
          throw new Error "'getById' method on '#{@config.model.metadata.model}' returned more than 1 row!"

        # if 'toObject' was set to true we need to check if 'get' method returned any rows
        # if yes, then we create instance, otherwise we return empty result
        if toObject and rows.length is 1
          return new @config.model rows[0]
        return rows[0]
      .catch (error) ->
        throw error

  # return specified instance of given Model
  # @param [Object] lookup object which is used in 'where' sql query like: { id: 5 }
  # @param [Array] returning array of fields to be returned from the DB e.g. ['id', 'name']
  # @param [Boolean] toObject boolean defining if result should be translated to Model instance
  get: ({ lookup, returning, toObject } = {}) ->
    # we set default value for 'toObject' parameter as true
    # which means that if it is not passed, query will always return Model instances
    toObject ?= true

    if not lookup?
      throw new Error "Lookup object is required!"

    returning ?= @config.returning.basic

    knex(@config.model.metadata.tableName)
      .where(lookup)
      .andWhere('is_deleted', false)
      .select(returning)
      .then (rows) =>
        # throw error if query returned more than 1 row - it definitely should not do that
        if rows.length > 1
          throw new Error "GET method on '#{@config.model.metadata.tableName}' returned more than 1 row!"

        # if 'toObject' was set to true we need to check if 'get' method returned any rows
        # if yes, then we create instance, otherwise we return empty result
        if toObject and rows.length is 1
          return new @config.model rows[0]
        return rows[0]
      .catch (error) ->
        throw error

  # return all instances of given Model
  # @param [Array] returning array of fields to be returned from the DB e.g. ['id', 'name']
  # @param [Boolean] toObject boolean defining if result should be translated to Model instance
  all: ({ returning, toObject } = {}) ->
    # we set default value for 'toObject' parameter as true
    # which means that if it is not passed, query will always return Model instances
    toObject ?= true

    returning ?= @config.returning.basic

    knex(@config.model.metadata.tableName)
      .select(returning)
      .andWhere('is_deleted', false)
      .then (rows) =>
        # if result is to be translated to Model instances, we need to check
        # if query returned at least 1 result, otherwise return empty result
        if toObject and rows.length > 0
          return _.map rows, (val, key) =>
            new @config.model val
        return rows
      .catch (error) ->
        throw error

  # find Model's instances fulfilling given lookup values
  # @param [Array] lookup array of objects with keys: 'key', 'values'. Defines the filtering attributes like 'where', 'orWhere', 'whereIn' etc.
  # @param [Array] returning array of fields to be returned from the DB e.g. ['id', 'name']
  # @param [Boolean] toObject boolean defining if result should be translated to Model instance
  filter: ({ lookup, returning, toObject } = {}) ->
    # we set default value for 'toObject' parameter as true
    # which means that if it is not passed, query will always return Model instances
    toObject ?= true

    returning ?= @config.returning.basic
    # default 'lookup' value is set to '{}' if none was passed
    lookup ?= [{ key: 'where', values: {} }]

    query = knex(@config.model.metadata.tableName).select(returning)

    # iterate over every object from 'lookup' attribute
    # every object should contain two keys: 'key' and 'values'
    # 'key' value can be string like 'where', 'whereIn' or object
    # the same as parent object (with 'key' and 'values')
    # 'values' value should be array e.g. ['name', '=', 'sample name']
    # which means that the lookup would be '#{value of key} name = sample name'
    # so for example, if the object was: { key: 'where', values: ['name', '=', 'sample name'] }
    # corresponding query would look like: where "name" = "sample name"
    _.each lookup, (val) ->
      if typeof val.values[0] is 'object' and not (_.isEmpty val.values[0])
        query[val.key]( ->
          _.each val.values, (nestedVal) =>
            if nestedVal.values.length is 2
              @[nestedVal.key](nestedVal.values[0], nestedVal.values[1])
            else
              @[nestedVal.key](nestedVal.values[0], nestedVal.values[1], nestedVal.values[2])
        )
      else if val.values instanceof Array
        if val.values.length is 2
          query[val.key](val.values[0], val.values[1])
        else if val.values.length is 3
          query[val.key](val.values[0], val.values[1], val.values[2])

    query.andWhere('is_deleted', false)
    console.log query.toString()
    query.then (rows) =>
      # if result is to be translated to Model instances, we need to check
      # if query returned at least 1 result, otherwise return empty result
      if toObject and rows.length > 0
        return _.map rows, (val, key) =>
          new @config.model val
      return rows
    .catch (error) ->
      throw error


  # save new instance of specified model
  # @param [Object] payload data of the instance to be saved
  # @param [Array] returning array of fields to be returned from DB
  # @param [Boolean] toObject boolean defining if result should be translated to Model instance
  # @param [Boolean] direct boolean defining if this method is used directly on Model class
  create: ({ payload, returning, toObject, direct } = {}) ->
    # we set default value for 'toObject' parameter as true
    # which means that if it is not passed, query will always return Model instances
    toObject ?= true

    returning ?= @config.returning.basic

    validationPromise = null

    # if this method is called directly on DAO
    # then we need to create new instance of the model, perform validation
    # and translate payload to database representation of the model
    if direct?
      instance = new @config.model payload
      validationPromise = instance.validate()
      payload = instance._toDatabaseFields()

    return Promise.all([validationPromise]).then (validationErrors) =>
      # if the model validation returned object with any keys
      # we throw this result as an error
      # this condition appears only in case when this method was called
      # directly on the DAO object
      if not (_.isEmpty validationErrors[0])
        throw validationErrors[0]

      return knex(@config.model.metadata.tableName)
        .insert(payload, returning)
        .then (rows) =>
          # if toObject was set to true we need to check if created result
          # was returned from the database, otherwise we should return empty result
          if toObject? and rows.length is 1
            return new @config.model rows[0]
          return rows[0]
        .catch (error) ->
          throw error

  # method used to perform bulkCreate on current Model
  # it saves multiple instances at once and returns specified fields or instances
  # @param [Array] data array of objects to be inserted to the database
  # @param [Array] returning array of fields to be returned from the database after create
  # @param [Boolean] toObject boolean specifying if returned objects should be model instances
  bulkCreate: ({ data, returning, toObject } = {}) ->
    # ensure that the 'data' parameter was passed and it is array
    if not data? or not (data instanceof Array)
      throw new Error "'data' argument must be passed to the function and it must be an array!"

    # default value of 'toObject' is set to true
    toObject ?= true
    # default 'returning' array is taken from the Model's DAO configuration
    returning ?= @config.returning.basic

    # it is necessary to validate and create first object from the data
    # explicity in order to perform validation of further elements
    firstObject = new @config.model _.first data
    # remove first objet's data from 'data' array
    data.shift()

    model = @config.model
    tableName = @config.model.metadata.tableName
    insertedReturning = []

    # transaction due to the fact that if any error ocurrs, it is necessary
    # to remove all previously created objects from the database
    return knex.transaction (trx) ->

      # perform validation of first object
      firstObject.validate({ trx: trx }).then (firstObjectValidation) ->
        if not (_.isEmpty firstObjectValidation)
          throw firstObjectValidation

        # insert first object to the database
        knex.insert(firstObject._toDatabaseFields(), returning)
          .into(tableName)
          .transacting(trx)
          .then (result) ->
            if result.length is 1
              insertedReturning.push _.first result
            else
              throw new Error "Error during 'bulkCreate' on #{model.metadata.model}!"

            # perform validation and inserting of any other futher object from
            # the 'data' attribute
            Promise.each data, (singleData) ->
              currentObject = new model singleData
              return currentObject.validate({ trx: trx }).then (currentObjectValidation) ->
                if not (_.isEmpty currentObjectValidation)
                  throw currentObjectValidation

                return knex.insert(currentObject._toDatabaseFields(), returning)
                  .into(tableName)
                  .transacting(trx)
                  .then (result) ->
                    if result.length is 1
                      insertedReturning.push _.first result
                    else
                      throw new Error "Error during 'bulkCreate' on #{model.metadata.model}!"
          .then(trx.commit)
          .catch(trx.rollback)
    .then (inserts) ->
      return insertedReturning
    .catch (error) ->
      throw error

  # update given instance of the model
  # @param [Object] obj current Model's instance
  # @param [Array] returning array of fields to be returned from DB
  # @param [Boolean] toObject boolean defining if result should be translated to Model instance
  update: ({ obj, returning, toObject } = {}) ->
    # we set default value for 'toObject' parameter as true
    # which means that if it is not passed, query will always return Model instances
    toObject ?= true

    if not obj?
      throw new Error "'update()' method needs model instance as 'obj' parameter!"

    returning ?= @config.returning.basic

    lookup = {}
    lookup[@config.lookupField] = obj.get @config.lookupField

    knex(@config.model.metadata.tableName)
      .where(lookup)
      .andWhere('is_deleted', false)
      .update(obj._toDatabaseFields(), returning)
      .then (rows) =>
        # if 'toObject' was set to true we need to check if updated result
        # was returned from the db, otherwise empty result is returned
        if toObject? and rows.length is 1
          return new @config.model rows[0]
        return rows[0]
      .catch (error) ->
        throw error

  # delete given instance of the model
  # @param [Any] lookupValue value for the 'lookupField' of the given model which is used in 'where' sql statement
  delete: (lookupValue, whoDeleted) ->
    deleteData =
      is_deleted: true

    _.extend deleteData, { 'deleted_at': new Date() }
    if whoDeleted? and @config.model.metadata.timestamps
      _.extend deleteData, { 'who_deleted_id': whoDeleted }

    lookup = {}
    lookup[@config.lookupField] = lookupValue

    knex(@config.model.metadata.tableName)
      .where(lookup)
      .andWhere('is_deleted', false)
      .update(deleteData)
      .then (rows) ->
        # returns number of deleted rows so if the 'rows' is equal to 0
        # it means that sql lookup failed - no rows were hit
        return rows
      .catch (error) ->
        throw error

  getReturning: ->
    @config.returning


module.exports = BaseDAO
