'use strict'

_           = require 'underscore'
Joi         = require 'joi'
Boom        = require 'boom'

BaseView    = require './baseView'

moduleKeywords = ['extended', 'included']


class ModelView extends BaseView

  @applyConfiguration: (obj) ->
    @::['config'] = {}
    for key, value of obj when key not in moduleKeywords
      @::['config'][key] = value

    obj.included?.apply(@)
    this

  # every 'ModelView' instance must obtain two params
  # @param [Object] server current server's instance
  # @param [Object] options options of current routing module
  constructor: (@server, @defaultOptions) ->
    # check if Model was specified in configuration attribute of the ModelView
    if @config? and not @config.model?
      throw new Error 'You must specify \'config.model\' class attribute of ModelView!'

    # server and options are required parameters
    if not @server?
      throw new Error 'You need to pass \'server\' instance to ModelView constructor!'

    # set default errorMessages attribute of configuration to empty object {}
    @config.errorMessages ?= {}
    # if the pluralName of Model was not specified, we simply append 's' to Model's name
    @config.pluralName ?= "#{@config.model.metadata.model}s"

    # if serializer was not specified in the configuration, set it to undefined
    @config.serializer ?= undefined

    super

  # extend defaultOptions with extraOptions
  # works recursively
  # @params [Object] defaultOptions defaultOptions of this ModelView
  # @params [Object] extraOptions additional options passed to route method
  __extendProperties: (defaultOptions, extraOptions) ->
    _.each extraOptions, (val, key) =>
      if val? and val.constructor? and val.constructor.name is 'Object' and not (_.isEmpty val)
        defaultOptions[key] = defaultOptions[key] or {}
        @__extendProperties defaultOptions[key], val
      else
        defaultOptions[key] = val
    defaultOptions

  # method which is used to extend (or overwrite) current routing object
  # @param [Object] routeObject current route object and it's attributes
  # @param [Object] options options that will be used to extend/overwrite existing routeObject
  _extendRouteObject: (routeObject, options) ->
    if options? and _.isObject(options)
      # separately assign method and path attributes of the route, if they were passed
      routeObject.method = options.method or routeObject.method
      routeObject.path = options.path or routeObject.path

    # if 'options.config' passed to routing method is undefined, set it to empty object
    options.config ?= {}

    if (rejectedOptions = _.difference _.keys(options.config), @constructor.getAcceptableRouteOptions()).length > 0
      throw new Error "Options #{rejectedOptions} are not accepted in route object!"

    # here we extend current route object with combination of 'defaultOptions' and 'options'
    # passed directly to the current routing method
    # result is full route configuration object
    # but first we need to create copy of 'defaultOptions' in order to omit reference problems
    defaultOptionsCopy = @__extendProperties {}, @defaultOptions
    @__extendProperties routeObject.config, (@__extendProperties(defaultOptionsCopy, _.clone(options.config)))

    # last check if the route object has config.handler method assigned
    if not (typeof routeObject.config.handler is 'function')
      # if not, throw an error
      throw new Error "The 'config.handler' attribute of route should be a function."

    # return extended/overwritten route object
    routeObject

  # GET - return single instance of Model
  # @param [Boolean] ifSerialize boolean which defines if result should be serialized
  # @param [Object] serializer serializer's Class to be used on the instance
  # @param [Object] options additional options which will extend/overwrite current route object
  get: (ifSerialize, serializer, options) =>
    if options? and not (_.isObject options)
      throw new Error "'options' parameter of routing method should be an object"

    options ?= { config: {} }

    routeObject =
      method: 'GET'
      path: "/#{@config.model.metadata.tableName}/{#{@config.model.metadata.primaryKey}}"

      config:
        description: "Return #{@config.model.metadata.model} with specified id"
        tags: @config.tags
        id: "return#{@config.model.metadata.model}"

        validate:
          params:
            "#{@config.model.metadata.primaryKey}": @config.model::attributes[@config.model.metadata.primaryKey].attributes.schema.required()
          query:
            fields: Joi.array().items(Joi.string()).single()

        plugins:
          'hapi-swagger':
            responses:
              '200':
                'description': 'Success'
                'schema': Joi.object(@config.model.getSchema()).label(@config.model.metadata.model)
              '400':
                'description': 'Bad request'
              '401':
                'description': 'Unauthorized'
              '404':
                'description': 'Not found'

        handler: (request, reply) =>
          returning = undefined
          if request.query.fields?
            try
              returning = _.map request.query.fields, (field) =>
                if field not of @config.model::attributes
                  throw new Error "Field '#{field}' does not match any attribute of model #{@config.model.metadata.model}"

                if not @config.allowTimestampAttributes and field of @config.model::timestampAttributes
                  throw new Error "Field '#{field}' does not match any attribute of model #{@config.model.metadata.model}"

                "#{@config.model::attributes[field].getDbField(field)} AS #{field}"
            catch error
              return reply Boom.badRequest(error)

          @config.model.objects().getById({ pk: request.params.id, returning: returning }).then (result) =>
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
              return reply Boom.notFound(@config.errorMessages['notFound'] or "#{@config.model.metadata.model} does not exist")
          .catch (error) ->
            reply Boom.badRequest error

    if options? and _.isObject(options)
      @_extendRouteObject routeObject, options

    routeObject

  # GET - return all instances of current Model
  # @param [Boolean] ifSerialize boolean which defines if result should be serialized
  # @param [Object] serializer serializer's Class to be used on the instances
  # @param [Object] options additional options which will extend/overwrite current route object
  list: (ifSerialize, serializer, options) =>
    if options? and not (_.isObject options)
      throw new Error "'options' parameter of routing method should be an object"

    options ?= { config: {} }

    routeObject =
      method: 'GET'
      path: "/#{@config.model.metadata.tableName}"

      config:
        description: "Return all #{@config.pluralName}"
        tags: @config.tags
        id: "returnAll#{@config.pluralName}"

        validate:
          query:
            fields: Joi.array().items(Joi.string()).single()

        plugins:
          'hapi-swagger':
            responses:
              '200':
                'description': 'Success'
                'schema': Joi.object({ items: Joi.array().items(@config.model.getSchema()) }).label(@config.pluralName)
              '400':
                'description': 'Bad request'
              '401':
                'description': 'Unauthorized'

        handler: (request, reply) =>
          returning = undefined
          if request.query.fields?
            try
              returning = _.map request.query.fields, (field) =>
                if field not of @config.model::attributes
                  throw new Error "Field '#{field}' does not match any attribute of model #{@config.model.metadata.model}"

                if not @config.allowTimestampAttributes and field of @config.model::timestampAttributes
                  throw new Error "Field '#{field}' does not match any attribute of model #{@config.model.metadata.model}"

                "#{@config.model::attributes[field].getDbField(field)} AS #{field}"
            catch error
              return reply Boom.badRequest(error)

          @config.model.objects().all({ returning: returning }).then (objects) =>
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

    if options? and _.isObject(options)
      @_extendRouteObject routeObject, options

    routeObject

  # POST - create new instance of current Model
  # @param [Boolean] ifSerialize boolean which defines if result should be serialized
  # @param [Object] serializer serializer's Class to be used on created instance
  # @param [Object] options additional options which will extend/overwrite current route object
  create: (ifSerialize, serializer, options) =>
    if options? and not (_.isObject options)
      throw new Error "'options' parameter of routing method should be an object"

    options ?= { config: {} }

    routeObject =
      method: 'POST'
      path: "/#{@config.model.metadata.tableName}"

      config:
        description: "Create new #{@config.model.metadata.model}"
        tags: @config.tags
        id: "addNew#{@config.model.metadata.model}"

        validate:
          payload: @config.model.getSchema()

        plugins:
          'hapi-swagger':
            responses:
              '201':
                'description': 'Created'
                'schema': Joi.object(@config.model.getSchema()).label(@config.model.metadata.model)
              '400':
                'description': 'Bad request/validation error'
              '401':
                'description': 'Unauthorized'

        handler: (request, reply) =>
          if request.auth.credentials?
            _.extend request.payload, { whoCreated: request.auth.credentials.user.id }

          @config.model.objects().create({ data: request.payload }).then (result) =>
            if @config.createLogger?
              @config.createLogger.info "#{@config.model.metadata.model} created: #{result}"
              
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
            reply Boom.badRequest(error)

    if options? and _.isObject(options)
      @_extendRouteObject routeObject, options

    routeObject

  # PUT - update specified instance of current Model
  # @param [Boolean] ifSerialize boolean which defines if result should be serialized
  # @param [Object] serializer serializer's Class to be used on updated instance
  # @param [Object] options additional options which will extend/overwrite current route object
  update: (ifSerialize, serializer, options) =>
    if options? and not (_.isObject options)
      throw new Error "'options' parameter of routing method should be an object"

    options ?= { config: {} }

    routeObject =
      method: 'PUT'
      path: "/#{@config.model.metadata.tableName}/{#{@config.model.metadata.primaryKey}}"

      config:
        description: "Update #{@config.model.metadata.model} with specified id"
        tags: @config.tags
        id: "update#{@config.model.metadata.model}"

        validate:
          params:
            "#{@config.model.metadata.primaryKey}": @config.model::attributes[@config.model.metadata.primaryKey].attributes.schema.required()
          payload: @config.model.getSchema()

        plugins:
          'hapi-swagger':
            responses:
              '200':
                'description': 'Updated'
                'schema': Joi.object(@config.model.getSchema()).label(@config.model.metadata.model)
              '400':
                'description': 'Bad request/validation error'
              '401':
                'description': 'Unauthorized'
              '404':
                'description': 'Not found'

        handler: (request, reply) =>
          @config.model.objects().getById({ pk: request.params.id }).then (instance) =>
            if instance?
              instance.set request.payload
              instance.save().then (result) =>
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
                # TODO: add custom ValidationError class in order to distinguish the reply message (Boom or simply error)
                return reply(Boom.badRequest(error))
            else
              return reply Boom.notFound @config.errorMessages.notFound || "#{@config.model.metadata.model} does not exist"

    if options? and _.isObject(options)
      @_extendRouteObject routeObject, options

    routeObject

  # PATCH - perform partial update of specified instance of current Model
  # @param [Boolean] ifSerialize boolean which defines if result should be serialized
  # @param [Object] serializer serializer's Class to be used on updated instance
  # @param [Object] options additional options which will extend/overwrite current route object
  partialUpdate: (ifSerialize, serializer, options) =>
    routeObject = @update ifSerialize, serializer, options

    # it is necessary to change method to PATCH and both description and id of this route method
    # to prevent situation in which it overlaps with '.update()' method
    routeObject.method = 'PATCH'
    routeObject.config.description = "Partial update of #{@config.model.metadata.model}"
    routeObject.config.id = "partialUpdate#{@config.model.metadata.model}"

    # we set the 'partial' parameter of 'getSchema()' method to true
    # in order to return the schema without 'required' attribute for required fields
    # because PATCH allows to update only part of object (model's instance)
    routeObject.config.validate.payload = @config.model.getSchema(undefined, true)

    routeObject

  # DELETE - delete specified instance of current Model, returns 1 if DELETE was successfull
  # @param [Object] options additional options which will extend/overwrite current route object
  delete: (options) =>
    if options? and not (_.isObject options)
      throw new Error "'options' parameter of routing method should be an object"

    options ?= { config: {} }

    routeObject =
      method: 'DELETE'
      path: "/#{@config.model.metadata.tableName}/{#{@config.model.metadata.primaryKey}}"

      config:
        description: "Delete #{@config.model.metadata.model} with specified id"
        tags: @config.tags
        id: "delete#{@config.model.metadata.model}"

        validate:
          params:
            "#{@config.model.metadata.primaryKey}": @config.model::attributes[@config.model.metadata.primaryKey].attributes.schema.required()

        plugins:
          'hapi-swagger':
            responses:
              '200':
                'description': 'Deleted'
              '400':
                'description': 'Bad request'
              '401':
                'description': 'Unauthorized'
              '404':
                'description': 'Not found'

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

    if options? and _.isObject(options)
      @_extendRouteObject routeObject, options

    routeObject


module.exports = ModelView
