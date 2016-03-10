
exports.up = (knex, Promise) ->

  Promise.join(
    knex.schema.createTableIfNotExists 'account_categories', (table) ->
      table.increments('id').primary()
      table.string('name').notNullable()

      table.timestamp('created_at').defaultTo(knex.fn.now())
      table.integer('who_created_id').nullable()
      table.timestamp('deleted_at').nullable()
      table.integer('who_deleted_id').nullable()
      table.boolean('is_deleted').defaultTo(false).notNullable()

    knex.schema.createTableIfNotExists 'permissions', (table) ->
      table.increments('id').primary()
      table.string('name').notNullable()

      table.timestamp('created_at').defaultTo(knex.fn.now())
      table.integer('who_created_id').nullable()
      table.timestamp('deleted_at').nullable()
      table.integer('who_deleted_id').nullable()
      table.boolean('is_deleted').defaultTo(false).notNullable()

    knex.schema.createTableIfNotExists 'account_categories_permissions', (table) ->
      table.increments('id').primary()
      table.integer('account_category_id').references('account_categories.id')
      table.integer('permission_id').references('permissions.id')

    knex.schema.createTableIfNotExists 'users', (table) ->
      table.increments('id').primary()
      table.string('username').notNullable()
      table.integer('account_category_id').references('account_categories.id').nullable()

      table.timestamp('created_at').defaultTo(knex.fn.now())
      table.integer('who_created_id').nullable()
      table.timestamp('deleted_at').nullable()
      table.integer('who_deleted_id').nullable()
      table.boolean('is_deleted').defaultTo(false).notNullable()
  )

exports.down = (knex, Promise) ->

  Promise.join(
    knex.schema.dropTableIfExists 'users'
    knex.schema.dropTableIfExists 'account_categories_permissions'
    knex.schema.dropTableIfExists 'permissions'
    knex.schema.dropTableIfExists 'account_categories'
  )
