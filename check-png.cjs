const fs = require('fs');
const buffer = fs.readFileSync('public/icon-192.png');
console.log(buffer.slice(0, 8).toString('hex'));
