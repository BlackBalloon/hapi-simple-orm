'use strict'

BaseDAO = require './../../lib/dao/baseDao'

config =
  returning:
    basic: ['id', 'name']


class AccountCategoryDAO extends BaseDAO

  @applyConfiguration config


module.exports = AccountCategoryDAO
