'use strict'

_             = require 'underscore'
knexConf      = require process.cwd() + '/knexfile'
knex          = require('knex')(knexConf[process.env.NODE_ENV])


class ManyToOne

  constructor: (@attributes...) ->
    @acceptedParameters = [
      'schema'
      'toModel'
      'referenceField'
      'returning'
      'abstract'
    ]

    @attributes = _.reduce @attributes, (memo, value) ->
      return value

    # we add the abstract attribute to the relation, because it is not directly saved
    # in current model's database table
    @attributes['abstract'] = true

    _.each @attributes, (val, key) =>
      if key not in @acceptedParameters
        throw new TypeError "Key '#{key}' is not accepted in field #{@attributes.name}!"


  # class which is used to acccess ManyToOne relations basing on ForeignKey
  # of referenced model
  # this class assigns instance attributes to Model in order to access
  # e.g. instance.users.all(), instance.users.get()
  class ManyToOneManager

    # class constructor which obtains 3 parameters
    # @param [Object] obj Model instance to which the related fields will be assigned
    # @param [String] name name of specified atribute
    # @param [Object] field attributes of specified related field
    constructor: (@obj, @name, field) ->
      @toModel = require field.attributes.toModel
      @referenceField = field.attributes.referenceField
      @returning = _.map field.attributes.returning, (val) =>
        if val of @toModel::attributes
          "#{@toModel::attributes[val].getDbField(val)} AS #{val}"

    # return all objects related to this instance
    # e.g. return all users of specified account category with '.users.all()'
    # @param [Boolean] toObject specifies if returned elements should be transalted to objects
    all: ({ toObject } = {}) =>
      knex(@toModel.metadata.tableName)
        .select(@returning)
        .where(@referenceField, @obj[@obj.constructor.metadata.primaryKey])
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

    # return specified related object of this instance
    # e.g. get one user which belongs to this account category with '.users.get()'
    # @param [Object] where is a lookup object used in 'WHERE' sql query
    # @param [Boolean] toObject defines if returned element should be translated to object
    get: ({ where, toObject } = {}) ->
      knex(@toModel.metadata.tableName)
        .select(@returning)
        .where(where)
        .andWhere("#{@toModel.metadata.tableName}.is_deleted", false)
        .then (result) =>
          if result.length > 1
            errorObj = {}
            errorObj[@name] = "Query returned more than 1 result"
            errorObj['statusCode'] = 400
            throw errorObj

          if toObject? and result.length is 1
            return new @toModel result[0]
          return result[0]
        .catch (error) =>
          if @obj.constructor.metadata.errorLogger? and not error.statusCode?
            @obj.constructor.metadata.errorLogger.error error
          throw error

  # class Getter
  @getManyToOneManager: ->
    return ManyToOneManager


module.exports = ManyToOne
