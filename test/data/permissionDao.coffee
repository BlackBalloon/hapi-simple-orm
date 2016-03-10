'use strict'

BaseDAO     = require './../../lib/dao/baseDao'


class PermissionDAO extends BaseDAO

  config:
    lookupField: 'id'
    returning:
      basic: ['id', 'name']


module.exports = PermissionDAO
