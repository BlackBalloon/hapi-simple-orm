'use strict'

BaseDAO = require './../../lib/dao/baseDao'


class AccountCategoryDAO extends BaseDAO

  config:
    lookupField: 'id'
    returning:
      basic: ['id', 'name']


module.exports = AccountCategoryDAO
