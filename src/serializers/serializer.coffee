'use strict'

_               = require 'underscore'
Promise         = require 'bluebird'

ForeignKey      = require './../fields/foreignKey'


class Serializer

  @applyConfiguration: (obj) ->
    @::['config'] = {}
    for key, value of obj when key not in moduleKeywords
      @::['config'][key] = value

    obj.included?.apply(@)
    this

  constructor: (@attributes...) ->
    # check if all attributes passed to the constructor are accepted by this serializer
    _.each @attributes[0], (val, key) =>
      if not (key in @constructor.acceptedParameters)
        # if not, throw an error
        throw new TypeError "Parameter '#{key}' is not accepted in #{@constructor.name}"

    # if no 'readOnlyFields' were specified, we set it's value to empty array []
    @constructor.config.readOnlyFields ?= []
    # if no 'fields' were specified, we set it's value to empty array []
    # in such a case, all model's fields will be returned from the serializer
    # (unless 'fields' are passed directly to the constructor)
    @constructor.config.fields ?= []
    # if no 'excludeFields' were specified, we set it's value to empty array []
    @constructor.config.excludeFields ?= []

    # if 'fields' attribute was passed to the serializer, we overwrite the 'constructor.config.fields'
    # value with those passed to the constructor
    if @attributes[0]? and @attributes[0].fields? and @attributes[0].fields.length > 0
      @constructor.config.fields = _.clone @attributes[0].fields

    # no value was specified in the 'fields' and 'readOnlyFields' attributes of the serializer
    # we assume that all Model's fields should be returned by this serializer
    if @constructor.config.fields.length is 0 and @constructor.config.readOnlyFields.length is 0
      @serializerFields = _.keys @constructor.config.model::attributes
    else
      @serializerFields = _.union @constructor.config.fields, @constructor.config.readOnlyFields

    # final check whether serializer's fields are acceptable
    _.each @serializerFields, (val, key) =>
      # here we check if field is passed in form of string e.g. 'company'
      if typeof val is 'string' and not @constructor.config.model::attributes[val]?
        throw new Error "Key '#{val}' does not match any attribute of model #{@constructor.config.model.metadata.model}"

    # here we get all field names from serializer specified fields
    # we perform a check whether current field was not set as 'excluded'
    @serializerFieldsKeys = _.map @serializerFields, (val, key) =>
      currentKey = if val.constructor.name is 'String' then val else (_.keys val)[0]
      if currentKey not in @constructor.config.excludeFields
        return currentKey

    # get rid of 'undefined' values from array of keys
    @serializerFieldsKeys = _.without @serializerFieldsKeys, undefined
    # if finnaly length of keys array is 0, throw an error with a message
    # that serializer does not have any fields specified
    if @serializerFieldsKeys.length is 0
      throw new Error "#{@constructor.name} does not have any field specified!"

  getData: ->
    return new Promise (resolve, reject) ->
      resolve @data

  setData: (data) ->
    @data = data

module.exports = Serializer
