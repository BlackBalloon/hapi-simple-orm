'use strict';

const Hapi = require('hapi');

const server = new Hapi.Server();

process.env.NODE_ENV = 'test'

server.connection({
  host: 'localhost',
  port: 3000
});

server.start((err) =>{

  if (err) {
    throw err;
  }

  console.log('Server running at: ', server.info.uri);
});

module.exports = server;
