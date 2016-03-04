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

moduleKeywords = ['extended', 'included']

class BaseModel

  @include: (obj) ->
    @::['attributes'] = {}
    for key, value of obj when key not in moduleKeywords
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

  @objects: ->
    modulesDir = process.cwd() + '/api/'

    self = @
    dao = undefined
    daoFileName = self.metadata.model.substring(0, 1).toLowerCase() + self.metadata.model.substring(1)

    modules = fs.readdirSync modulesDir
    _.each modules, (moduleName) ->
      if not moduleName.startsWith '.'
        insideModule = fs.readdirSync modulesDir + moduleName
        if 'dao' in insideModule
          currentModule = fs.readdirSync modulesDir + moduleName + '/dao'
          if daoFileName + '.coffee' in currentModule
            dao = require modulesDir + moduleName + '/dao/' + daoFileName

    if dao?
      return new dao @
    else
      throw new Error "Model #{@metadata.model} does not have its DAO!"

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
    fields ?= _.keys @::attributes
    attributesWithSchema = _.pick @::attributes, (val, key) ->
      val.attributes.schema? and not (key of BaseModel::timestampAttributes) and key in fields

    _.mapObject attributesWithSchema, (val, key) ->
      schema = val.attributes.schema
      if val.attributes.required and not partial
        schema = schema.required()
      schema

  # constructor for Model
  # @param [Object] properties properties passed to create new Model instance
  constructor: (properties) ->
    manyToOneManager = ManyToOne.getManyToOneManager()
    manyToManyManager = ManyToMany.getManyToManyManager()

    _.each @attributes, (val, key) =>
      # setting value for 'dbField' attribute of every model's field
      # if it is not already present in the attributes
      if not _.has val.attributes, 'dbField'
        val.attributes.dbField = @constructor._camelToSnakeCase key, @attributes

      # setting value for 'name' attribute of every model's field
      # if it is not already present in the attributes
      if not _.has val.attributes, 'name'
        val.attributes.name = key

      # adding many to many related attributes to model's instance
      if val instanceof ManyToMany
        if not _.has val.attributes, 'throughFields'
          toModel = require val.attributes.toModel
          throughFields = []
          throughFields.push @constructor.metadata.singular + '_' + @constructor.metadata.primaryKey
          throughFields.push toModel.metadata.singular + '_' + toModel.metadata.primaryKey
          val.attributes.throughFields = throughFields
        @[key] = new manyToManyManager @, key, val

      # adding many to one related attributes to model's instance
      if val instanceof ManyToOne
        if not _.has val.attributes, 'referenceField'
          val.attributes.referenceField = @constructor.metadata.singular + '_' + @constructor.metadata.primaryKey
        @[key] = new manyToOneManager @, key, val

      # setting model's metadata as an attribute for every field
      val.attributes.modelMeta = @constructor.metadata

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
      else
        # we check if desired attribute is a foreign key
        # if it is, we need to return referenced Model's instance from DB
        if @attributes[key] instanceof ForeignKey and @[key]?
          lookup = {}
          lookup[@attributes[key].attributes.referenceField] = @[key]
          return @attributes[key].attributes.referenceModel.objects().get({ lookup: lookup, toObject: toObject })
            .then (result) ->
              return result
            .catch (error) ->
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
        @[key] = value
      else
        throw new TypeError "The '#{key}' field does not match any attribute of model #{@constructor.metadata.model}!"

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
      validationResultObject

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
        @constructor.objects().create({ payload: @_toDatabaseFields(), returning: returning, toObject: toObject }).then (res) ->
          return res
    .catch (error) ->
      throw error

  # Instance method used to delete current Model's instance
  # before deleting, the primary key of the instance must be checked
  # whether it exists - otherwise it means that instance wasnt saved to DB before
  delete: (whoDeleted) =>
    primaryKey = @constructor.metadata.primaryKey
    if @[primaryKey]?
      @constructor.objects().delete(@[primaryKey], whoDeleted).then (result) ->
        return result
      .catch (error) ->
        throw error
    else
      throw new Error "This #{@constructor.metadata.model} does not have primary key set!"


module.exports = BaseModel
