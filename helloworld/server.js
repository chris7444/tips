'use strict';

const express = require('express');
var ip = require('ip');

// Constants
const PORT = 8080;

// App
const app = express();
app.get('/', function (req, res) {
  res.send('Hello world V2 is running on ' + ip.address() + '\n');
});

app.listen(PORT);
console.log('V2 Running on http://' + ip.address() + ':' + PORT );
