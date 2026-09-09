const fs = require('fs');
let c = fs.readFileSync('app.js');
let str = c.toString('utf8');
let idx = str.indexOf('w\x00i\x00n\x00');
if (idx !== -1) str = str.substring(0, idx);
str = str.replace(/w i n d o w.*?$/g, '');
fs.writeFileSync('app.js', str + '\n\ndocument.addEventListener("DOMContentLoaded", () => {\n    window.app = new CitizenMobileClient();\n});\n', 'utf8');
