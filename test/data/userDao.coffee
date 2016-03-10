'use strict'

BaseDAO = require './../../lib/dao/baseDao'

class UserDAO extends BaseDAO

  config:
    lookupField: 'id'
    returning:
      basic: ['id', 'username', 'account_category_id as accountCategory']


module.exports = UserDAO
