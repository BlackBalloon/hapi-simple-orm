'use strict'

Joi           = require 'joi'

BaseModel   = require './../../lib/model/baseModel'
BaseField   = require './../../lib/fields/baseField'
ForeignKey  = require './../../lib/fields/foreignKey'


AccountCategory = require './accountCategoryModel'

userAttributes =
  id: new BaseField(
    schema: Joi.number().integer().positive()
    primaryKey: true
  )

  username: new BaseField(
    schema: Joi.string()
    required: true
    name: 'username'
    unique: true
    errorMessages: {}
  )

  accountCategory: new ForeignKey(
    referenceModel: AccountCategory
  )


class User extends BaseModel

  @include userAttributes

  @extend {}


module.exports = User
