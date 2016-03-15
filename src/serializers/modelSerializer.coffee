'use strict'

_             = require 'underscore'
Promise       = require 'bluebird'
knexConf      = require process.cwd() + '/knexfile'
knex          = require('knex')(knexConf[process.env.NODE_ENV])
ForeignKey    = require './../fields/foreignKey'
BaseModel     = require './../model/baseModel'
ManyToMany    = require './../fields/manyToMany'
ManyToOne     = require './../fields/manyToOne'

PrimaryKeyRelatedSerializer = require './primaryKeyRelatedSerializer'
FieldRelatedSerializer      = require './fieldRelatedSerializer'
Serializer                  = require './serializer'


# object which specifies which method should be used
# in order to retrieve value for current field
# should be extended any time new kind of field appears
methods = {
  'ForeignKey': '_getForeignKeyObject'
  'ManyToMany': '_getManyToManyObjects'
  'ManyToOne': '_getManyToOneObjects'
  'BaseField': '_getBaseFieldValue'
}


class ModelSerializer extends Serializer

  @acceptedParameters = [
    'data'
    'many'
    'readOnly'
    'instance'
    'fields'
    'excludeFields'
  ]

  # ModelSerializer constructor
  # it checks whether passed objects are instance of Model specified in the
  # serializer's config attribute
  constructor: ({ @data, @many, @instance } = {}) ->
    # here we check if data passed to the serializer is instance/instances
    # of Model defined in the 'config.model' attribute of the serializer
    # checking depends on the '@many' attribute passed to the serializer
    if @data? and not @many and not (@data instanceof @constructor.config.model)
      throw new Error "Data passed to the #{@constructor.name} must be an instance of #{@constructor.config.model.metadata.model}!"
    else if @data? and @many
      # here we check if every array element of '@data' is instance of specified Model
      if (_.filter @data, (val) => val instanceof @constructor.config.model).length isnt @data.length
        throw new Error "Data passed to the #{@constructor.name} must be an instance of #{@constructor.config.model.metadata.model}!"

    # we set the 'many' parameter to false if it wasnt passed to the constructor
    @many ?= false
    super arguments['0']

    # if the instance was passed to the constructor, we need to check
    # if it is an instance of serializer's specified model
    if @instance?
      if not (@instance instanceof @constructor.config.model)
        throw new TypeError "Instance passed to the #{@constructor.name} is not an instance of #{@constructor.config.model.name}"


  # simple method which returns value for specified field of given object
  # @param [Object] obj current model's instance
  # @param [String] key name of the field
  _getBaseFieldValue: (obj, key) ->
    return new Promise (resolve, reject) ->
      resolve obj.get(key)

  # method used to get specified values for Foreign Key object
  # @param [Object] obj current model's instance
  # @param [String] key name of current field to serialize
  # @param [Object] serializer instance of serializer to be used on this field
  _getForeignKeyObject: (obj, key, serializer) ->
    if not (serializer instanceof Serializer) or obj[key] is null
      return new Promise (resolve, reject) ->
        resolve obj[key]

    model = obj.attributes[key].attributes.referenceModel
    field = obj.attributes[key].attributes.referenceField
    val = obj[key]

    lookup = {}
    lookup[field] = val

    # here we select only those fields from related serializer
    # which belong to attributes of related Model
    # e.g. id, name. All other (m2m, m2o are not taken into consideration
    # because they require other serializer)
    # we can also take into consideration the FieldRelatedSerializer
    returning = []
    if serializer instanceof FieldRelatedSerializer
      # here we check if the field passd to FieldRelatedSerializer instance
      # belongs to any of the current Model instance attributes
      # if no - we throw an error with message
      if not model::attributes[serializer.field]?
        throw new TypeError "#{serializer.field} is not an attribute of #{model.metadata.model}!"
      returning = ["#{model::attributes[serializer.field].getDbField(serializer.field)} AS #{serializer.field}"]
    else if serializer instanceof PrimaryKeyRelatedSerializer
      returning = ["#{model.metadata.primaryKey}"]
    else
      _.each serializer.serializerFieldsKeys, (relatedKey) ->
        if relatedKey of model::attributes and not model::attributes[relatedKey].attributes.abstract?
          # we need to create RETURN fields with ALIAS from the database
          # in order to transform them to Model instances
          # e.g. 'first_name AS firstName'
          returning.push "#{model::attributes[relatedKey].getDbField(relatedKey)} AS #{relatedKey}"

    return model
            .objects()
            .get(
              lookup: lookup
              returning: returning
              toObject: true
            )
            .then (getResult) ->
              serializer.setData getResult
              return serializer.getData().then (values) ->
                return values
            .catch (error) ->
              if model.metadata.errorLogger?
                model.metadata.errorLogger.error error
              throw error

  # returns array of related objects and applies related serializer to each of them
  # e.g. permissions of specified account category
  # @param [Object] obj current model's instance
  # @param [String] key name of current field to serialize
  # @param [Object] serializer instance of serializer to be used on this field
  _getManyToManyObjects: (obj, key, serializer) ->
    # get referenced model
    model = require obj.attributes[key].attributes.toModel
    # connecting table for both models
    through = obj.attributes[key].attributes.through
    # fields from the connecting table e.g. first_id, second_id
    throughFields = obj.attributes[key].attributes.throughFields
    # value of current model's instance for it's primary key
    val = obj[obj.constructor.metadata.primaryKey]
    # set default serializer to 'PrimaryKeyRelatedSerializer' - array of IDs
    serializer ?= new PrimaryKeyRelatedSerializer many: true

    # defining fields that should be returned from the related objects
    # but first we need to check if the serializer isnt PrimaryKeyRelatedSerializer
    # because it has no config.fields attribute defined
    # and the only returning field would be 'id' in this case
    returning = []
    if serializer instanceof PrimaryKeyRelatedSerializer
      returning = ["#{model.metadata.tableName}.#{model.metadata.primaryKey}"]
    else if serializer instanceof FieldRelatedSerializer
      # checking the FieldRelatedSerializer field of Model
      if not model::attributes[serializer.field]?
        throw new TypeError "#{serializer.field} is not an attribute of #{model.metadata.model}!"
      returning = ["#{model.metadata.tableName}.#{model::attributes[serializer.field].getDbField(serializer.field)} AS #{serializer.field}"]
    else
      _.each serializer.serializerFieldsKeys, (serFieldKey) ->
        if serFieldKey of model::attributes and not model::attributes[serFieldKey].attributes.abstract?
          # translation of database fields to Model fields (attributes)
          returning.push "#{model.metadata.tableName}.#{model::attributes[serFieldKey].getDbField(serFieldKey)} AS #{serFieldKey}"

    # here we create the query using knex in order to retrieve M2M relation
    # e.g. permissions of specified account category
    # when they are retrieved from the database, they are translated to Model instances
    # and are applied to the prepared serializer in order to define how they are retrieved
    return knex(model.metadata.tableName)
            .select(returning)
            .leftJoin(through, "#{through}.#{throughFields[1]}", "#{model.metadata.tableName}.id")
            .where("#{through}.#{throughFields[0]}", val)
            .andWhere("#{model.metadata.tableName}.is_deleted", false)
            .then (m2mresult) ->
              m2mInstances = _.map m2mresult, (val, key) ->
                new model val

              serializer.setData m2mInstances
              return serializer.getData().then (values) ->
                return values
            .catch (error) ->
              if model.metadata.errorLogger?
                model.metadata.errorLogger.error error
              throw error

  # return array of M2O relation e.g. users of specified account category
  # @param [Object] obj current model's instance
  # @param [String] key name of current field to serialize
  # @param [Object] serializer instance of serializer to be used on this field
  _getManyToOneObjects: (obj, key, serializer) ->
    # get referenced model
    model = require obj.attributes[key].attributes.toModel
    # get field from referenced model e.g. permission_id
    field = obj.attributes[key].attributes.referenceField
    # value of current model's instance for it's primary key
    # used for lookup in referenced model
    val = obj[obj.constructor.metadata.primaryKey]
    # set default serializer to 'PrimaryKeyRelatedSerializer' - array of IDs
    serializer ?= new PrimaryKeyRelatedSerializer many: true

    returning = []
    if serializer instanceof PrimaryKeyRelatedSerializer
      returning = ["#{model.metadata.primaryKey}"]
    else if serializer instanceof FieldRelatedSerializer
      # checking the FieldRelatedSerializer field of Model
      if not model::attributes[serializer.field]?
        throw new TypeError "#{serializer.field} is not an attribute of #{model.metadata.model}!"
      returning = ["#{model::attributes[serializer.field].getDbField(serializer.field)} AS #{serializer.field}"]
    else
      _.each serializer.serializerFieldsKeys, (serFieldKey) ->
        if serFieldKey of model::attributes and not model::attributes[serFieldKey].attributes.abstract?
          returning.push "#{model::attributes[serFieldKey].getDbField(serFieldKey)} AS #{serFieldKey}"

    return knex(model.metadata.tableName)
            .select(returning)
            .where(field, val)
            .andWhere('is_deleted', false)
            .then (m2mresult) ->
              m2mInstances = _.map m2mresult, (val, key) ->
                new model val

              serializer.setData m2mInstances
              return serializer.getData().then (values) ->
                return values
          .catch (error) ->
            if model.metadata.errorLogger?
              model.metadata.errorLogger.error error
            throw error

  _getSingleObject: (obj) ->
    if not obj?
      obj = @data

    objectPromises = []
    _.each @serializerFields, (val, key) =>

      if val.constructor.name is 'String'
        key = val
      else
        key = (_.keys val)[0]

      # here we check if serializer's config field belongs to Model's attributes
      # as well as we check if current field is not set as excluded
      # according to 'constructor.config.excludeFields' parameter
      if not (key in @constructor.config.excludeFields) and key of obj.attributes
        # taking the method name to be used on current field basing on the field's constructor
        # different methods are used for instances of BaseField
        # and for related objects (foreign keys, m2m or m2o)
        methodName = methods[obj.attributes[key].constructor.name]
        objectPromises.push ModelSerializer::[methodName](obj, key, val[key]).then (result) ->
          return result

    Promise.all(objectPromises).then (objectValues) =>
      # get rid of field keys that are set as 'undefined'
      # due to 'constructor.config.excludeFields' attribute
      @serializerFieldsKeys = _.without @serializerFieldsKeys, undefined

      # if length of keys and serializer's values is not equal
      # throw an error
      if @serializerFieldsKeys.length isnt objectValues.length
        throw new Error "Encountered error while retrieving data from serializer!"
      return _.object @serializerFieldsKeys, objectValues

  _getMultipleObjects: (objects) =>
    result = []
    allObjectsPromises = []

    if not objects?
      objects = @data

    _.each @data, (val, key) =>
      allObjectsPromises.push @_getSingleObject(val)

    Promise.all(allObjectsPromises).then (values) ->
      return values

  # performs basic validation - checks if data passed to the serializer
  # has only those attributes that are about to be saved
  # reject any attribute which does not belong to given Model
  # or is set as readOnly field
  validate: ->
    return new Promise (resolve, reject) =>
      _.each @data, (val, key) =>
        if not (key in @serializerFieldsKeys)
          reject new TypeError "Parameter '#{key}' is not an attribute of " +
                                "#{@constructor.config.model.metadata.model} or is set as readOnly!"

      if @constructor.config.model.metadata.primaryKey of @data and not @instance
        reject new TypeError "Primary key was passed without an instance of the model!"
      resolve true

  # create new instance of the model and save it to the database
  create: ->
    @constructor.config.model.objects().create({ data: @data, toObject: true }).then (result) ->
      return result
    .catch (error) =>
      if @constructor.config.model.metadata.errorLogger?
        @constructor.config.model.metadata.errorLogger.error error
      throw error

  # update specified instance with data passed to the serializer
  update: ->
    if not @instance?
      throw new Error "There is no instance of #{@constructor.config.model.metadata.model}!"

    @instance.set @data
    @instance.save({ toObject: true }).then (result) ->
      return result
    .catch (error) =>
      if @constructor.config.model.metadata.errorLogger?
        @constructor.config.model.metadata.errorLogger.error error
      throw error

  # save the data to database - if the instance was passed we use the
  # .update() method, otherwise .create()
  save: ->
    @validate().then () =>
      if not @instance?
        @create().then (result) =>
          @data = result
          return result
      else
        @update().then (result) =>
          @data = result
          return result
    .catch (error) =>
      if @constructor.config.model.metadata.errorLogger?
        @constructor.config.model.metadata.errorLogger.error error
      throw error

  getData: =>
    # '@data' is required to retrieve model's instance values
    if not @data?
      throw new Error "You must first specify the data for #{@constructor.name} to retrieve values!"
    if @many
      @_getMultipleObjects().then (values) ->
        return values
    else
      @_getSingleObject().then (values) ->
        return values

  toString: ->
    "Instance of #{constructor.config.model.metadata.model}."


module.exports = ModelSerializer
