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
    @path('/users/{id}/account_category') \
    ->
      @getBasicConfiguration arguments['0']

userModelView = null

describe 'ModelView tests', ->

  it 'create ModelView for User Model with default options', (done) ->
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
