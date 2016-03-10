module.exports = {
  test: {
    client: 'postgresql',
    connection: {
      database: 'orm_test',
      user: 'postgres',
      password: 'postgres'
    },
    migrations: {
      tableName: 'migrations'
    }
  },
};
