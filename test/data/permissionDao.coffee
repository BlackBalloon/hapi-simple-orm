'use strict'

BaseDAO     = require './../../lib/dao/baseDao'
Permission  = require './permissionModel'

config =
  model: Permission
  returning:
    basic: [
      'id'
      'name'
    ]

class PermissionDAO extends BaseDAO

  @applyConfiguration config


module.exports = PermissionDAO
