'use strict'

_             = require 'underscore'
Promise       = require 'bluebird'

Serializer    = require './serializer'


class FieldRelatedSerializer extends Serializer

  @acceptedParameters: [
    'many'
    'field'
    'readOnly'
    'model'
  ]

  # field types that will be rejectet - relations only
  @rejectedFieldTypes: {
    'ForeignKey': 'foreign key'
    'ManyToMany': 'm2m relation'
    'ManyToOne': 'm2o relation'
  }

  constructor: ({ @many, @field, @readOnly, @model } = {}) ->
    # field and model are required attributes
    if not @field? or not @model?
      throw new Error "#{@constructor.name} requires the 'field' and 'model' attributes!"

    # we check if specified field belongs to attributes of given model
    if not @field of @model::attributes
      throw new TypeError "Related object does not have attribute #{@field}"

    # here we check if specified field is a relation of given model
    # if the field is foreign key/m2m/m2o, we throw an error with message
    fieldClassName = @model::attributes[@field].constructor.name
    if fieldClassName of @constructor.rejectedFieldTypes
      throw new TypeError "Field from #{@constructor.name} can't be a #{@constructor.rejectedFieldTypes[fieldClassName]}"

    # check if all arguments passed to the constructor are accepted
    # in 'FieldRelatedSerializer'
    _.each arguments[0], (val, key) =>
      if not (key in @constructor.acceptedParameters)
        throw new TypeError "Parameter '#{key} is not accepted in #{@constructor.name}'"

  getData: ->
    return new Promise (resolve, reject) =>
      if @many
        resolve _.map @data, (val) =>
          val.get @field
      else
        if not @field of @data.attributes
          reject new TypeError "Related object does not have attribute #{@field}"
        resolve @data.get @field


module.exports = FieldRelatedSerializer
