'use strict'

_       = require 'underscore'

acceptableMethods = [
  'get'
  'put'
  'patch'
  'post'
  'delete'
]

acceptableRouteOptions = [
  'app', 'auth', 'bind', 'cache', 'cors', 'ext', 'files', 'handler', 'id', 'isInternal',
  'json', 'jsonp', 'payload', 'plugins', 'pre', 'response', 'security', 'state', 'validate',
  'timeout', 'description', 'notes', 'tags'
]

acceptableDefaultOptions = [
  'app', 'auth', 'bind', 'cache', 'cors', 'files', 'json', 'jsonp', 'plugins',
  'pre', 'security', 'state', 'validate', 'timeout', 'tags'
]


class BaseView

  @_decoratorMethodBody: (self, method, args, key, value) ->
    obj = {}
    obj[key] = value

    if _.isEmpty args
      method.apply self, [obj]
    else
      args['0'] = _.extend args['0'], obj
      method.apply self, args

  # decorator for every routing method
  # defines http verb (method) of current method
  # 'methodName' should be one of ['get', 'put', 'post', 'delete', 'patch']
  @method: (methodName) -> (method) -> ->
    if not methodName?
      throw new Error "It is necessary to specify 'methodName' attribute for the view!"
    if methodName? and not (methodName.toLowerCase() in acceptableMethods)
      throw new Error "Method name for route should be one of #{acceptableMethods}!"

    @constructor._decoratorMethodBody @, method, arguments, 'method', methodName

  # routing method decorator defining path for the request
  # e.g. '/products'
  @path: (path) -> (method) -> ->
    if not path?
      throw new Error "It is necessary to specify 'path' attribute for the view!"
    if path? typeof path isnt 'string'
      throw new Error "'path' of the route should be a string"

    @constructor._decoratorMethodBody @, method, arguments, 'path', path

  # routing method decorator specifying id parameter of this route
  @id: (id) -> (method) -> ->
    if id? and typeof id isnt 'string'
      throw new Error "'id' of the route should be a string"

    @constructor._decoratorMethodBody @, method, arguments, 'id', id

  # routing method decorator specifying description of current route
  # for documentation purposes
  @description: (description) -> (method) -> ->
    if description? and typeof description isnt 'string'
      throw new Error "'description' of the route should be a string"

    @constructor._decoratorMethodBody @, method, arguments, 'description', description

  # routing method decorator specifying if current route method
  # will return only one instance of model or array of instances
  # this parameter is used in server method calles 'swaggerRouteResponse'
  # for documentation purposes
  @many: (many) -> (method) -> ->
    many ?= false
    if many? and typeof many isnt 'boolean'
      throw new Error "'many' attribute should be boolean"

    @constructor._decoratorMethodBody @, method, arguments, 'many', many

  # routing method decorator specifying path parameters of current route
  # (their names and validation object as Joi object)
  # so e.g. '/products/{id}', the param would be 'id' with corresponding validation object as value
  @params: (params) -> (method) -> ->
    params ?= {}
    if params? and typeof params isnt 'object'
      throw new Error "'params' of the routing should be an object'"

    @constructor._decoratorMethodBody @, method, arguments, 'params', params

  # routing method decorator specifying responses of current view
  # for documentation purposes
  @responses: (responses) -> (method) -> ->
    @constructor._decoratorMethodBody @, method, arguments, 'responses', responses

  # routing method decorator specifying validation object of request payload
  @payload: (payload) -> (method) -> ->
    payload ?= {}
    if payload? and typeof payload isnt 'object'
      throw new Error "'payload' of the routing object should be an object"

    @constructor._decoratorMethodBody @, method, arguments, 'payload', payload

  @getAcceptableRouteOptions: ->
    acceptableRouteOptions

  constructor: (@server, @defaultOptions) ->
    # if no default options were passed, set it to an empty object
    @defaultOptions ?= {}

  # method that is used to generate full route object via options passed to the constructor
  # @params [Object] options route options according to Hapi.js route configuration documentation
  _getFullConfiguration: (options) ->
    # throw an error if 'options' is not an object'
    if not (_.isObject options)
      throw new Error "'options' of route should be an object"

    # throw an error if options does not have attributes 'method', 'path' or 'config'
    if 'method' not of options or 'path' not of options or 'config' not of options
      throw new Error "'method', 'path' and 'config' attributes are required for route options!"

    routeObject = {}
    # add method, path and config to route options
    _.extend routeObject, { method: options.method, path: options.path, config: {} }

    # extend route object's config attribute with passed options
    _.each acceptableRouteOptions, (val) ->
      routeObject.config[val] = options.config[val] or @defaultOptions[val] or undefined

    # throw an error if routeObject's config.handler is undefined or is not a function
    if not routeObject.config.handler? or not (typeof routeObject.config.handler is 'function')
      throw new Error "Route options must have 'config.handler()' method defined!"

    routeObject


  # returns basic configuration current route method
  # basing on previously defined decorators
  # @param [String] method - specifies method of current view
  # @param [String] description - description of current view for documentation
  # @param [String] id - id of current Hapi route
  # @param [String] path - path of current view e.g. /users/{id}
  # @param [Boolean] many - defines if view should return multiple records
  # @param [Object] params - object defining validation of path parameters
  # @param [Object] responses - object specifying responses of current view for documentation
  # @param [Object] payload - object fedining validation of request payload
  getBasicConfiguration: ({ method, description, id, path, many, params, responses, payload } = {}) ->
    {
      method: method
      path: path

      config:
        description: description
        tags: @config.tags
        id: id

        security: @defaultOptions.security
        cors: true

        validate:
          headers: @defaultOptions.headersValidation
          params: params
          payload: payload

        plugins:
          'hapi-swagger':
            responses: responses
    }


module.exports = BaseView
