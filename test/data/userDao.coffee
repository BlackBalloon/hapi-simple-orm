'use strict'

BaseDAO = require './../../lib/dao/baseDao'

config = {
  returning:
    basic: [
      'id',
      'username',
      'accountCategory'
    ]
}

class UserDAO extends BaseDAO

  @applyConfiguration config


module.exports = UserDAO
