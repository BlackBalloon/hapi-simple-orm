'use strict'

server      = require './index'

request     = require 'supertest'
_           = require 'underscore'
Joi         = require 'joi'
chai        = require 'chai'

knexConf    = require '../knexfile'
knex        = require('knex')(knexConf['test'])

chai.should()
expect      = chai.expect

ModelView   = require './../lib/views/modelView'
BaseField   = require './../lib/fields/baseField'
ForeignKey  = require './../lib/fields/foreignKey'

User        = require './data/userModel'

chai.should()
expect      = chai.expect

class UserModelView extends ModelView

  config:
    model: User
    tags: ['auth', 'api']
    allowTimestampAttributes: true

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
        User.objects().getById({ pk: request.params.id }).then (user) ->
          user.get('accountCategory').then (category) ->
            reply category
        .catch (error) ->
          reply(error).code(400)

      obj

  getUsername:
    @method('get') \
    @path('/users/get_username') \
    @query({ username: Joi.string().required() }) \
    ->
      obj = @getBasicConfiguration arguments['0']

      obj.config.handler = (request, reply) ->
        username = request.query.username + '11'

        return reply { username: username }

      obj

userModelView = null

describe 'ModelView tests', ->

  before (done) ->
    knex.migrate.rollback().then ->
      knex.migrate.latest().then ->
        userData =
          username: 'piobie'

        User.objects().create({ data: userData }).then (user) ->
          done()
    .catch (error) ->
      done error

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

  it 'POST on /users', (done) ->

    data =
      username: 'markas'

    request('http://localhost:3000')
      .post('/users')
      .send(data)
      .expect(201)
      .end (error, response) ->
        if error
          return done error

        expect(response.body).to.contain.all.keys ['id', 'username']
        expect(response.body.username).to.equal data.username

        done()

  it 'GET on /users', (done) ->

    request('http://localhost:3000')
      .get('/users')
      .expect(200)
      .end (error, response) ->
        if error
          return done error

        expect(response.body).to.be.an 'array'
        _.each response.body, (user) ->
          expect(user).to.contain.all.keys ['id', 'username']

        done()

  it 'GET on /users/1', (done) ->

    request('http://localhost:3000')
      .get('/users/1')
      .expect(200)
      .end (error, response) ->
        if error
          return done error

        expect(response.body).to.contain.all.keys ['id', 'username']
        expect(response.body.id).to.equal 1

        done()

  it 'PUT on /users/1', (done) ->

    data =
      username: 'piobie'

    request('http://localhost:3000')
      .put('/users/1')
      .send(data)
      .expect(200)
      .end (error, response) ->
        if error
          return done error

        done()

  it 'PATCH on /users/1', (done) ->

    data =
      username: 'alenow'

    request('http://localhost:3000')
      .patch('/users/1')
      .send(data)
      .expect(200)
      .end (error, response) ->
        if error
          return done error

        expect(response.body).to.contain.all.keys ['id', 'username']
        expect(response.body.username).to.equal data.username

        done()

  it 'should test query fields param on .all()', (done) ->

    request('http://localhost:3000')
      .get('/users?fields=id&fields=username&fields=isDeleted')
      .expect(200)
      .end (error, response) ->

        expect(response.body).to.be.an 'array'
        expect(response.body[0]).to.have.all.keys ['id', 'username', 'isDeleted']

        done()

  it 'should test query fields param on .get()', (done) ->

    request('http://localhost:3000')
      .get('/users/1?fields=id&fields=username')
      .expect(200)
      .end (error, response) ->

        expect(response.body).to.have.all.keys ['id', 'username']

        done()

  it 'should return 400 on query fields param (does not match)', (done) ->

    request('http://localhost:3000')
      .get('/users/1?fields=id&fields=test')
      .expect(400)
      .end (error, response) ->

        expect(response.body.statusCode).to.equal 400;
        expect(response.body).to.have.property 'message';

        done()
