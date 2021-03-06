'use strict'

Joi         = require 'joi'
_           = require 'underscore'
fs          = require 'fs'
knexConf    = require process.cwd() + '/knexfile'
knex        = require('knex')(knexConf[process.env.NODE_ENV])
Promise     = require 'bluebird'

ForeignKey  = require '../fields/foreignKey'
BaseField   = require '../fields/baseField'
ManyToMany  = require '../fields/manyToMany'
ManyToOne   = require '../fields/manyToOne'

BaseDAO     = require './../dao/baseDao'

moduleKeywords = ['extended', 'included']

acceptableMetadataAttributes = [
  'model'       # name of current Model
  'singular'    # singular name of the database table e.g. account_category
  'tableName'   # name of table in database
  'primaryKey'  # pk of table
  'timestamps'  # boolean defining if timestamp fields should be included
  'dao'         # DAO object of current Model
  'errorLogger' # if you want to log errors, pass the log4js error logger object
]

class BaseModel

  @injectDao: (obj) ->
    @objects = ->
      return obj

    obj.extended?.apply(@)
    this

  @extend: (obj) ->
    # add 'metadata' attribute to the model and apply parameters to it
    @metadata = {}
    for key, value of obj when key not in moduleKeywords
      if key not in acceptableMetadataAttributes
        throw new Error "The '#{key}' attribute in Model's metadata is not acceptable.\n
                        Acceptable attributes are #{acceptableMetadataAttributes}."
      @metadata[key] = value

    # default 'model' value is name of the Class e.g. AccountCategory
    if not @metadata.model?
      @metadata.model = @name

    # collection name used in case of MongoDB logging, translates e.g. AccountCategory to accountCategory
    @metadata.collectionName = @name.substring(0, 1).toLowerCase() + @name.substring(1)

    # default 'singular' value is snake_case of Class e.g. account_category
    if not @metadata.singular?
      @metadata.singular = @_camelToSnakeCase @name

    # default 'tableName' is snake_case of Class + 's' e.g. users (User)
    if not @metadata.tableName?
      @metadata.tableName = @_camelToSnakeCase(@name) + 's'

    # default 'primaryKey' is set to 'id'
    if not @metadata.primaryKey?
      @metadata.primaryKey = 'id'

    # if 'timestamps' attribute was not passed, we set its default val to true
    if not @metadata.timestamps?
      @metadata.timestamps = true

    # default 'dao' is set to BaseDAO if not passed
    if not @metadata.dao?
      @metadata.dao = BaseDAO

    dao = @metadata.dao
    @objects = =>
      return new @metadata.dao @

    obj.extended?.apply(@)
    this

  @include: (obj) ->
    @::['attributes'] = {}
    @::['fields'] = []
    for key, value of obj when key not in moduleKeywords
      @::['fields'].push key
      @::['attributes'][key] = value

    _.extend @::['attributes'], @::timestampAttributes
    obj.included?.apply(@)
    this

  timestampAttributes:
    createdAt: new BaseField(
      schema: Joi.date().format('YYYY-MM-DD HH:mm:ss')
      name: 'createdAt'
    )

    whoCreated: new BaseField(
      schema: Joi.number().integer().positive()
      name: 'whoCreated'
      dbField: 'who_created_id'
    )

    deletedAt: new BaseField(
      schema: Joi.date().format('YYYY-MM-DD HH:mm:ss')
      name: 'deletedAt'
    )

    whoDeleted: new BaseField(
      schema: Joi.number().integer().positive()
      name: 'whoDeleted'
      dbField: 'who_deleted_id'
    )

    isDeleted: new BaseField(
      schema: Joi.boolean()
      name: 'isDeleted'
    )

  # Class Method used to convert passed parameter to 'camelCase'
  # @param [String] string value to be translated to camelCase
  # @param [Object] attributes current model's attributes used to define foreign keys
  @_snakeToCamelCase: (string, attributes) ->
    camelCase = string.replace /(_\w)/g, (m) ->
      return m[1].toUpperCase()

    if attributes?
      # if passed attribute is a foreign key in given model
      # then we need to cut the 'Id' part of resulting string
      if attributes[camelCase] instanceof ForeignKey
        camelCase.slice 0, -2
    camelCase

  # Class Method used to convert passed parameter to 'snake_case'
  # @param [String] string value to be translated to snake_case
  # @param [Object] attributes current model's attributes used to define foreign keys
  @_camelToSnakeCase: (string, attributes) ->
    snakeCase = (string.replace /\.?([A-Z])/g, (m, n) ->
      return '_' + n.toLowerCase()
    ).replace /^_/, ''

    if attributes?
      # if passed attribute is a foreign key of given model
      # then we need to add the '_id' part to resulting string
      if attributes[string] instanceof ForeignKey
        snakeCase += '_id'
    snakeCase

  # simple Class Method which returns object containing all keys of the Model
  # and 'schema' (Joi validation objects) as value for every key
  @getSchema: (fields, partial) ->
    attributesWithSchema = _.pick @::attributes, (val, key) =>
      val.attributes.schema? and not (key of BaseModel::timestampAttributes) and key in @::fields

    _.mapObject attributesWithSchema, (val, key) ->
      schema = val.attributes.schema
      if val.attributes.required and not partial
        schema = schema.required()
      else if not val.attributes.required
        schema = schema.allow(null)
      schema

  # constructor for Model
  # @param [Object] properties properties passed to create new Model instance
  constructor: (properties) ->
    manyToOneManager = ManyToOne.getManyToOneManager()
    manyToManyManager = ManyToMany.getManyToManyManager()

    _.each @attributes, (val, key) =>
      # adding many to many related attributes to model's instance
      if val instanceof ManyToMany
        if not (_.has val.attributes, 'throughFields')
          toModel = require val.attributes.toModel
          throughFields = []
          throughFields.push @constructor.metadata.singular + '_' + @constructor.metadata.primaryKey
          throughFields.push toModel.metadata.singular + '_' + toModel.metadata.primaryKey
          val.attributes.throughFields = throughFields
        @[key] = new manyToManyManager @, key, val

      # adding many to one related attributes to model's instance
      if val instanceof ManyToOne
        if not (_.has val.attributes, 'referenceField')
          val.attributes.referenceField = @constructor.metadata.singular + '_' + @constructor.metadata.primaryKey
        @[key] = new manyToOneManager @, key, val

    try
      @set properties
    catch error
      throw error

  # translate JSON object to database format (camelCase to snake_case)
  # operates on Model instance, applies setter on every field if it was set
  _toDatabaseFields: =>
    databaseObject = {}
    for key, value of @attributes
      # we check if value for specified key was set
      # we also check if the attribute has 'dbField' assigned
      # otherwise it is a virtual attribute which is not saved in the DB
      if @[key] isnt undefined and value.attributes.dbField and not value.attributes.abstract
        # apply all setters
        databaseObject[value.attributes.dbField] = if value.attributes.set? then value.attributes.set @ else @[key]
    databaseObject

  # retrieve Model instance's value for specified key
  # @param [String] key returns value of field of model's instance for specified key
  # @param [Boolean] toObject boolean value which defines if related FK should be returned as model instance
  get: (key, toObject) =>
    if key of @attributes
      if @attributes[key].attributes.get?
        return @attributes[key].attributes.get @
      # we check if desired attribute is a foreign key
      # if it is, we need to return referenced Model's instance from DB
      if @attributes[key] instanceof ForeignKey and @[key]?
        lookup = {}
        lookup[@attributes[key].attributes.referenceField] = @[key]
        return @attributes[key].attributes.referenceModel.objects().get({ lookup: lookup, toObject: toObject })
          .then (result) ->
            return result
          .catch (error) =>
            if @constructor.metadata.errorLogger?
              @constructor.metadata.errorLogger.error error
            throw error
      else
        # otherwise we just return value for specified key
        return @[key]
    else
      throw new TypeError "The '#{key}' field does not match any attribute of model #{@constructor.metadata.model}!"

  # set specified keys of the Model instance with given values
  # @param [Object] properties object containing properties to be set e.g. { name: 'my name' }
  set: (properties) =>
    _.each properties, (value, key) =>
      if key of @attributes
        if @attributes[key] instanceof ForeignKey
          if value instanceof BaseModel
            if value instanceof @attributes[key].attributes.referenceModel
              @[key] = value.get(@attributes[key].attributes.referenceModel.metadata.primaryKey)
            else
              throw new TypeError "Value for '#{key}' of #{@constructor.metadata.model} should be FK value or instance of #{@attributes[key].attributes.referenceModel.metadata.model}!"
          else
            @[key] = value
        else
          @[key] = value
      else
        throw new TypeError "The '#{key}' field does not match any attribute of model #{@constructor.metadata.model}!"
    @

  # translate Object retrieved from database to JSON readable format
  # initially it would return all fields from Model, however it is able
  # to pass 'attributes' param, which defines which fields should be returned
  # this method operations on Model instance
  # @param [Array] attributes array of attributes to be returned from model
  toJSON: ({ attributes } = {}) =>
    attributes ?= _.keys @attributes

    jsonObject = {}
    _.each attributes, (key, val) =>
      if not (@attributes[key] instanceof ManyToMany) and not (@attributes[key] instanceof ManyToOne)
        if @attributes[key] instanceof ForeignKey
          jsonObject[key] = @[key]
        else
          jsonObject[key] = if @get(key) isnt undefined then @get(key)
    jsonObject

  # method validating every attribute of model's instance
  # @param [Object] trx - transaction object in case when multiple records will be impacted
  validate: ({ trx } = {}) =>
    promises = []
    _.each @attributes, (value, key) =>
      if not value.attributes.abstract?
        promises.push value.validate @, { primaryKey: @[@constructor.metadata.primaryKey], trx: trx }

    Promise.all(promises).then (values) ->
      validationResultObject = {}
      # get rid of elements that are 'undefined'
      # change array format of the validation result to object
      _.each (_.compact values), (val, key) ->
        _.extend validationResultObject, val
      finalValidationError = {}
      if not (_.isEmpty(validationResultObject))
        _.extend finalValidationError, { error: 'ValidationError', fields: validationResultObject }
      finalValidationError

  # Instance method which performs Model save to the database
  # First, the validation is performed - if it passes, then model is saved
  save: ({ returning, toObject } = {}) =>
    @validate().then (validationResult) =>
      # we check if 'validationResult' is an empty object
      # if it is not, it means that validation returned errors
      if not (_.isEmpty validationResult)
        throw validationResult

      # we check if the instance has primary key set
      # if it does, then method should be 'update'
      # otherwise it is 'create'
      if @[@constructor.metadata.primaryKey]?
        @constructor.objects().update({ obj: @, returning: returning, toObject: toObject }).then (res) ->
          return res
      else
        @constructor.objects().create({ data: @_toDatabaseFields(), returning: returning, toObject: toObject, direct: false }).then (res) ->
          return res
    .catch (error) =>
      if @constructor.metadata.errorLogger?
        @constructor.metadata.errorLogger.error error
      throw error

  # Instance method used to delete current Model's instance
  # before deleting, the primary key of the instance must be checked
  # whether it exists - otherwise it means that instance wasnt saved to DB before
  delete: (whoDeleted) =>
    primaryKey = @constructor.metadata.primaryKey
    if @[primaryKey]?
      @constructor.objects().delete(@[primaryKey], whoDeleted).then (result) ->
        return result
      .catch (error) =>
        if @constructor.metadata.errorLogger?
          @constructor.metadata.errorLogger.error error
        throw error
    else
      throw new Error "This #{@constructor.metadata.model} does not have primary key set!"


module.exports = BaseModel
