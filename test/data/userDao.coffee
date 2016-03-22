'use strict'

BaseDAO = require './../../lib/dao/baseDao'
User = require './userModel'

config = {
  model: User
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
