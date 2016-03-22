'use strict'

BaseDAO     = require './../../lib/dao/baseDao'

config =
  returning:
    basic: [
      'id'
      'name'
    ]

class PermissionDAO extends BaseDAO

  @applyConfiguration config


module.exports = PermissionDAO
