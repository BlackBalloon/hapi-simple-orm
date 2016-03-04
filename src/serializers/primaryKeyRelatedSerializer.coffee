'use strict'

_             = require 'underscore'
Promise       = require 'bluebird'

Serializer    = require './serializer'


class PrimaryKeyRelatedSerializer extends Serializer

  @acceptedParameters: [
    'many'
  ]

  constructor: ({ @many } = {}) ->
    _.each arguments[0], (val, key) =>
      if not (key in @constructor.acceptedParameters)
        throw new TypeError "Parameter '#{key} is not accepted in #{@constructor.name}'"

  getData: ->
    return new Promise (resolve, reject) =>
      if @many
        resolve _.map @data, (val) ->
          if val[val.constructor.metadata.primaryKey]?
            return val[val.constructor.metadata.primaryKey]
          reject new TypeError "Related field of #{val.constructor.metadata.model} does not have primary key set!"
      else
        if @data[@data.constructor.metadata.primaryKey]?
          resolve @data[@data.constructor.metadata.primaryKey]
        reject new TypeError "Related field of #{val.constructor.metadata.model} does not have primary key set!"


module.exports = PrimaryKeyRelatedSerializer
