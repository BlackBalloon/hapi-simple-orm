'use strict'

BaseDAO = require './../../lib/dao/baseDao'
AccountCategory = require './accountCategoryModel'

config =
  model: AccountCategory
  returning:
    basic: ['id', 'name']


class AccountCategoryDAO extends BaseDAO

  @applyConfiguration config


module.exports = AccountCategoryDAO
