'use strict'

knexConf    = require process.cwd() + '/knexfile'
knex        = require('knex')(knexConf[process.env.NODE_ENV])
_           = require 'underscore'
Promise     = require 'bluebird'

moduleKeywords = ['extended', 'included']


class BaseDAO

  @applyConfiguration: (obj) ->
    @::config = {}
    for key, value of obj when key not in moduleKeywords
      @::config[key] = value

    obj.included?.apply(@)
    this

  # constructor of BaseDAO, obtains two parameters
  # @param [Object] model current Model Class
  # @param [Object] errorLogger log4j logger object for logging errors
  constructor: (model) ->
    @config ?= {}
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
          "#{key}"
      @config.returning.basic = _.without returningArray, undefined

    # iterate over every array from config.returning and translate camelCase field
    # to database snake_case equivalent for current model
    newReturning = {}
    _.each @config.returning, (returningArray, key) =>
      newReturningArray = _.map returningArray, (fieldName) =>
        if not ([" AS "].some (word) -> ~fieldName.indexOf word)
          if fieldName not of @config.model::attributes
            throw new Error "Field '#{fieldName}' from 'config.returning' of #{@config.model.metadata.model} is not an attribute of this model"
          "#{@config.model::attributes[fieldName].getDbField(fieldName)} AS #{fieldName}"
        else
          "#{fieldName}"
      newReturning[key] = newReturningArray

    @config.returning = newReturning


  # return specified instance of given Model by it's 'primaryKey' attribute
  # @param [Any] val value of the primary key
  # @param [Array] returning array of fields to be returned from the DB
  # @param [Boolean] toObject boolean defining if result should be translated to Model instance
  getById: ({ pk, returning, toObject } = {}) ->
    # we set default value for 'toObject' parameter as true
    # which means that if it is not passed, query will always return Model instances
    toObject ?= true

    if not pk?
      throw new Error "'getById' method requires value for 'pk' parameter!"

    returning ?= @config.returning.basic

    knex(@config.model.metadata.tableName)
      .where(@config.model.metadata.primaryKey, pk)
      .andWhere('is_deleted', false)
      .select(returning)
      .then (rows) =>
        # throw error if query returned more than 1 row - it definitely should not do that
        if rows.length > 1
          throw new Error "'getById()' method on '#{@config.model.metadata.model}' returned more than 1 row!"

        # if 'toObject' was set to true we need to check if 'get' method returned any rows
        # if yes, then we create instance, otherwise we return empty result
        if toObject and rows.length is 1
          return new @config.model rows[0]
        return rows[0]
      .catch (error) =>
        if @config.errorLogger?
          @config.errorLogger.error error
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
      throw new Error "'get()' method requires value for 'lookup' parameter!"

    where = {}
    _.each lookup, (val, key) =>
      if not (key of @config.model::attributes)
        throw new Error "'#{key}' does not match any attribute of model '#{@config.model.metadata.model}' in '.get()' method of DAO"
      databaseKey = @config.model::attributes[key].getDbField(key)
      where[databaseKey] = val

    returning ?= @config.returning.basic

    knex(@config.model.metadata.tableName)
      .where(where)
      .andWhere('is_deleted', false)
      .select(returning)
      .then (rows) =>
        # throw error if query returned more than 1 row - it definitely should not do that
        if rows.length > 1
          throw new Error "'get()' method on '#{@config.model.metadata.tableName}' returned more than 1 row!"

        # if 'toObject' was set to true we need to check if 'get' method returned any rows
        # if yes, then we create instance, otherwise we return empty result
        if toObject and rows.length is 1
          return new @config.model rows[0]
        return rows[0]
      .catch (error) =>
        if @config.errorLogger?
          @config.errorLogger.error error
        throw error

  # return all instances of given Model
  # @param [Array] returning array of fields to be returned from the DB e.g. ['id', 'name']
  # @param [Boolean] toObject boolean defining if result should be translated to Model instance
  all: ({ returning, toObject, orderBy } = {}) ->
    # we set default value for 'toObject' parameter as true
    # which means that if it is not passed, query will always return Model instances
    toObject ?= true

    # if 'orderBy' is a string (field name), we check if it exists in Model attributes
    if orderBy? and typeof orderBy is 'string' and orderBy of @config.model::attributes
      column = @config.model::attributes[orderBy].attributes.dbField
      # if it does exist, we get the dbField and set the direction to 'asc'
      orderBy =
        column: column
        direction: 'asc'
    # otherwise, if 'orderBy' is object, we check if it has 'column' attribute and if it exists in Model's attributes
    else if orderBy? and _.isObject(orderBy) and 'column' in _.keys(orderBy) and orderBy.column of @config.model::attributes
      orderBy.column = @config.model::attributes[orderBy.column].attributes.dbField

      # if the direction attribute is present in orderBy, we check if it is one of ['asc', 'desc']
      if orderBy.direction? and not (orderBy.direction in ['asc', 'desc'])
        throw new Error "'direction' attribute of 'orderBy' object should be one of: asc, desc!"

      # if there was no 'direction' attribute in 'orderBy' object, we set default value to 'asc'
      orderBy.direction ?= 'asc'
    else if orderBy?
      # otherwise throw an error with proper message
      throw new Error "'orderBy' should be an object with 'column' and 'direction' attributes " +
                      "or name of the field of #{@config.model.metadata.model}!"

    returning ?= @config.returning.basic

    knexQuery = knex(@config.model.metadata.tableName)
      .select(returning)
      .where('is_deleted', false)

    # apply ordering if 'orderBy' exists
    if orderBy?
      knexQuery.orderBy(orderBy.column, orderBy.direction)

    knexQuery.then (rows) =>
        # if result is to be translated to Model instances, we need to check
        # if query returned at least 1 result, otherwise return empty result
        if toObject and rows.length > 0
          return _.map rows, (val, key) =>
            new @config.model val
        return rows
      .catch (error) =>
        if @config.errorLogger?
          @config.errorLogger.error error
        throw error

  # find Model's instances fulfilling given lookup values
  # @param [Array] lookup array of objects with keys: 'key', 'values'. Defines the filtering attributes like 'where', 'orWhere', 'whereIn' etc.
  # @param [Array] returning array of fields to be returned from the DB e.g. ['id', 'name']
  # @param [Boolean] toObject boolean defining if result should be translated to Model instance
  filter: ({ lookup, returning, toObject, orderBy } = {}) ->
    # we set default value for 'toObject' parameter as true
    # which means that if it is not passed, query will always return Model instances
    toObject ?= true

    returning ?= @config.returning.basic
    # default 'lookup' value is set to '{}' if none was passed
    lookup ?= [{ key: 'where', values: {} }]

    # if 'orderBy' is a string (field name), we check if it exists in Model attributes
    if orderBy? and typeof orderBy is 'string' and orderBy of @config.model::attributes
      column = @config.model::attributes[orderBy].attributes.dbField
      # if it does exist, we get the dbField and set the direction to 'asc'
      orderBy =
        column: column
        direction: 'asc'
    # otherwise, if 'orderBy' is object, we check if it has 'column' attribute and if it exists in Model's attributes
    else if orderBy? and _.isObject(orderBy) and 'column' in _.keys(orderBy) and orderBy.column of @config.model::attributes
      orderBy.column = @config.model::attributes[orderBy.column].attributes.dbField

      # if the direction attribute is present in orderBy, we check if it is one of ['asc', 'desc']
      if orderBy.direction? and not (orderBy.direction in ['asc', 'desc'])
        throw new Error "'direction' attribute of 'orderBy' object should be one of: asc, desc!"

      # if there was no 'direction' attribute in 'orderBy' object, we set default value to 'asc'
      orderBy.direction ?= 'asc'
    else if orderBy?
      # otherwise throw an error with proper message
      throw new Error "'orderBy' should be an object with 'column' and 'direction' attributes " +
                      "or name of the field of #{@config.model.metadata.model}!"

    query = knex(@config.model.metadata.tableName).select(returning)

    # iterate over every object from 'lookup' attribute
    # every object should contain two keys: 'key' and 'values'
    # 'key' value can be string like 'where', 'whereIn' or object
    # the same as parent object (with 'key' and 'values')
    # 'values' value should be array e.g. ['name', '=', 'sample name']
    # which means that the lookup would be '#{value of key} name = sample name'
    # so for example, if the object was: { key: 'where', values: ['name', '=', 'sample name'] }
    # corresponding query would look like: where "name" = "sample name"
    model = @config.model
    _.each lookup, (val) ->
      if typeof val.values[0] is 'object' and not (_.isEmpty val.values[0])
        query[val.key]( ->
          _.each val.values, (nestedVal) =>
            databaseKey = model::attributes[nestedVal.values[0]].getDbField(nestedVal.values[0])
            if nestedVal.values.length is 2
              @[nestedVal.key](databaseKey, nestedVal.values[1])
            else
              @[nestedVal.key](databaseKey, nestedVal.values[1], nestedVal.values[2])
        )
      else if val.values instanceof Array
        databaseKey = model::attributes[val.values[0]].getDbField(val.values[0])
        if val.values.length is 2
          query[val.key](databaseKey, val.values[1])
        else if val.values.length is 3
          query[val.key](databaseKey, val.values[1], val.values[2])

    query.andWhere('is_deleted', false)

    # apply ordering to the query if orderBy exists
    if orderBy?
      query.orderBy(orderBy.column, orderBy.direction)

    query.then (rows) =>
      # if result is to be translated to Model instances, we need to check
      # if query returned at least 1 result, otherwise return empty result
      if toObject and rows.length > 0
        return _.map rows, (val, key) =>
          new @config.model val
      return rows
    .catch (error) =>
      if @config.errorLogger?
        @config.errorLogger.error error
      throw error


  # save new instance of specified model
  # @param [Object] data data of the instance to be saved
  # @param [Array] returning array of fields to be returned from DB
  # @param [Boolean] toObject boolean defining if result should be translated to Model instance
  # @param [Boolean] direct boolean defining if this method is used directly on Model class
  create: ({ data, returning, toObject, direct } = {}) ->
    # we set default value for 'toObject' parameter as true
    # which means that if it is not passed, query will always return Model instances
    toObject ?= true
    direct ?= true

    returning ?= @config.returning.basic

    validationPromise = null

    # if this method is called directly on DAO
    # then we need to create new instance of the model, perform validation
    # and translate data to database representation of the model
    if direct
      instance = new @config.model data
      validationPromise = instance.validate()
      data = instance._toDatabaseFields()

    return Promise.all([validationPromise]).then (validationErrors) =>
      # if the model validation returned object with any keys
      # we throw this result as an error
      # this condition appears only in case when this method was called
      # directly on the DAO object
      if not (_.isEmpty validationErrors[0])
        throw validationErrors[0]

      return knex(@config.model.metadata.tableName)
        .insert(data, returning)
        .then (rows) =>
          # if toObject was set to true we need to check if created result
          # was returned from the database, otherwise we should return empty result
          if toObject? and rows.length is 1
            return new @config.model rows[0]
          return rows[0]
        .catch (error) =>
          if @config.errorLogger?
            @config.errorLogger.error error
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
    .catch (error) =>
      if @config.errorLogger?
        @config.errorLogger.error error
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
    else if obj? and not (obj instanceof @config.model)
      throw new Error "'obj' attribute passed to #{@constructor.name} 'update()' method should be an instance of #{@config.model.metadata.model}"

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
      .catch (error) =>
        if @config.errorLogger?
          @config.errorLogger.error error
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
      .catch (error) =>
        if @config.errorLogger?
          @config.errorLogger.error error
        throw error

  getReturning: ->
    @config.returning


module.exports = BaseDAO
