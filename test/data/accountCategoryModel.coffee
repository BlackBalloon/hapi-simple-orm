'use strict'

Joi           = require 'joi'

BaseModel     = require './../../lib/model/baseModel'
BaseField     = require './../../lib/fields/baseField'
ManyToOne     = require './../../lib/fields/manyToOne'
ManyToMany    = require './../../lib/fields/manyToMany'

AccountCategoryDAO = require './accountCategoryDao'


accountCategoryAttributes =
  id: new BaseField(
    schema: Joi.number().integer().positive()
    primaryKey: true
  )

  name: new BaseField(
    schema: Joi.string()
    required: true
    name: 'name'
    unique: true
    errorMessages: {}
  )

  users: new ManyToOne(
    toModel: process.cwd() + '/test/data/userModel'
    returning: ['id', 'username']
  )

  permissions: new ManyToMany(
    toModel: process.cwd() + '/test/data/permissionModel'
    through: 'account_categories_permissions'
    returning: ['id', 'name']
  )

metadata =
  tableName: 'account_categories'
  dao: AccountCategoryDAO


class AccountCategory extends BaseModel

  @include accountCategoryAttributes

  @extend metadata


module.exports = AccountCategory
