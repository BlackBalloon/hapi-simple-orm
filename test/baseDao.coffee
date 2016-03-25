'use strict'

_           = require 'underscore'
chai        = require 'chai'
knexConf    = require '../knexfile'
knex        = require('knex')(knexConf['test'])
expect      = chai.expect

User             = require './data/userModel'
AccountCategory  = require './data/accountCategoryModel'
Permission       = require './data/permissionModel'

chai.should()


describe 'BaseDAO tests', ->

  before (done) ->
    knex.migrate.rollback().then ->
      knex.migrate.latest().then ->
        done()
    .catch (error) ->
      done error

  after (done) ->
    knex.migrate.rollback().then ->
      done()
    .catch (error) ->
      done error

  describe 'creating new instances', ->

    it 'should create new account category', (done) ->

      data =
        name: 'admin'

      try
        accountCategory = new AccountCategory data
      catch error
        done error

      expect(accountCategory).to.be.an.instanceOf AccountCategory
      accountCategory.get('name').should.equal data.name

      done()

    it 'should create and save new account category', (done) ->

      data =
        name: 'admin'

      accountCategory = new AccountCategory data

      accountCategory.save().then (result) ->

        result.id.should.equal 1
        result.name.should.equal data.name

        userData =
          username: 'set test'
          accountCategory: result

        user = new User userData
        console.log user

        done()
      .catch (error) ->
        done error

    it 'should create and save new user', (done) ->

      data =
        username: 'piobie'
        accountCategory: 1

      User.objects().create({ data: data }).then (user) ->
        expect(user.id).to.equal 1
        expect(user.accountCategory).to.equal data.accountCategory
        expect(user.username).to.equal data.username
        done()
      .catch (error) ->
        done error

    it 'should create and save new permission', (done) ->

      data =
        name: 'can edit user'

      Permission.objects().create({ data: data }).then (perm) ->
        expect(perm.id).to.equal 1
        expect(perm.name).to.equal data.name
        done()
      .catch (error) ->
        done error

    it 'should add new account category by direct create() on DAO', (done) ->

      data =
        name: 'director'

      AccountCategory.objects().create({ data: data }).then (category) ->
        expect(category).to.be.an.instanceOf AccountCategory
        category.id.should.equal 2
        category.name.should.equal data.name
        done()
      .catch (error) ->
        done error

    it 'should add another account category', (done) ->

      data =
        name: 'employee'

      accountCategory = new AccountCategory data
      accountCategory.save().then (res) ->
        res.id.should.equal 3
        res.name.should.equal data.name
        done()
      .catch (error) ->
        done error

    it 'should return error on category create - unique name', (done) ->

      data =
        name: 'admin'

      accountCategory = new AccountCategory data
      accountCategory.save().then (result) ->
        done new Error 'Test passed, wrong!'
      .catch (error) ->
        expect(error).to.have.property 'name'
        done()

    it 'should return error on user create - foreign key constraint', (done) ->

      data =
        username: 'markas'
        accountCategory: 5

      User.objects().create({ data: data }).then (user) ->
        done new Error 'Test passed, wrong!'
      .catch (error) ->
        error.should.have.property 'accountCategory'
        done()

    it 'should perform bulkCreate of categories', (done) ->

      data = [
        name: 'new category 1'
      ,
        name: 'new category 2'
      ]

      AccountCategory.objects().bulkCreate({ data: _.clone data, toObject: false }).then (categories) ->
        expect(categories).to.be.an 'array'
        expect(categories[0].name).to.equal data[0].name
        expect(categories[1].name).to.equal data[1].name
        done()
      .catch (error) ->
        done error

  describe 'updating instances', ->

    it 'should update account category', (done) ->

      data =
        name: 'editor'

      AccountCategory.objects().getById({ pk: 1 }).then (category) ->
        category.set data
        category.save().then (result) ->
          result.name.should.equal data.name
          done()
      .catch (error) ->
        done error

  describe 'returning instances', ->

    it 'should return category by id with getById method', (done) ->

      AccountCategory.objects().getById({ pk: 1 }).then (category) ->
        category.id.should.equal 1
        done()
      .catch (error) ->
        done error

    it 'should return all account categories', (done) ->

      AccountCategory.objects().all().then (categories) ->
        expect(categories).to.be.an 'array'
        expect(categories.length).to.equal 5
        done()
      .catch (error) ->
        done error

    it 'should order categories by ID descending', (done) ->

      AccountCategory.objects().all({ orderBy: { column: 'id', direction: 'desc' }, returning: ['id'], toObject: false }).then (categories) ->
        expect(categories).to.be.an 'array'
        console.log _.pluck categories, 'id'
        done()
      .catch (error) ->
        done error

    it 'should order categories by name ascending', (done) ->

      AccountCategory.objects().all({ orderBy: 'name', toObject: false, returning: ['name'] }).then (categories) ->
        console.log _.pluck categories, 'name'
        done()
      .catch (error) ->
        done error

    it 'should filter categories by id values in [1, 2]', (done) ->

      AccountCategory.objects().filter({
        lookup: [
          key: 'whereIn'
          values: ['id', [1, 2]]
        ], toObject: false, returning: ['id']
      }).then (categories) ->
        console.log _.pluck categories, 'id'
        done()
      .catch (error) ->
        done error

    it 'should filter categories by name %cat%', (done) ->

      AccountCategory.objects().filter({
        lookup: [
          key: 'where',
          values: ['name', 'like', '%cat%']
        ], toObject: false, returning: ['name']
      }).then (categories) ->
        console.log categories
        done()
      .catch (error) ->
        done error

  describe 'deleting instances', ->

    it 'should delete category with id = 3', (done) ->

      AccountCategory.objects().delete(3).then (result) ->
        expect(result).to.equal 1
        done()
      .catch (error) ->
        done error

  describe 'returning related fields', ->

    it 'should return users of first category', (done) ->

      AccountCategory.objects().getById({ pk: 1 }).then (category) ->
        category.users.all().then (users) ->
          expect(users).to.be.an 'array'
          expect(users.length).to.equal 1
          done()
      .catch (error) ->
        done error

    it 'should return specified user of first category', (done) ->

      AccountCategory.objects().getById({ pk: 1 }).then (category) ->
        category.users.get({ where: { id : 1 }}).then (user) ->
          expect(user.id).to.equal 1
          expect(user.username).to.equal 'piobie'
          done()
      .catch (error) ->
        done error

    it 'should set permissions of first category', (done) ->

      AccountCategory.objects().getById({ pk: 1 }).then (category) ->
        category.permissions.set([1]).then (result) ->
          expect(result).to.be.an 'array'
          expect(_.isEqual(result, [1])).to.equal true
          done()
      .catch (error) ->
        done error

    it 'should return permissions of first category', (done) ->

      AccountCategory.objects().getById({ pk: 1 }).then (category) ->
        category.permissions.all().then (permissions) ->
          expect(permissions).to.be.an 'array'
          expect(permissions[0].id).to.equal 1
          done()
      .catch (error) ->
        done error

    it 'should return specified permission of category', (done) ->

      AccountCategory.objects().getById({ pk: 1 }).then (category) ->
        category.permissions.get({ id: 1 }).then (permission) ->
          expect(permission.id).to.equal 1
          expect(permission.name).to.equal 'can edit user'
          done()
      .catch (error) ->
        done error
