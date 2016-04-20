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

    _.each @config.returning, (returningArray, key) =>
      _.each returningArray, (field) =>
        if not (field of @config.model::attributes) and field isnt '*'
          throw new Error "Field '#{field}' of 'config.returning' of #{@config.model.metadata.model} is not an attribute of this model."

  # method which obtains array of fields to be returned from current DAO method
  # it validates whether passed fields are correct attributes of current model
  # and translates them to it's equivalent database representation
  # @param [Array] returning array of fields to be returned from current DAO operation
  _translateReturningToDatabase: (returning) ->

    # if 'returning' array was passed to the metod in form of array, we need to check if all those fields
    # are attributes of given model
    if returning? and _.isArray(returning)
      tempReturningArray = _.each returning, (field) =>
        # check if every value of array is string and is attribute of model and is not set as an abstract attribute
        if _.isString(field) and field of @config.model::attributes and not @config.model::attributes[field].attributes.abstract?
          field
        else
          # otherwise throw an error
          throw new Error "Field '#{field}' from #{@config.model.metadata.model} is not an attribute of this model or is set as an 'abstract'."

    # otherwise if 'returning' was passed in form of String, we need to check if this string is one of dao.config.returning arrays
    else if returning? and _.isString(returning)
      if returning of @config.returning
        defaultReturningArray = @config.returning[returning]
      else
        # if passed 'returning' string is not one of dao.config.returning, throw error with appropriate message
        throw new Error "Returning '#{returning}' is not one of dao.config.returning of '#{@config.model.metadata.model}'."

    # if the 'returning' was not passed or it isn't a string or array, use the configuration returning array
    else if not returning? or (returning? and not _.isArray(returning) and not _.isString(returning))
      defaultReturningArray = if @config.returning? and @config.returning.basic? then @config.returning.basic else ['*']

    # if the returning array constains '*' then it means that all fields should be returned
    if defaultReturningArray? and _.contains(defaultReturningArray, '*')
      tempReturningArray = _.map(@config.model::attributes, (fieldVal, modelField) =>
        if not fieldVal.attributes.abstract? and not (modelField of @config.model::timestampAttributes)
          "#{modelField}"
      )
    else if defaultReturningArray?
      tempReturningArray = _.clone defaultReturningArray

    # remove undefined values from returning array
    returningArray = _.without tempReturningArray, undefined

    # check if primary key of model is in the returning array
    # if no, then append it to the beginning of the array
    if _.indexOf(returningArray, @config.model.metadata.primaryKey) is -1
      returningArray.unshift @config.model.metadata.primaryKey

    # map field values to database equivalent e.g. account_category AS accountCategory
    finalReturningArray = _.map returningArray, (field) =>
      "#{@config.model::attributes[field].getDbField(field)} AS #{field}"

    finalReturningArray


  # method which validates if passed 'orderBy' property to current DAO method is correct
  # it should be a string which is one of current model's attributes, optionally with '-' sign at the beginning
  # in order to define descending direction of ordering
  # @param [String] orderBy name of model's attribute by which the results will be sorted, can be with '-' sign
  _validateOrderBy: (orderBy) =>
    # check if 'orderBy' is string and is name of attribute of current model and does not have '-' sign at the beginning
    if orderBy? and typeof orderBy is 'string' and orderBy.charAt(0) isnt '-' and orderBy of @config.model::attributes
      column = @config.model::attributes[orderBy].attributes.dbField
      orderByObject =
        column: column
        direction: 'asc'
    # the same conditions as previously, except that we check if there is a '-' sign at the beginning
    # which defines the ordering direction as 'descending'
    else if orderBy? and typeof orderBy is 'string' and orderBy.charAt(0) is '-' and orderBy.substr(1) of @config.model::attributes
      column = @config.model::attributes[orderBy.substr(1)].attributes.dbField
      orderByObject =
        column: column
        direction: 'desc'
    else if orderBy?
      throw new Error "'orderBy' attribute of '#{@constructor.name}' method should be attribute of #{@config.model.metadata.model}, optionaly with '-' sign!"
    else
      orderByObject =
        column: @config.model.metadata.primaryKey
        direction: 'asc'

    orderByObject


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

    try
      returningArray = @_translateReturningToDatabase(returning)
    catch error
      return new Promise (resolve, reject) ->
        reject error


    knex(@config.model.metadata.tableName)
      .where(@config.model.metadata.primaryKey, pk)
      .andWhere('is_deleted', false)
      .select(returningArray)
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

    try
      returningArray = @_translateReturningToDatabase(returning)
    catch error
      return new Promise (resolve, reject) ->
        reject error


    knex(@config.model.metadata.tableName)
      .where(where)
      .andWhere('is_deleted', false)
      .select(returningArray)
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

    try
      returningArray = @_translateReturningToDatabase(returning)
      orderByObject = @_validateOrderBy(orderBy)
    catch error
      return new Promise (resolve, reject) ->
        reject error

    knexQuery = knex(@config.model.metadata.tableName)
      .select(returningArray)
      .where('is_deleted', false)

    # apply ordering if 'orderBy' exists
    if orderByObject?
      knexQuery.orderBy(orderByObject.column, orderByObject.direction)

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

  filterPaged: ({ lookup, orderBy, returning, toObject, limit, page }) ->
    lookup ?= {}
    lookup['is_deleted'] = false
    toObject ?= true

    try
      returningArray = @_translateReturningToDatabase(returning)
      orderByObject = @_validateOrderBy(orderBy)
    catch error
      return new Promise (resolve, reject) ->
        reject error

    return knex(@config.model.metadata.tableName)
      .select(returningArray)
      .where(lookup)
      .orderBy(orderByObject.column, orderByObject.direction)
      .limit(limit)
      .offset((page - 1) * limit)
      .then (result) ->
        return result
      .catch (error) ->
        throw error

  # find Model's instances fulfilling given lookup values
  # @param [Array] lookup array of objects with keys: 'key', 'values'. Defines the filtering attributes like 'where', 'orWhere', 'whereIn' etc.
  # @param [Array] returning array of fields to be returned from the DB e.g. ['id', 'name']
  # @param [Boolean] toObject boolean defining if result should be translated to Model instance
  filter: ({ lookup, returning, toObject, orderBy } = {}) ->
    # we set default value for 'toObject' parameter as true
    # which means that if it is not passed, query will always return Model instances
    toObject ?= true

    # default 'lookup' value is set to '{}' if none was passed
    lookup ?= [{ key: 'where', values: {} }]

    try
      returningArray = @_translateReturningToDatabase(returning)
      orderByObject = @_validateOrderBy(orderBy)
    catch error
      return new Promise (resolve, reject) ->
        reject error

    query = knex(@config.model.metadata.tableName).select(returningArray)

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
    if orderByObject?
      query.orderBy(orderByObject.column, orderByObject.direction)

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

    try
      returningArray = @_translateReturningToDatabase(returning)
    catch error
      return new Promise (resolve, reject) ->
        reject error

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
        .insert(data, returningArray)
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

    try
      returningArray = @_translateReturningToDatabase(returning)
    catch error
      return new Promise (resolve, reject) ->
        reject error

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
        knex.insert(firstObject._toDatabaseFields(), returningArray)
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

                return knex.insert(currentObject._toDatabaseFields(), returningArray)
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

    try
      returningArray = @_translateReturningToDatabase(returning)
    catch error
      return new Promise (resolve, reject) ->
        reject error

    lookup = {}
    lookup[@config.lookupField] = obj.get @config.lookupField

    knex(@config.model.metadata.tableName)
      .where(lookup)
      .andWhere('is_deleted', false)
      .update(obj._toDatabaseFields(), returningArray)
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
  # @param [Integer] whoDeleted id of user who performed this operation
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

  # delete multiple instances of the model
  # @param [Array] ids array of ids of model instances to be deleted
  # @param [Integer] whoDeleted id of user who performed this operation
  deleteMany: (ids, whoDeleted) ->
    # check if 'ids' argument is array
    if not (_.isArray(ids))
      throw new Error "First argument of 'deleteMany' should be array of IDs"

    deleteData =
      is_deleted: true

    _.extend deleteData, { 'deleted_at': new Date() }
    if whoDeleted? and @config.model.metadata.timestamps
      _.extend deleteData, { 'who_deleted_id': whoDeleted }

    deletedCounter = 0
    return knex.transaction (trx) =>

      Promise.each ids, (id) =>

        lookup = {}
        lookup[@config.lookupField] = id
        lookup['is_deleted'] = false

        return knex(@config.model.metadata.tableName)
          .where(lookup)
          .update(deleteData)
          .transacting(trx)
          .then (rows) =>

            # if rows === 0 it means that no result was updated (deleted in this case)
            # so throw an error with appropriate message that specified instance does not exist
            # rolls back whole transaction
            if rows is 0
              throw new Error "'deleteMany()' - #{@config.model.metadata.model} with id = #{id} does not exist!"
            deletedCounter += 1

    .then (finalResult) ->
      return finalResult
    .catch (error) =>
      if @config.errorLogger?
        @config.errorLogger.error error
      throw error


  getReturning: ->
    @config.returning


module.exports = BaseDAO
