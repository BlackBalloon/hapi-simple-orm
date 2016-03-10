'use strict'

Joi           = require 'joi'

BaseModel     = require './../../lib/model/baseModel'
BaseField     = require './../../lib/fields/baseField'
ManyToMany    = require './../../lib/fields/manyToMany'

PermissionDAO = require './permissionDao'

permissionAttributes =
  id: new BaseField(
    schema: Joi.number().integer().positive()
    primaryKey: 'id'
  )

  name: new BaseField(
    schema: Joi.string()
    required: true
    unique: true
    name: 'name'
    errorMessages: {}
  )

  accountCategories: new ManyToMany(
    toModel: process.cwd() + '/test/data/accountCategoryModel'
    through: 'account_categories_permissions'
    returning: ['id', 'name']
  )

metadata =
  dao: PermissionDAO


class Permission extends BaseModel

  @include permissionAttributes

  @extend metadata


module.exports = Permission
