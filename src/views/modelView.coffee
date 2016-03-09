'use strict'

_           = require 'underscore'
Joi         = require 'joi'
Boom        = require 'boom'

BaseView    = require './baseView'

optionsAllowedAttributes = [
  'security'
  'headersValidation'
  'validate'
]


class ModelView extends BaseView

  # every 'ModelView' instance must obtain two params
  # @param [Object] server current server's instance
  # @param [Object] options options of current routing module
  constructor: (@server, @options) ->
    # check if Model was specified in configuration attribute of the ModelView
    if not @config.model?
      throw new Error 'You must specify \'config.model\' attribute of ModelView!'

    # server and options are required parameters
    if not @server? or not @options?
      throw new Error 'You need to pass \'server\' and \'options\' to ModelView constructor!'

    # set default errorMessages attribute of configuration to empty object {}
    @config.errorMessages ?= {}
    # if the pluralName of Model was not specified, we simply append 's' to Model's name
    @config.pluralName ?= "#{@config.model.metadata.model}s"

    # if serializer was not specified in the configuration, set it to undefined
    @config.serializer ?= undefined

    # assignValue is used in 'pre' attribute of route object
    # translates UpperCase to camelCase e.g. AccountCategory will become accountCategory
    @config.assignValue = @config.model.metadata.model.substr(0, 1).toLowerCase() + @config.model.metadata.model.substr(1)

    _.each @options, (val, key) ->
      if key not in optionsAllowedAttributes
        throw new Error "Attribute '#{key}' is not accepted in 'options' parameter!"

    ###
    options obj:
    {
      security: {
        hsts: true
        xframe:
          rule: 'sameorigin'
        xss: true
        noOpen: true
        noSniff: true
      }
      headersValidation: Joi.object()
      validate: {
        failAction: (request, reply, source, error)
        options: {
          abortEarly: boolean
          stripUnknown: boolean
        }
      }
    }
    ###

    # if options was not passed, set it to empty object
    @options ?= {}

    # security headers
    @options.security ?= undefined
    # validation of request headers e.g. 'authorization' header
    @options.headersValidation ?= undefined
    # validate options - failAction and other options
    # failAction must be a method with definition like (request, reply, source, error)
    # and needs to finish execution by calling '.reply()'
    @options.validate ?= {}

    # validation of path parameters e.g. id
    @paramsValidation = {}
    primaryKey = @config.model.metadata.primaryKey
    @paramsValidation[primaryKey] = @config.model::attributes[primaryKey].attributes.schema.required()

  get: (ifSerialize, serializer) =>
    {
      method: 'GET'
      path: "/#{@config.model.metadata.tableName}/{#{@config.model.metadata.primaryKey}}"

      config:
        description: "Return #{@config.model.metadata.model} with specified id"
        tags: @config.tags
        id: "return#{@config.model.metadata.model}"

        security: @options.security
        cors: true

        validate:
          headers: @options.headersValidation
          params: @paramsValidation

        plugins:
          'hapi-swagger': @server.methods.swaggerRouteResponse('get', false)

        handler: (request, reply) =>
          @config.model.objects().getById({ val: request.params.id }).then (result) =>
            if result?
              if ifSerialize
                serializerClass = if serializer then serializer else @config.serializer
                if not serializerClass?
                  throw new Error "There is no serializer specified for #{@constructor.name}"

                serializerInstance = new serializerClass data: result
                serializerInstance.getData().then (serializerData) ->
                  return reply serializerData
              else
                return reply result
            else
              return reply Boom.notFound(@config.errorMessages['notFound'] || "#{@config.model.metadata.model} does not exist")
          .catch (error) ->
            reply Boom.badRequest error
    }

  list: (ifSerialize, serializer) ->
    {
      method: 'GET'
      path: "/#{@config.model.metadata.tableName}"

      config:
        description: "Return all #{@config.pluralName}"
        tags: @config.tags
        id: "returnAll#{@config.pluralName}"

        security: @options.security
        cors: true

        validate:
          headers: @options.headersValidation

        plugins:
          'hapi-swagger': @server.methods.swaggerRouteResponse('get', true)

        handler: (request, reply) =>
          @config.model.objects().all().then (objects) =>
            if ifSerialize
              serializerClass = if serializer then serializer else @config.serializer
              if not serializerClass?
                throw new Error "There is no serializer specified for #{@constructor.name}"

              serializerInstance = new serializerClass data: objects, many: true
              serializerInstance.getData().then (serializerData) ->
                reply serializerData
            else
              reply objects
          .catch (error) ->
            reply Boom.badRequest error
    }

  create: (ifSerialize, serializer) =>
    {
      method: 'POST'
      path: "/#{@config.model.metadata.tableName}"

      config:
        description: "Create new #{@config.model.metadata.model}"
        tags: @config.tags
        id: "addNew#{@config.model.metadata.model}"

        security: @options.security
        cors: true

        validate:
          headers: @options.headersValidation
          payload: @config.model.getSchema()
          failAction: @options.validate.failAction
          options: @options.validate.options

        plugins:
          'hapi-swagger': @options.headersValidation

        handler: (request, reply) =>
          if request.auth.credentials?
            _.extend request.payload, { whoCreated: request.auth.credentials.user.id }

          @config.model.objects().create({ payload: request.payload, direct: true }).then (result) =>
            if ifSerialize
              serializerClass = if serializer then serializer else @config.serializer
              if not serializerClass?
                throw new Error "There is no serializer specified for #{@constructor.name}"

              serializerInstance = new serializerClass data: result
              serializerInstance.getData().then (serializerData) ->
                reply(serializerData).code(201)
            else
              publishObj =
                action: 'add'
                obj: result
              @server.publish "/#{@config.model.metadata.tableName}", publishObj
              reply(result).code(201)
          .catch (error) ->
            reply(error).code(400)
    }

  update: (ifSerialize, serializer) =>
    {
      method: 'PUT'
      path: "/#{@config.model.metadata.tableName}/{#{@config.model.metadata.primaryKey}}"

      config:
        description: "Update #{@config.model.metadata.model} with specified id"
        tags: @config.tags
        id: "update#{@config.model.metadata.model}"

        security: @options.security
        cors: true

        validate:
          headers: @options.headersValidation
          params: @paramsValidation
          payload: @config.model.getSchema()
          failAction: @options.validate.failAction
          options: @options.validate.options

        plugins:
          'hapi-swagger': @server.methods.swaggerRouteResponse('put')

        pre: [
          {
            assign: @config.assignValue
            method: (request, reply) =>
              @config.model.objects().getById({ val: request.params.id }).then (result) ->
                reply result
          }
        ]

        handler: (request, reply) =>
          if request.pre[@config.assignValue]?
            request.pre[@config.assignValue].set request.payload
            request.pre[@config.assignValue].save().then (result) =>

              if ifSerialize
                serializerClass = if serializer then serializer else @config.serializer
                if not serializerClass?
                  throw new Error "There is no serializer specified for #{@constructor.name}"

                serializerInstance = new serializerClass data: result
                serializerInstance.getData().then (serializerData) ->
                  reply serializerData
              else
                reply result
            .catch (error) ->
              return reply(error).code(400)
          else
            return reply Boom.notFound @config.errorMessages.notFound || "#{@config.model.metadata.model} does not exist"
    }

  partialUpdate: (ifSerialize, serializer) ->
    obj = @update ifSerialize, serializer

    obj.config.validate.payload = @config.model.getSchema(undefined, true)

    obj

  delete: =>
    {
      method: 'DELETE'
      path: "/#{@config.model.metadata.tableName}/{#{@config.model.metadata.primaryKey}}"

      config:
        description: "Delete #{@config.model.metadata.model} with specified id"
        tags: @config.tags
        id: "delete#{@config.model.metadata.model}"

        security: @options.security
        cors: true

        validate:
          headers: @options.headersValidation
          params: @paramsValidation

        plugins:
          'hapi-swagger': @server.methods.swaggerRouteResponse('delete')

        handler: (request, reply) =>
          whoDeleted = if request.auth.credentials? then request.auth.credentials.user.id else undefined

          @config.model.objects().delete(request.params.id, whoDeleted).then (result) =>
            if result is 1
              publishObj =
                action: 'delete'
                id: request.params.id
              @server.publish "/#{@config.model.metadata.tableName}", publishObj
              return reply result
            return reply Boom.notFound @config.errorMessages.notFound || "#{@config.model.metadata.model} does not exist!"
          .catch (error) ->
            reply Boom.badRequest error
    }


module.exports = ModelView
