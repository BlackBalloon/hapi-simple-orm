'use strict'

Joi           = require 'joi'
BaseModel     = require './../model/baseModel'
_             = require 'underscore'
knexConf      = require process.cwd() + '/knexfile'
knex          = require('knex')(knexConf[process.env.NODE_ENV])
Promise       = require 'bluebird'


class BaseField

  @schemaErrorMessages:
    language:
      any:
        required: 'jest polem obowiązkowym'
        empty: 'nie może być puste'
      number:
        base: 'musi być liczbą'
        min: 'wartość musi być większa lub rowna {{limit}}'
        max: 'wartość musi być mniejsza lub rowna {{limit}}'

  # Class property which specifies validation methods for given attributes
  # @property [Object] description
  @validationMethods:
    schema: 'validateSchema'
    unique: 'validateUnique'

  # Class property which specifies acceptable attributes for the Field Class
  @acceptedParameters: [
    'required'        # defines if field value must be passed
    'unique'          # defines if the column value is unique
    'schema'          # defines the Joi validation schema
    'dbField'         # defines name of the column in table
    'abstract'        # defines if field should be saved to database
    'name'            # defines 'camelCase' readable name
    'primaryKey'      # defines if this field is a primary key
    'modelMeta'       # defines attributes of the Model instance
    'errorMessages'   # custom error messages for validation
    'set'             # method for explicit setting the field's value
    'get'             # method for explicit retrieve the field's value
  ]

  @_camelToSnakeCase: (val) ->
    snakeCase = (val.replace /\.?([A-Z])/g, (m, n) ->
      return '_' + n.toLowerCase()
    ).replace /^_/, ''
    snakeCase

  # Field constructor which obtains set of attributes
  # Checks, whether specified attributes are acceptable according to
  # 'acceptedParameters' Class property
  constructor: (@attributes...) ->
    @attributes = _.reduce @attributes, (memo, value) ->
      return value

    @attributes.errorMessages ?= {}

    # if current field has 'primaryKey' attribute set and it does not have
    # its 'name' specified, then we set the 'name' attribute to 'id'
    if @attributes.primaryKey and not _.has @attributes, 'name'
      @attributes['name'] = 'id'

    # if specify the 'dbField' attribute for current field basing on
    # it's 'name' attribute value - name is translated from camelCase to snake_case
    if not (@constructor.name is 'ForeignKey') and _.has @attributes, 'name'
      @attributes['dbField'] = @getDbField @attributes.name

    if not @acceptedParameters?
      @acceptedParameters = _.clone @constructor.acceptedParameters

    if not @validationMethods?
      @validationMethods = _.clone @constructor.validationMethods

    _.each @attributes, (val, key) =>
      if key not in @acceptedParameters
        throw new TypeError "Key '#{key}' is not accepted in field #{@attributes.name}!"

  # Instance method which validates specified attribute against it's Joi schema
  # @param [Any] value value of current field
  validateSchema: (value) =>
    Joi.validate value, @getSchema(), @constructor.schemaErrorMessages, (err, value) ->
      if err
        err.details[0].message

  # Instance method which validates if given attribute's value fulfills the
  # unique constraint
  # @param [Any] value value of current field
  # @param [Any] primaryKey named parameter, value of primary key of current model's instance
  # @param [Object] trx transaction object in case when multiple records will be impacted
  validateUnique: (value, { primaryKey, trx }) =>
    query = "SELECT EXISTS(SELECT 1 FROM #{@attributes.modelMeta.tableName}
              WHERE #{@attributes.dbField} = ?
              AND is_deleted = false"
    bindings = [value]

    # we omit current instance when finding unique fields
    # that is why we check the primary key if it is set
    if primaryKey?
      query += " AND #{@attributes.modelMeta.primaryKey} <> ?"
      bindings.push primaryKey
    query += ")"

    finalQuery = knex.raw(query, bindings)
    if trx?
      # apply transaction if was passed to the method
      finalQuery.transacting(trx)

    finalQuery.then (result) =>
      if result.rows[0].exists is true
        @attributes.errorMessages['unique'] || "#{@attributes.modelMeta.model} with this #{@attributes.name} (#{value}) already exists!"
    .catch (error) ->
      throw error

  # Instance method which performs validation depending on attributes of given field
  # It puts the results of the validation in array of Promises which is furtherly resolved
  # @param [Object] obj current model's instance
  # @param [Any] primaryKey current model's instance value of primary key
  # @param [Object] trx transaction object in case when multiple records will be impacted
  validate: (obj, { primaryKey, trx }) =>
    currentFieldValue = obj[@attributes.name]

    validationPromises = []
    _.each @attributes, (val, key) =>
      if key of @validationMethods
        validationPromises.push @[@validationMethods[key]](currentFieldValue, { primaryKey: primaryKey, trx: trx })

    Promise.all(validationPromises).then (validationPromisesResults) =>
      returnObj = {}

      err = _.find validationPromisesResults, (val) ->
        val?

      if err?
        returnObj[@attributes.name] = err
        return returnObj

  # get 'dbField' attribute for specified 'val'
  # translates 'camelCase' to 'snake_case'
  getDbField: (val) =>
    if not _.has @attributes, 'dbField'
      return @constructor._camelToSnakeCase val
    return @attributes.dbField

  # return Joi validation schema of current field
  getSchema: ->
    # throw error if the field does not have its schema specified
    if not _.has @attributes, 'schema'
      throw new Error "Field '#{@attributes.name}' does not have its schema!"

    schema = @attributes.schema
    # if field is set as 'required', then append '.required()' method
    # to current field's schema attribute
    if @attributes.required
      schema = schema.required()
    else
      # otherwise allow 'null' values
      schema = schema.allow(null)

    schema

module.exports = BaseField
