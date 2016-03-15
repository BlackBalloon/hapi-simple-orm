'use strict'

_           = require 'underscore'
knexConf    = require process.cwd() + '/knexfile'
knex        = require('knex')(knexConf[process.env.NODE_ENV])
Joi         = require 'joi'


class ManyToMany

  @acceptedParameters: [
    'schema'
    'toModel'
    'through'
    'throughFields'
    'returning'
    'name'
    'abstract'
  ]

  constructor: (@attributes...) ->
    @attributes = _.reduce @attributes, (memo, value) ->
      return value

    # default Joi validation schema for M2M relation is array of positive integers
    if not(_.has @attributes, 'schema')
      _.extend @attributes, { schema: Joi.array(Joi.number().integer().positive()) }

    # we add the abstract attribute to the relation, because it is not directly saved
    # in current model's database table
    @attributes['abstract'] = true

    _.each @attributes, (val, key) =>
      if key not in @constructor.acceptedParameters
        throw new TypeError "Key '#{key}' is not accepted in field #{@attributes.name}!"


  # This class creates access to related attributes from many-to-many
  # relationship. It adds instance attributes to every model,
  # after initialization, the instance can access it's related attributes
  # via '.attribute-name.method' e.g. '.permissions.all()'
  # where method is one of this class's methods
  class ManyToManyManager

    # constructor of this class takes two parameters:
    # @param [Object] obj instance of Model to assign related attributes to
    # @param [String] name name of the attributes e.g. 'parameters'
    constructor: (@obj, @name, field) ->
      @toModel = require field.attributes.toModel
      @thisModel = @obj.constructor.metadata
      @through = field.attributes.through
      @throughFields = field.attributes.throughFields
      @returning = _.map field.attributes.returning, (val) =>
        "#{@toModel.metadata.tableName}.#{@obj.attributes[val].getDbField(val)} AS #{val}"

    # returns all related objects
    # @param [Boolean] toObject defines if returned elements should be translated to Model instances
    all: ({ toObject } = {}) =>
      knex(@toModel.metadata.tableName)
        .select(@returning)
        .leftJoin(@through, "#{@toModel.metadata.tableName}.#{@toModel.metadata.primaryKey}", "#{@through}.#{@throughFields[1]}")
        .where("#{@through}.#{@throughFields[0]}", @obj[@obj.constructor.metadata.primaryKey])
        .andWhere("#{@toModel.metadata.tableName}.is_deleted", false)
        .then (result) =>
          if toObject?
            relatedObjects = []
            _.each result, (val) =>
              relatedObjects.push new @toModel val
            return relatedObjects
          return result
        .catch (error) =>
          if @obj.constructor.metadata.errorLogger?
            @obj.constructor.metadata.errorLogger.error error
          throw error

    # returns specified related object
    # @param [Number] id ID of related object to return
    # @param [Boolean] toObject defines if returned element should be translated to Model instance
    get: ({ id, toObject } = {}) =>
      knex(@toModel.metadata.tableName)
        .select(@returning)
        .where("#{@toModel.metadata.primaryKey}", id)
        .andWhere('is_deleted', false)
        .then (result) =>
          if toObject? and result.length is 1
            return new @toModel result[0]
          return result[0]
        .catch (error) =>
          if @obj.constructor.metadata.errorLogger?
            @obj.constructor.metadata.errorLogger.error error
          throw error

    # adds specified objects to set of related objects
    # @param [Array] id Array of IDs of objects to be added
    add: (id...) =>
      if not id?
        throw new Error "IDs of related objects are required"

      # _.flatten is used in case array of IDs is passed
      id = _.flatten id

      # here we check if the model's instance to which we will save related objects
      # is already saved in the database - has 'primaryKey' value
      if not @obj[@obj.constructor.metadata.primaryKey]?
        throw new Error "First you need to save the instance in order to assign related objects to it!"

      # we use transaction in this case because multiple rows are
      # being affected at once
      knex.transaction (transaction) =>
        knex(@toModel.metadata.tableName)
          .count('id')
          .whereIn('id', id)
          .andWhere('is_deleted', false)
          .transacting(transaction)
          .then (result) =>
            # here we check if all passed related IDs exist in the database
            # if any of them does not exist, we return 404 error
            if parseInt(result[0].count) isnt id.length
              errorObj = {}
              errorObj[@name] = "Specified related object does not exist!"
              errorObj['statusCode'] = 404
              throw errorObj
            else
              # we find all already existing related objects in order to omit situation
              # in which we will add the same relation twice
              knex(@through)
                .select(@throughFields[1])
                .where(@throughFields[0], @obj[@obj.constructor.metadata.primaryKey])
                .transacting(transaction)
                .then (result) =>
                  insertValues = []
                  _.each id, (val) =>
                    # we select the related objects only if they do not already exist in the M2M relation
                    # e.g. if category has permissions 1,2 and we want to add permissions 2,3
                    # it ensures that only the value 3 will be added to the relation (2 already exists)
                    if val not in _.pluck result, @throughFields[1]
                      obj = {}
                      obj[@throughFields[0]] = @obj[@obj.constructor.metadata.primaryKey]
                      obj[@throughFields[1]] = val
                      insertValues.push obj
                  if insertValues.length > 0
                    return knex(@through)
                      .insert(insertValues, @throughFields[1])
                      .transacting(transaction)
                  else
                    return []
          .then(transaction.commit)
          .catch(transaction.rollback)
      .then (rows) ->
        return rows
      .catch (error) =>
        # we omit the error with 'statusCode' thrown inside the transaction
        # it will be used in the request response
        # we only log errors coming directly from the Knex
        if @obj.constructor.metadata.errorLogger? and not error.statusCode?
          @obj.constructor.metadata.errorLogger.error error
        throw error

    # clears all curent related objects and defines new set of them
    # @param [Array] id Array of IDs of objects to be set
    set: (id...) =>
      if not id?
        throw new Error "IDs of related objects are required!"

      # here we check if the model's instance to which we will save related objects
      # is already saved in the database - has 'primaryKey' value
      if not @obj[@obj.constructor.metadata.primaryKey]?
        throw new Error "First you need to save the instance in order to assign related objects to it!"

      id = _.flatten id
      insertValues = _.map id, (val) =>
        obj = {}
        obj[@throughFields[0]] = @obj[@obj.constructor.metadata.primaryKey]
        obj[@throughFields[1]] = val
        obj

      knex.transaction (transaction) =>
        # here we check if passed array of IDs exist in 'toModel' table
        # if the count length is equal to number of elements in passed array
        # then all passed IDs exist in 'toModel' table
        # otherwise we throw error with message
        knex(@toModel.metadata.tableName)
          .count('id')
          .whereIn('id', id)
          .andWhere('is_deleted', false)
          .then (result) =>
            if parseInt(result[0].count) isnt id.length
              errorObj = {}
              errorObj[@name] = "Specified related object does not exist!"
              errorObj['statusCode'] = 404
              throw errorObj
            else
              return knex(@through)
                .where(@throughFields[0], @obj[@obj.constructor.metadata.primaryKey])
                .del()
                .transacting(transaction)
                .then (result) =>
                  return knex(@through)
                          .insert(insertValues, @throughFields[1])
                          .transacting(transaction)
          .then(transaction.commit)
          .catch(transaction.rollback)
      .then (rows) ->
        return rows
      .catch (error) =>
        # we omit the error with 'statusCode' thrown inside the transaction
        # it will be used in the request response
        # we only log errors coming directly from the Knex
        if @obj.constructor.metadata.errorLogger? and not error.statusCode?
          @obj.constructor.metadata.errorLogger.error error
        throw error

  @getManyToManyManager: ->
    return ManyToManyManager


module.exports = ManyToMany
