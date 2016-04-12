'use strict'

BaseDAO = require './../../lib/dao/baseDao'

config = {
  returning:
    basic: [
      '*'
    ]
}

class UserDAO extends BaseDAO

  @applyConfiguration config


module.exports = UserDAO
