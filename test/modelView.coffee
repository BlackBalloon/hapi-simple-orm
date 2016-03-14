'use strict'

server      = require './index'

_           = require 'underscore'
Joi         = require 'joi'
chai        = require 'chai'

ModelView   = require './../lib/views/modelView'

User        = require './data/userModel'

chai.should()
expect      = chai.expect

class UserModelView extends ModelView

  config:
    model: User
    tags: ['auth', 'api']

  getAccountCategory:
    @method('GET') \
    @id('getAccountCategory') \
    @path('/users/{id}/account_category') \
    @description('Get account category of user') \
    @params({ id: Joi.number().integer().positive().required() }) \
    @responses({ '200': 'Success', '400': 'Bad request', '404': 'Not found '}) \
    ->
      obj = @getBasicConfiguration arguments['0']

      obj.config.handler = (request, reply) ->
        User.objects().getById({ val: request.params.id }).then (user) ->
          user.get('accountCategory').then (category) ->
            reply category
        .catch (error) ->
          reply(error).code(400)

      obj

userModelView = null

describe 'ModelView tests', ->

  it 'create ModelView for User model with default options', (done) ->
    defaultOptions =
      cors: true
      validate:
        headers: Joi.object(
          'authorization': Joi.string()
        ).unknown()

    userModelView = new UserModelView server, defaultOptions

    expect(userModelView).to.contain.all.keys ['get', 'list', 'update', 'partialUpdate', 'create', 'delete']
    expect(userModelView.get).to.be.a 'function'
    expect(userModelView.list).to.be.a 'function'
    expect(userModelView.create).to.be.a 'function'
    expect(userModelView.update).to.be.a 'function'
    expect(userModelView.partialUpdate).to.be.a 'function'
    expect(userModelView.delete).to.be.a 'function'

    done()

  it 'should add extra options to ModelView method', (done) ->

    options =
      config:
        id: 'createUser'
        description: 'Create new user'
        validate:
          options:
            abortEarly: false
            stripUnknown: true
          payload:
            username: Joi.string().required()

    routeObject = userModelView.create false, null, options

    expect(routeObject).to.have.all.keys ['method', 'path', 'config']
    expect(routeObject.config).to.have.all.keys ['id', 'description', 'validate', 'handler', 'cors', 'tags', 'plugins']

    expect(routeObject.method).to.equal 'POST'
    expect(routeObject.path).to.equal '/users'

    expect(routeObject.config.id).to.equal options.config.id
    expect(routeObject.config.description).to.equal options.config.description
    expect(routeObject.config.validate).to.have.all.keys ['payload', 'options', 'headers']

    done()

  it 'should add all ModelView methods to the server instance', (done) ->

    server.route userModelView.get()
    server.route userModelView.list()
    server.route userModelView.create()
    server.route userModelView.update()
    server.route userModelView.partialUpdate()
    server.route userModelView.delete()

    done()

  it 'should check custom method from UserModelView', (done) ->

    routeObject = userModelView.getAccountCategory()

    expect(routeObject.method).to.equal 'GET'
    expect(routeObject.path).to.equal '/users/{id}/account_category'
    expect(routeObject.config.id).to.equal 'getAccountCategory'

    expect(routeObject.config.plugins['hapi-swagger']).to.have.property 'responses'
    expect(routeObject.config.plugins['hapi-swagger'].responses).to.have.all.keys ['200', '400', '404']
    expect(routeObject.config.plugins['hapi-swagger'].responses['200']).to.be.an 'object'
    expect(routeObject.config.plugins['hapi-swagger'].responses['400']).to.be.an 'object'
    expect(routeObject.config.plugins['hapi-swagger'].responses['404']).to.be.an 'object'

    done()
