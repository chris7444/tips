'use strict';

const express = require('express');
var ip = require('ip');

// Constants
const PORT = 8080;

// App
const app = express();
app.get('/', function (req, res) {
  res.send('Hello world is running on ' + ip.address() + '\n');
});

app.listen(PORT);
console.log('Running on http://' + ip.address() + ':' + PORT );
